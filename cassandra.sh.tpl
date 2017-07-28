#!/bin/bash

# Sets the correct hostname, else cassandra won't run
hostnamectl set-hostname cassandra-${node_index}
echo "127.0.0.1 cassandra-${node_index}" | tee /etc/hosts

# Mounts ephemeral storage on /var/lib/cassandra for faster access
function create_fs_and_mount {
    DEVICE_NAME=${ephemeral_disk_device}
    echo "Creating fs and mounting..."
    #mkfs -t ext4 $DEVICE_NAME
    mkdir -p /var/lib/cassandra
    mount $DEVICE_NAME /var/lib/cassandra
    umount /mnt
    # Remove default /mnt mount for instance store
    sed -i '/\/mnt/d' /etc/fstab
    echo '${ephemeral_disk_device} /var/lib/cassandra ext4 defaults 0 0' | tee --append /etc/fstab
    echo "Done creating fs and mounting."
}
create_fs_and_mount

# Cassandra installation. Largely leveraged from https://github.com/Jagatveersingh/terraform-cassandra-multinode
apt-get update
apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys 0x219BD9C9
apt_source='deb http://repos.azulsystems.com/debian stable main'
apt_list='/etc/apt/sources.list.d/zulu.list'
echo "$apt_source" | sudo tee "$apt_list" > /dev/null
apt-get update
apt-get install -y zulu-8
apt-get install -y python-pip
pip install cassandra-driver
echo "deb http://debian.datastax.com/community stable main" | sudo tee -a /etc/apt/sources.list.d/cassandra.sources.list
curl -L https://debian.datastax.com/debian/repo_key | apt-key add -
apt-get update
apt-get install -y gcc libev4 libev-dev python-dev
apt-get install -y dsc30 -V
apt-get install -y cassandra-tools
service cassandra stop
rm -rf /var/lib/cassandra/data/system/*
sed -i "s/cluster_name: 'Test Cluster'/cluster_name: '${cassandra_cluster_name}'/g" /etc/cassandra/cassandra.yaml
#Seed nodes are used to bootstrap new nodes into the cluster.  Without a seed node new nodes can't join.  Too many is bad but there should be more than one.
sed -i "s/seeds: \"127.0.0.1\"/seeds: \"${cassandra_seed_ips}\"/g" /etc/cassandra/cassandra.yaml
sed -i "s/listen_address: localhost/listen_address: ${private_ip}/g" /etc/cassandra/cassandra.yaml
sed -i "s/rpc_address: localhost/rpc_address: 0.0.0.0/g" /etc/cassandra/cassandra.yaml
sed -i "s/# broadcast_rpc_address: 1.2.3.4/broadcast_rpc_address: ${private_ip}/g" /etc/cassandra/cassandra.yaml

service cassandra start


# Set up SSH keys
cat <<"EOF" > /home/${ssh_user}/update_ssh_authorized_keys.sh
#!/usr/bin/env bash
set -e
BUCKET_NAME=${s3_bucket_name}
SSH_USER=${ssh_user}
MARKER="# KEYS_BELOW_WILL_BE_UPDATED_BY_TERRAFORM"
KEYS_FILE=/home/$SSH_USER/.ssh/authorized_keys
TEMP_KEYS_FILE=$(mktemp /tmp/authorized_keys.XXXXXX)
PUB_KEYS_DIR=/home/$SSH_USER/pub_key_files/
PATH=/usr/local/bin:$PATH
BUCKET_URI="s3://$BUCKET_NAME/"
mkdir -p $PUB_KEYS_DIR
# Add marker, if not present, and copy static content.
grep -Fxq "$MARKER" $KEYS_FILE || echo -e "\n$MARKER" >> $KEYS_FILE
line=$(grep -n "$MARKER" $KEYS_FILE | cut -d ":" -f 1)
head -n $line $KEYS_FILE > $TEMP_KEYS_FILE
# Synchronize the keys from the bucket.
aws s3 sync --delete $BUCKET_URI $PUB_KEYS_DIR
for filename in $PUB_KEYS_DIR/*; do
    sed 's/\n\?$/\n/' < $filename >> $TEMP_KEYS_FILE
done
# Move the new authorized keys in place.
chown $SSH_USER:$SSH_USER $KEYS_FILE
chmod 600 $KEYS_FILE
mv $TEMP_KEYS_FILE $KEYS_FILE
if [[ $(command -v "selinuxenabled") ]]; then
    restorecon -R -v $KEYS_FILE
fi
EOF

cat <<"EOF" > /home/${ssh_user}/.ssh/config
Host *
    StrictHostKeyChecking no
EOF
chmod 600 /home/${ssh_user}/.ssh/config
chown ${ssh_user}:${ssh_user} /home/${ssh_user}/.ssh/config

chown ${ssh_user}:${ssh_user} /home/${ssh_user}/update_ssh_authorized_keys.sh
chmod 755 /home/${ssh_user}/update_ssh_authorized_keys.sh

# Execute now
su ${ssh_user} -c /home/${ssh_user}/update_ssh_authorized_keys.sh

# Be backwards compatible with old cron update enabler
if [ "${enable_hourly_cron_updates}" = 'true' -a -z "${keys_update_frequency}" ]; then
  keys_update_frequency="0 * * * *"
else
  keys_update_frequency="${keys_update_frequency}"
fi

# Add to cron
if [ -n "$keys_update_frequency" ]; then
  croncmd="/home/${ssh_user}/update_ssh_authorized_keys.sh"
  cronjob="$keys_update_frequency $croncmd"
  ( crontab -u ${ssh_user} -l | grep -v "$croncmd" ; echo "$cronjob" ) | crontab -u ${ssh_user} -
fi
