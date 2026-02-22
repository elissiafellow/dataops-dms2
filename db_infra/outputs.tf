# Outputs for database infrastructure

output "source_db_endpoint" {
  description = "RDS endpoint for source database"
  value       = aws_db_instance.source_db.endpoint
}

output "source_db_address" {
  description = "RDS address for source database (hostname only)"
  value       = aws_db_instance.source_db.address
}

output "source_db_port" {
  description = "RDS port for source database"
  value       = aws_db_instance.source_db.port
}

output "dest_db_endpoint" {
  description = "RDS endpoint for destination database"
  value       = aws_db_instance.dest_db.endpoint
}

output "dest_db_address" {
  description = "RDS address for destination database (hostname only)"
  value       = aws_db_instance.dest_db.address
}

output "dest_db_port" {
  description = "RDS port for destination database"
  value       = aws_db_instance.dest_db.port
}

output "db_security_group_id" {
  description = "Security group ID for databases"
  value       = aws_security_group.db_sg.id
}

output "db_subnet_group_name" {
  description = "DB subnet group name"
  value       = aws_db_subnet_group.db_subnet.name
}

output "source_db_connection_string" {
  description = "MySQL connection string for source database"
  value       = "mysql://${aws_db_instance.source_db.username}:${var.db_password}@${aws_db_instance.source_db.address}:${aws_db_instance.source_db.port}/${var.source_db_name}"
  sensitive   = true
}

output "dest_db_connection_string" {
  description = "MySQL connection string for destination database"
  value       = "mysql://${aws_db_instance.dest_db.username}:${var.db_password}@${aws_db_instance.dest_db.address}:${aws_db_instance.dest_db.port}/${var.dest_db_name}"
  sensitive   = true
}
