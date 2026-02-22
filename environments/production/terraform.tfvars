bastion_key_name   = "production-kafka-cluster-eks-vpc-bastion-host-key"
bastion_ami    = "ami-0e54671bdf3c8ed8d"
allowed_ips    =  ["41.187.108.120/29", "41.33.74.216/29", "41.187.93.208/29", "41.33.73.8/29", "35.235.240.0/20","154.178.35.29/32"]
vpc_name       = "kafka-cluster-eks-vpc"
env              = "production"
eks_name         = "kafka-cluster"
eks_version      = "1.31"
vpc_cidr       = "10.240.0.0/16"
public_subnets = ["10.240.1.0/24", "10.240.2.0/24"]
private_subnets = ["10.240.3.0/24", "10.240.4.0/24"]
outpost_private_subnets = ["10.240.100.0/24", "10.240.101.0/24"]
azs            = ["eu-central-1a","eu-central-1b"]
region       = "eu-central-1"

# rds_vpc_cidr = "10.0.0.0/16" # RDS VPC CIDR
# rds_vpc_id = "vpc-04447702574b393ef" # RDS VPC ID
# rds_route_table_id = "rtb-077937aea323b4f6d" #"kafka-cluster-eks-vpc-private-rt" #RDS VPC's private route table