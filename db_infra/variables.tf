variable "environment" {
  description = "Environment name (should match demo-env/infra environment)"
  type        = string
  default     = "demo"
}

variable "vpc_name" {
  description = "Name tag of the VPC created by demo-env/infra (e.g., 'demo-vpc')"
  type        = string
  default     = "demo-vpc"
}

variable "db_instance_class" {
  description = "RDS instance class for databases"
  type        = string
  default     = "db.t3.micro" # Smallest/cheapest for demos
}

variable "db_allocated_storage" {
  description = "Initial allocated storage in GB"
  type        = number
  default     = 20 # Minimum for MySQL
}

variable "db_max_allocated_storage" {
  description = "Maximum storage for autoscaling (0 to disable)"
  type        = number
  default     = 100
}

variable "mysql_version" {
  description = "MySQL engine version"
  type        = string
  default     = "8.0"
}

variable "source_db_name" {
  description = "Name of the source database"
  type        = string
  default     = "sourcedb"
}

variable "dest_db_name" {
  description = "Name of the destination database"
  type        = string
  default     = "destdb"
}

variable "db_username" {
  description = "Master username for databases"
  type        = string
  default     = "admin"
  sensitive   = true
}

variable "db_password" {
  description = "Master password for databases"
  type        = string
  default     = "Admin123!" # Change this in production!
  sensitive   = true
}

variable "db_publicly_accessible" {
  description = "Whether databases should be publicly accessible (for testing)"
  type        = bool
  default     = true # Set to false for production
}

variable "allowed_external_ips" {
  description = "List of CIDR blocks allowed to access databases from outside VPC"
  type        = list(string)
  default     = [] # Empty by default - only VPC access
}
