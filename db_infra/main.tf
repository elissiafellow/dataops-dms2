# Database Infrastructure for DMS/Kafka Testing
# Creates source and destination MySQL databases in the same VPC as EKS cluster

# Data source to get VPC information from demo-env infrastructure
# This assumes the VPC is already created by demo-env/infra/
data "aws_vpc" "main" {
  filter {
    name   = "tag:Name"
    values = [var.vpc_name]
  }
}

# Get public subnets from the VPC (required for publicly accessible databases)
# RDS requires subnets in at least 2 availability zones
data "aws_subnets" "public" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.main.id]
  }
  filter {
    name   = "tag:Type"
    values = ["public"]
  }
}

# Security group for database access
# Allows access from EKS cluster and optionally from your IP
resource "aws_security_group" "db_sg" {
  name        = "${var.environment}-db-sg"
  description = "Security group for source and destination databases"
  vpc_id      = data.aws_vpc.main.id

  # Allow MySQL access from VPC CIDR (EKS cluster can access)
  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.main.cidr_block]
    description = "MySQL access from VPC"
  }

  # Optionally allow access from specific IPs (for testing from local machine)
  dynamic "ingress" {
    for_each = var.allowed_external_ips
    content {
      from_port   = 3306
      to_port     = 3306
      protocol    = "tcp"
      cidr_blocks = [ingress.value]
      description = "MySQL access from external IP"
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = {
    Name        = "${var.environment}-db-sg"
    Environment = var.environment
    Purpose     = "DMS-Kafka-Testing"
  }
}

# DB Subnet Group
# RDS requires subnets in at least 2 AZs
resource "aws_db_subnet_group" "db_subnet" {
  name       = "${var.environment}-db-subnet-group"
  subnet_ids = data.aws_subnets.public.ids

  tags = {
    Name        = "${var.environment}-db-subnet-group"
    Environment = var.environment
  }
}

# DB Parameter Group for MySQL with CDC (Change Data Capture) settings
# Required for DMS to capture binlog changes
resource "aws_db_parameter_group" "mysql_dms_cdc" {
  name        = "${var.environment}-mysql-dms-cdc"
  family      = "mysql8.0"
  description = "MySQL parameter group for DMS CDC with binlog enabled"

  parameter {
    name  = "binlog_format"
    value = "ROW"
  }

  parameter {
    name  = "binlog_row_image"
    value = "FULL"
  }

  parameter {
    name  = "binlog_checksum"
    value = "NONE"
  }

  tags = {
    Name        = "${var.environment}-mysql-dms-cdc"
    Environment = var.environment
  }
}

# Source Database
# This is the database that will be replicated/migrated
resource "aws_db_instance" "source_db" {
  identifier             = "${var.environment}-source-db"
  allocated_storage      = var.db_allocated_storage
  engine                 = "mysql"
  engine_version         = var.mysql_version
  instance_class         = var.db_instance_class
  db_name                = var.source_db_name
  username               = var.db_username
  password               = var.db_password
  db_subnet_group_name   = aws_db_subnet_group.db_subnet.name
  vpc_security_group_ids = [aws_security_group.db_sg.id]
  parameter_group_name   = aws_db_parameter_group.mysql_dms_cdc.name

  # Enable binlog for CDC (Change Data Capture)
  # backup_retention_period > 0 enables automated backups which enable binlog
  backup_retention_period = 1
  backup_window           = "03:00-04:00"
  maintenance_window      = "mon:04:00-mon:05:00"

  # For demo/testing - skip final snapshot on destroy
  skip_final_snapshot = true
  deletion_protection = false

  # Make publicly accessible for testing (optional - set to false for production)
  publicly_accessible = var.db_publicly_accessible

  # Apply changes immediately
  apply_immediately = true

  # Enable storage autoscaling for demo (optional)
  max_allocated_storage = var.db_max_allocated_storage

  # Disable performance insights to save costs
  performance_insights_enabled = false

  tags = {
    Name        = "${var.environment}-source-db"
    Environment = var.environment
    Purpose     = "DMS-Source"
    Database    = "MySQL"
  }
}

# Destination Database
# This is where data will be replicated/migrated to
resource "aws_db_instance" "dest_db" {
  identifier             = "${var.environment}-dest-db"
  allocated_storage      = var.db_allocated_storage
  engine                 = "mysql"
  engine_version         = var.mysql_version
  instance_class         = var.db_instance_class
  db_name                = var.dest_db_name
  username               = var.db_username
  password               = var.db_password
  db_subnet_group_name   = aws_db_subnet_group.db_subnet.name
  vpc_security_group_ids = [aws_security_group.db_sg.id]
  parameter_group_name   = aws_db_parameter_group.mysql_dms_cdc.name

  # Backup settings
  backup_retention_period = 1
  backup_window           = "03:00-04:00"
  maintenance_window      = "mon:04:00-mon:05:00"

  # For demo/testing - skip final snapshot on destroy
  skip_final_snapshot = true
  deletion_protection = false

  # Make publicly accessible for testing (optional)
  publicly_accessible = var.db_publicly_accessible

  # Apply changes immediately
  apply_immediately = true

  # Enable storage autoscaling
  max_allocated_storage = var.db_max_allocated_storage

  # Disable performance insights for cost savings
  performance_insights_enabled = false

  tags = {
    Name        = "${var.environment}-dest-db"
    Environment = var.environment
    Purpose     = "DMS-Destination"
    Database    = "MySQL"
  }
}

# ============================================================================
# AWS Secrets Manager secrets for Kafka Connectors
# These secrets are used by External Secrets Operator to sync to Kubernetes
# ============================================================================

# ============================================================================
# INNOV8-SYSTEM SECRETS
# ============================================================================

resource "aws_secretsmanager_secret" "source_innov8_mysql" {
  name        = "source-innov8-mysql"
  description = "MySQL connection credentials for innov8-system source database"

  tags = {
    Name        = "source-innov8-mysql"
    Environment = var.environment
    Purpose     = "Kafka-Connector"
  }
}

resource "aws_secretsmanager_secret_version" "source_innov8_mysql" {
  secret_id = aws_secretsmanager_secret.source_innov8_mysql.id
  secret_string = jsonencode({
    user     = var.db_username
    password = var.db_password
    host     = aws_db_instance.source_db.address
    database = "innov8-system"
  })

  depends_on = [aws_db_instance.source_db]
}

resource "aws_secretsmanager_secret" "destination_innov8_mysql" {
  name        = "destination-innov8-mysql"
  description = "MySQL connection credentials for innov8-system destination database"

  tags = {
    Name        = "destination-innov8-mysql"
    Environment = var.environment
    Purpose     = "Kafka-Connector"
  }
}

resource "aws_secretsmanager_secret_version" "destination_innov8_mysql" {
  secret_id = aws_secretsmanager_secret.destination_innov8_mysql.id
  secret_string = jsonencode({
    user     = var.db_username
    password = var.db_password
    host     = aws_db_instance.dest_db.address
    database = "innov8-system"
  })

  depends_on = [aws_db_instance.dest_db]
}

# ============================================================================
# NI SECRETS
# ============================================================================

resource "aws_secretsmanager_secret" "source_ni_mysql" {
  name        = "source-ni-mysql"
  description = "MySQL connection credentials for ni source database"

  tags = {
    Name        = "source-ni-mysql"
    Environment = var.environment
    Purpose     = "Kafka-Connector"
  }
}

resource "aws_secretsmanager_secret_version" "source_ni_mysql" {
  secret_id = aws_secretsmanager_secret.source_ni_mysql.id
  secret_string = jsonencode({
    user     = var.db_username
    password = var.db_password
    host     = aws_db_instance.source_db.address
    database = "ni"
  })

  depends_on = [aws_db_instance.source_db]
}

resource "aws_secretsmanager_secret" "destination_ni_mysql" {
  name        = "destination-ni-mysql"
  description = "MySQL connection credentials for ni destination database"

  tags = {
    Name        = "destination-ni-mysql"
    Environment = var.environment
    Purpose     = "Kafka-Connector"
  }
}

resource "aws_secretsmanager_secret_version" "destination_ni_mysql" {
  secret_id = aws_secretsmanager_secret.destination_ni_mysql.id
  secret_string = jsonencode({
    user     = var.db_username
    password = var.db_password
    host     = aws_db_instance.dest_db.address
    database = "ni"
  })

  depends_on = [aws_db_instance.dest_db]
}

# ============================================================================
# LOYALTY SECRETS
# ============================================================================

resource "aws_secretsmanager_secret" "source_loyalty_mysql" {
  name        = "source-loyalty-mysql"
  description = "MySQL connection credentials for loyalty source database"

  tags = {
    Name        = "source-loyalty-mysql"
    Environment = var.environment
    Purpose     = "Kafka-Connector"
  }
}

resource "aws_secretsmanager_secret_version" "source_loyalty_mysql" {
  secret_id = aws_secretsmanager_secret.source_loyalty_mysql.id
  secret_string = jsonencode({
    user     = var.db_username
    password = var.db_password
    host     = aws_db_instance.source_db.address
    database = "loyalty"
  })

  depends_on = [aws_db_instance.source_db]
}

resource "aws_secretsmanager_secret" "destination_loyalty_mysql" {
  name        = "destination-loyalty-mysql"
  description = "MySQL connection credentials for loyalty destination database"

  tags = {
    Name        = "destination-loyalty-mysql"
    Environment = var.environment
    Purpose     = "Kafka-Connector"
  }
}

resource "aws_secretsmanager_secret_version" "destination_loyalty_mysql" {
  secret_id = aws_secretsmanager_secret.destination_loyalty_mysql.id
  secret_string = jsonencode({
    user     = var.db_username
    password = var.db_password
    host     = aws_db_instance.dest_db.address
    database = "loyalty"
  })

  depends_on = [aws_db_instance.dest_db]
}
