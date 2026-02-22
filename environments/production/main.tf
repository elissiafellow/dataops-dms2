
# resource "aws_s3_bucket" "terraform-state" {
#   bucket = "tfstate-${var.env}-${var.eks_name}"
# }

# resource "aws_s3_bucket_versioning" "terraform-state" {
#   bucket = aws_s3_bucket.terraform-state.id
#   versioning_configuration {
#     status = "Enabled"
#   }
# }

# resource "aws_dynamodb_table" "state_lock_table" {
#   name           = "terraform_state_lock"
#   billing_mode   = "PAY_PER_REQUEST"
#   hash_key       = "LockID"
#   attribute {
#     name = "LockID"
#     type = "S"
#   }
# }

module "vpc" {
  source = "../modules/vpc"
  vpc_cidr         = var.vpc_cidr
  vpc_name         = var.vpc_name
  public_subnets   = var.public_subnets
  private_subnets  = var.private_subnets
  outpost_private_subnets = var.outpost_private_subnets
  azs              = var.azs
  env              = var.env
  eks_name  = var.eks_name

  providers = {
    aws = aws.dataops-account
  }
}

module "eks" {
  source = "../modules/eks"
  private_subnet_ids = concat(module.vpc.outpost_private_subnet_ids, module.vpc.private_subnet_ids)

  eks_name         = var.eks_name
  eks_version      = var.eks_version
  env              = var.env
  eks_sg_id     = module.vpc.eks_sg_id
  providers = {
    aws = aws.dataops-account
  }


  depends_on = [module.vpc]
}

module "eks-bastion-association" {
  source = "../modules/eks-bastion-association"
  cluster_name = module.eks.cluster_name
  providers = {
    aws = aws.dataops-account
  }
  depends_on = [module.eks]
}

module "bastion" {
  source = "../modules/bastion"
  ami           = var.bastion_ami
  instance_profile_name = module.eks-bastion-association.instance_profile
  vpc_id        = module.vpc.vpc_id
  vpc_name      = var.vpc_name
  public_subnet_id = element(module.vpc.public_subnet_ids, 0)  # Choose the first public subnet
  allowed_ips   = var.allowed_ips
  key_name      = var.bastion_key_name
  ssh_pem_bucket  = "moneyfellows-prod-dms-statefiles"
  env           = var.env
  providers = {
    aws = aws.dataops-account
    tls = tls
  }

  depends_on = [module.vpc]
}

module "ecr" {
  source = "../modules/ecr"
  aws_region = var.region
  repository_name = "kafka-cluster"
  image_name = "kafka-connect-cluster-image"

    providers = {
    aws = aws.dataops-account
    null = null
  }
}

# module "vpc_peering" {
#   source                     = "../modules/vpc-peering"
#   peer_region                = var.region
#   vpc_id                     = module.vpc.vpc_id # Requester VPC ID
#   peer_vpc_id                = var.rds_vpc_id
#   peer_owner_id              = data.aws_caller_identity.rds.account_id
#   acceptor_cidr_block        = var.rds_vpc_cidr
#   requestor_cidr_block       = var.vpc_cidr
#   route_table_id             = module.vpc.private_route_table_id
#   accepter_route_table_id    = var.rds_route_table_id

#   providers = {
#     aws.src = aws.dataops-account
#     aws.dst = aws.rds_account
#   }
# }