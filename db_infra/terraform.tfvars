# Database Infrastructure Configuration
# This creates source and destination MySQL databases for DMS/Kafka testing

# Environment - should match demo-env/infra environment
environment = "demo"

# VPC name - should match the VPC created by demo-env/infra
# Check demo-env/infra/main.tf for the VPC name tag
vpc_name = "demo-vpc"

# AWS Region - should match demo-env/infra region
aws_region = "eu-central-1"

# Database Configuration
db_instance_class        = "db.t3.micro" # Smallest instance for demos (~$15/month each)
db_allocated_storage     = 20            # Minimum 20GB for MySQL
db_max_allocated_storage = 100           # Auto-scale up to 100GB if needed
mysql_version            = "8.0"

# Database Names
source_db_name = "sourcedb"
dest_db_name   = "destdb"

# Database Credentials
# ⚠️  CHANGE THESE IN PRODUCTION!
db_username = "admin"
db_password = "Admin123!"

# Network Configuration
db_publicly_accessible = true # Set to false for production (requires bastion/VPN)

# External IPs allowed to access databases (optional)
# Add your IP here if you want to connect from your local machine
# Example: ["1.2.3.4/32", "5.6.7.8/32"]
allowed_external_ips = []
