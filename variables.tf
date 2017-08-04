variable number_of_seeds { }
variable private_subnet_ids { type = "list" }
variable cassandra_seed_ips { type = "list" }
variable instance_type { }
variable ssh_public_key { }
variable vpc_id { }
variable vpc_cidr { }
variable ephemeral_disk_device { default = "/dev/xvdh" }
variable cassandra_cluster_name { }
variable depends_id { }
variable ssh_key_s3_bucket { }
variable ssh_user { default = "ubuntu" }
variable enable_hourly_cron_updates { default = "false" }
variable keys_update_frequency { default = "" }
variable r53_zone_id { }
variable cassandra_subdomain { default = "cassandra" }
variable r53_domain { }
