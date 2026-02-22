# Database Infrastructure for DMS/Kafka Testing

This Terraform configuration creates **source and destination MySQL databases** for testing Database Migration Service (DMS) and Kafka CDC (Change Data Capture) workflows.

## Overview

Creates two MySQL RDS instances:
- **Source Database**: The database that will be replicated/migrated
- **Destination Database**: The target database for replication

Both databases are configured with:
- ✅ Binlog enabled for CDC (Change Data Capture)
- ✅ Same VPC as EKS cluster (from `demo-env/infra/`)
- ✅ Security groups allowing access from EKS cluster
- ✅ Parameter groups optimized for DMS

## Prerequisites

1. **EKS Cluster Created**: The VPC from `demo-env/infra/` must be created first
2. **AWS Credentials**: Configured via `aws configure` or environment variables
3. **Terraform**: Version 1.5.0 or higher

## Quick Start

### Step 1: Verify VPC Exists

Make sure you've created the EKS cluster using `demo-env/infra/`:

```bash
cd ../demo-env/infra
terraform apply
```

Note the VPC name tag (should be `demo-vpc` by default).

### Step 2: Configure Variables

Edit `terraform.tfvars`:

```hcl
environment = "demo"
vpc_name    = "demo-vpc"  # Must match VPC name from demo-env/infra
aws_region  = "eu-central-1"

# Optional: Add your IP for external access
allowed_external_ips = ["YOUR_IP/32"]
```

### Step 3: Initialize and Apply

```bash
cd dataops-dms2/db_infra
terraform init
terraform plan
terraform apply
```

### Step 4: Get Database Endpoints

```bash
# Get source database endpoint
terraform output source_db_endpoint

# Get destination database endpoint
terraform output dest_db_endpoint

# Get connection strings (sensitive)
terraform output -json
```

## Configuration

### Database Settings

| Setting | Default | Description |
|---------|---------|-------------|
| Instance Class | `db.t3.micro` | Smallest/cheapest for demos |
| Storage | 20 GB | Minimum for MySQL |
| Max Storage | 100 GB | Auto-scaling limit |
| MySQL Version | 8.0 | Latest stable |
| Public Access | `true` | For testing (set `false` for production) |

### Binlog Configuration

The databases are configured with:
- `binlog_format = ROW` - Required for DMS CDC
- `binlog_row_image = FULL` - Captures all column data
- `binlog_checksum = NONE` - Required for DMS

These settings are in the parameter group `mysql_dms_cdc`.

### Security

- **VPC Access**: Databases are accessible from within the VPC (EKS cluster can connect)
- **External Access**: Optional - configure `allowed_external_ips` in `terraform.tfvars`
- **Security Group**: Allows MySQL (port 3306) from VPC CIDR

## Outputs

After applying, you'll get:

- `source_db_endpoint` - Full endpoint (hostname:port)
- `source_db_address` - Hostname only
- `source_db_port` - Port (3306)
- `dest_db_endpoint` - Full endpoint
- `dest_db_address` - Hostname only
- `dest_db_port` - Port (3306)
- `db_security_group_id` - Security group ID (for DMS configuration)
- `db_subnet_group_name` - Subnet group name (for DMS configuration)
- Connection strings (sensitive)

## Cost Estimate

**Per Database** (db.t3.micro):
- Instance: ~$15/month
- Storage (20GB gp2): ~$2.30/month
- **Total per DB**: ~$17/month
- **Both databases**: ~$34/month

**Note**: This is for demo/testing. Production databases will cost more.

## Usage with DMS

After creating the databases, you can:

1. **Create DMS Endpoints**: Use the database endpoints as source and target
2. **Configure Kafka Connect**: Use source DB for Debezium CDC connector
3. **Test Replication**: Verify data flows from source to destination

### Example: Connect from EKS Pod

```bash
# From a pod in the EKS cluster
mysql -h <source_db_address> -u admin -pAdmin123! sourcedb
```

### Example: Connect from Local Machine

If you added your IP to `allowed_external_ips`:

```bash
mysql -h <source_db_address> -u admin -pAdmin123! sourcedb
```

## Troubleshooting

### Database Not Accessible from EKS

1. **Check Security Group**: Ensure it allows traffic from VPC CIDR
2. **Check Subnet Group**: Databases must be in private subnets
3. **Check VPC Name**: Verify `vpc_name` matches the actual VPC name tag

### Cannot Find VPC

```bash
# List VPCs to find the correct name
aws ec2 describe-vpcs --query 'Vpcs[*].[VpcId,Tags[?Key==`Name`].Value|[0]]' --output table
```

### Database Creation Fails

- **Subnet Issue**: Ensure at least 2 subnets in different AZs exist
- **Instance Class**: Some regions may not have `db.t3.micro` - try `db.t3.small`
- **Storage**: Minimum 20GB required for MySQL

## Cleanup

To destroy the databases:

```bash
terraform destroy
```

**Warning**: This will delete both databases and all data. Make sure you have backups if needed.

## Next Steps

After creating the databases:

1. **Initialize Source Database**: Run SQL scripts to create tables and seed data
2. **Configure DMS**: Set up replication task
3. **Configure Kafka Connect**: Set up Debezium connector for CDC
4. **Test Workflow**: Verify data flows from source → Kafka → destination

## Security Best Practices

For production:

1. **Change Default Password**: Use AWS Secrets Manager instead of hardcoded passwords
2. **Disable Public Access**: Set `db_publicly_accessible = false`
3. **Use VPC Peering/VPN**: Access databases through secure network
4. **Enable Encryption**: Add `storage_encrypted = true`
5. **Enable Backup**: Increase `backup_retention_period`
6. **Enable Monitoring**: Enable CloudWatch monitoring and Performance Insights

## Integration with demo-env/infra

This infrastructure is designed to work with the VPC created by `demo-env/infra/`:

```
demo-env/infra/
  └── Creates VPC, EKS cluster, subnets

dataops-dms2/db_infra/
  └── Creates databases in the same VPC
```

The databases will be accessible from:
- EKS cluster pods (same VPC)
- Bastion host (if created)
- Your local machine (if IP whitelisted)
