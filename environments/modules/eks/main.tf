resource "aws_iam_role" "eks" {
  name = "${var.env}-${var.eks_name}-eks-cluster-role"

  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "eks.amazonaws.com"
      }
    }
  ]
}
POLICY

  tags = {
    Name = "${var.env}-${var.eks_name}-eks-role"
    Environment = var.env
  }
}

resource "aws_iam_role_policy_attachment" "eks" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks.name

  depends_on = [aws_iam_role.eks]
}

resource "aws_eks_cluster" "eks" {
  name     = "${var.env}-${var.eks_name}"
  version  = var.eks_version
  role_arn = aws_iam_role.eks.arn

  enabled_cluster_log_types = [
    "api",
    "audit",
    "authenticator",
    "controllerManager",
    "scheduler"
  ]
  vpc_config {
    endpoint_private_access = true
    endpoint_public_access  = false
    subnet_ids              = var.private_subnet_ids
    security_group_ids      = [var.eks_sg_id] #-->> additional security groups to be attached with the eni of the control plane and all the worker nodes
  }
   access_config {
    authentication_mode                         = "API"
    bootstrap_cluster_creator_admin_permissions = true
  }

  tags = {
    Name = "${var.env}-${var.eks_name}"
    Environment = var.env
  }

  depends_on = [aws_iam_role.eks, aws_iam_role_policy_attachment.eks]
}

resource "aws_iam_role" "nodes" {
  name = "${var.env}-${var.eks_name}-eks-nodes"

  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      }
    }
  ]
}
POLICY
}

resource "aws_iam_role_policy_attachment" "amazon_eks_worker_node_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.nodes.name
  depends_on = [aws_iam_role.nodes]
}

resource "aws_iam_role_policy_attachment" "amazon_eks_cni_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.nodes.name
  depends_on = [aws_iam_role.nodes]
}

resource "aws_iam_role_policy_attachment" "amazon_ec2_container_registry_read_only" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.nodes.name
  depends_on = [aws_iam_role.nodes]
}

resource "aws_iam_role_policy_attachment" "amazon_ec2_ebs_driver_policy" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
  role       = aws_iam_role.nodes.name
  depends_on = [aws_iam_role.nodes]
}

resource "aws_iam_role_policy_attachment" "amazon_cloudwatch_agent" {
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
  role       = aws_iam_role.nodes.name
  depends_on = [aws_iam_role.nodes]
}

module "self_managed_node_group_kafka_cluster" {
  source = "terraform-aws-modules/eks/aws//modules/self-managed-node-group"
  version = "20.31.6"

  name                = "kafka-cluster"
  cluster_name        = aws_eks_cluster.eks.name
  cluster_version     = var.eks_version
  cluster_endpoint    = aws_eks_cluster.eks.endpoint
  cluster_auth_base64 = aws_eks_cluster.eks.certificate_authority[0].data
  cluster_service_cidr = aws_eks_cluster.eks.kubernetes_network_config[0].service_ipv4_cidr
  cluster_primary_security_group_id	= aws_eks_cluster.eks.vpc_config[0].cluster_security_group_id
  subnet_ids = [var.private_subnet_ids[0]]

  vpc_security_group_ids = [
    aws_eks_cluster.eks.vpc_config[0].cluster_security_group_id,
    var.eks_sg_id
  ]
  iam_role_additional_policies = {
    amazon_eks_worker_node_policy           = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
    amazon_eks_cni_policy                   = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
    amazon_ec2_container_registry_read_only = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
    amazon_ec2_ebs_driver_policy           = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
    amazon_cloudwatch_agent                 = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
  }

  launch_template_name   = "kafka-cluster"

  block_device_mappings = [
        {
          device_name = "/dev/xvda"
          # no_device = true
 
          ebs = {
            volume_size = 20
            volume_type = "gp2"
          }
        }
      ]

  min_size     = 3
  max_size     = 4
  desired_size = 3

  # ami_type      = "AL2023_x86_64_STANDARD" ## kubelet-extra-args  does not work with this image
  instance_type        = "m5.xlarge"

  bootstrap_extra_args = "--kubelet-extra-args '--node-labels=kafka-cluster-role=kafka-cluster'"

  tags = {
    Name        = "${var.env}-${var.eks_name}-kafka-cluster-ng"
    Environment = var.env
  }
  depends_on = [
    aws_iam_role_policy_attachment.amazon_eks_worker_node_policy,
    aws_iam_role_policy_attachment.amazon_eks_cni_policy,
    aws_iam_role_policy_attachment.amazon_ec2_container_registry_read_only,
    aws_iam_role_policy_attachment.amazon_ec2_ebs_driver_policy,
    aws_iam_role_policy_attachment.amazon_cloudwatch_agent
  ]
}


module "self_managed_node_group_kafka_connect" {
  source = "terraform-aws-modules/eks/aws//modules/self-managed-node-group"
  version = "20.31.6"

  name                = "kafka-connect"
  cluster_name        = aws_eks_cluster.eks.name
  cluster_version     = var.eks_version
  cluster_endpoint    = aws_eks_cluster.eks.endpoint
  cluster_auth_base64 = aws_eks_cluster.eks.certificate_authority[0].data
  cluster_service_cidr = aws_eks_cluster.eks.kubernetes_network_config[0].service_ipv4_cidr
  cluster_primary_security_group_id	= aws_eks_cluster.eks.vpc_config[0].cluster_security_group_id
  subnet_ids = [var.private_subnet_ids[0]]

  iam_role_additional_policies = {
    amazon_eks_worker_node_policy           = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
    amazon_eks_cni_policy                   = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
    amazon_ec2_container_registry_read_only = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
    amazon_ec2_ebs_driver_policy           = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
    amazon_cloudwatch_agent                 = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
  }

  vpc_security_group_ids = [
    aws_eks_cluster.eks.vpc_config[0].cluster_security_group_id,
    var.eks_sg_id
  ]

  launch_template_name   = "kafka-connect"

  block_device_mappings = [
        {
          device_name = "/dev/xvda"
          # no_device = true
 
          ebs = {
            volume_size = 20
            volume_type = "gp2"
          }
        }
      ]

  min_size     = 2
  max_size     = 2
  desired_size = 2

  # ami_type      = "AL2023_x86_64_STANDARD" ## kubelet-extra-args  does not work with this image
  instance_type        = "m5.xlarge"

  bootstrap_extra_args = "--kubelet-extra-args '--node-labels=kafka-cluster-role=kafka-connect'"

  tags = {
    Name        = "${var.env}-${var.eks_name}-kafka-connect-ng"
    Environment = var.env
  }
  depends_on = [
    aws_iam_role_policy_attachment.amazon_eks_worker_node_policy,
    aws_iam_role_policy_attachment.amazon_eks_cni_policy,
    aws_iam_role_policy_attachment.amazon_ec2_container_registry_read_only,
    aws_iam_role_policy_attachment.amazon_ec2_ebs_driver_policy,
    aws_iam_role_policy_attachment.amazon_cloudwatch_agent
  ]
}


module "self_managed_node_group_admin_tools" {
  source = "terraform-aws-modules/eks/aws//modules/self-managed-node-group"
  version = "20.31.6"

  name                = "admin-tools"
  cluster_name        = aws_eks_cluster.eks.name
  cluster_version     = var.eks_version
  cluster_endpoint    = aws_eks_cluster.eks.endpoint
  cluster_auth_base64 = aws_eks_cluster.eks.certificate_authority[0].data
  cluster_service_cidr = aws_eks_cluster.eks.kubernetes_network_config[0].service_ipv4_cidr
  cluster_primary_security_group_id	= aws_eks_cluster.eks.vpc_config[0].cluster_security_group_id
  subnet_ids = [var.private_subnet_ids[0]]


  iam_role_additional_policies = {
    amazon_eks_worker_node_policy           = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
    amazon_eks_cni_policy                   = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
    amazon_ec2_container_registry_read_only = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
    amazon_ec2_ebs_driver_policy           = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
    amazon_cloudwatch_agent                 = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
  }
  vpc_security_group_ids = [
    aws_eks_cluster.eks.vpc_config[0].cluster_security_group_id,
    var.eks_sg_id
  ]

  launch_template_name   = "admin-tools"

  block_device_mappings = [
        {
          device_name = "/dev/xvda"
          # no_device = true
 
          ebs = {
            volume_size = 20
            volume_type = "gp2"
          }
        }
      ]

  min_size     = 1
  max_size     = 2
  desired_size = 1

  # ami_type      = "AL2023_x86_64_STANDARD" ## kubelet-extra-args  does not work with this image
  instance_type        = "m5.large"

  bootstrap_extra_args = "--kubelet-extra-args '--node-labels=kafka-cluster-role=admin-tools'"

  tags = {
    Name        = "${var.env}-${var.eks_name}-admin-tools-ng"
    Environment = var.env
  }
  depends_on = [
    aws_iam_role_policy_attachment.amazon_eks_worker_node_policy,
    aws_iam_role_policy_attachment.amazon_eks_cni_policy,
    aws_iam_role_policy_attachment.amazon_ec2_container_registry_read_only,
    aws_iam_role_policy_attachment.amazon_ec2_ebs_driver_policy,
    aws_iam_role_policy_attachment.amazon_cloudwatch_agent
  ]
}

resource "aws_eks_addon" "coredns" {
  cluster_name                =  "${var.env}-${var.eks_name}"
  addon_name                  = "coredns"
  # addon_version               = "v1.10.1-eksbuild.1" #e.g., previous version v1.9.3-eksbuild.3 and the new version is v1.10.1-eksbuild.1
  resolve_conflicts_on_update = "OVERWRITE"
  resolve_conflicts_on_create = "OVERWRITE"
  depends_on = [
    # aws_eks_cluster.eks,
    module.self_managed_node_group_kafka_cluster,
    module.self_managed_node_group_admin_tools
  ]

  tags = {
    Name = "${var.env}-${var.eks_name}-coredns"
    Environment = var.env
  }
}

resource "aws_eks_addon" "vpc_cni" {
  cluster_name                = "${var.env}-${var.eks_name}"
  addon_name                  = "vpc-cni"
  # addon_version               = "v1.10.1-eksbuild.1" #e.g., previous version v1.9.3-eksbuild.3 and the new version is v1.10.1-eksbuild.1
  resolve_conflicts_on_update = "OVERWRITE"
  resolve_conflicts_on_create = "OVERWRITE"
  depends_on = [
    # aws_eks_cluster.eks, 
    module.self_managed_node_group_kafka_cluster,
    module.self_managed_node_group_admin_tools
  ]

  tags = {
    Name = "${var.env}-${var.eks_name}-vpc-cni"
    Environment = var.env
  }
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name                = "${var.env}-${var.eks_name}"
  addon_name                  = "kube-proxy"
  # addon_version               = "v1.10.1-eksbuild.1" #e.g., previous version v1.9.3-eksbuild.3 and the new version is v1.10.1-eksbuild.1
  resolve_conflicts_on_update = "OVERWRITE"
  resolve_conflicts_on_create = "OVERWRITE"
  depends_on = [
    # aws_eks_cluster.eks,
    module.self_managed_node_group_kafka_cluster,
    module.self_managed_node_group_admin_tools
  ]

  tags = {
    Name = "${var.env}-${var.eks_name}-kube-proxy"
    Environment = var.env
  }
}

resource "aws_eks_addon" "aws-ebs-csi-driver" {
  cluster_name                = "${var.env}-${var.eks_name}"
  addon_name                  = "aws-ebs-csi-driver"
  # addon_version               = "v1.10.1-eksbuild.1" #e.g., previous version v1.9.3-eksbuild.3 and the new version is v1.10.1-eksbuild.1
  resolve_conflicts_on_update = "OVERWRITE"
  resolve_conflicts_on_create = "OVERWRITE"
  depends_on = [
    # aws_eks_cluster.eks,
    module.self_managed_node_group_kafka_cluster,
    module.self_managed_node_group_admin_tools
  ]

  tags = {
    Name = "${var.env}-${var.eks_name}-aws-ebs-csi-driver"
    Environment = var.env
  }

}

resource "aws_eks_addon" "snapshot-controller" {
    cluster_name                = "${var.env}-${var.eks_name}"
    addon_name                  = "snapshot-controller"
    # addon_version               = "v1.9.3-eksbuild.3" #e.g., previous version v1.9.3-eksbuild.3 and the new version is v1.10.1-eksbuild.1
    # resolve_conflicts_on_update = "OVERWRITE"
    # resolve_conflicts_on_create = "OVERWRITE"
    depends_on = [
      # aws_eks_cluster.eks, 
      module.self_managed_node_group_kafka_cluster,
      module.self_managed_node_group_admin_tools

    ]
    tags = {
      Name = "${var.env}-${var.eks_name}-snapshot-controller"
      Environment = var.env
    }
  }


resource "aws_eks_addon" "amazon-cloudwatch-observability" {
    cluster_name                = "${var.env}-${var.eks_name}"
    addon_name                  = "amazon-cloudwatch-observability"
    # addon_version               = "v1.9.3-eksbuild.3" #e.g., previous version v1.9.3-eksbuild.3 and the new version is v1.10.1-eksbuild.1
    # resolve_conflicts_on_update = "OVERWRITE"
    # resolve_conflicts_on_create = "OVERWRITE"
    depends_on = [
      # aws_eks_cluster.eks,  
      module.self_managed_node_group_kafka_cluster,
      module.self_managed_node_group_admin_tools
    ]
    tags = {
      Name = "${var.env}-${var.eks_name}-amazon-cloudwatch-observability"
      Environment = var.env
    }
  }

resource "aws_eks_addon" "pod_identity" {
    cluster_name                = "${var.env}-${var.eks_name}"
    addon_name                  = "eks-pod-identity-agent"
    # addon_version               = "v1.9.3-eksbuild.3" #e.g., previous version v1.9.3-eksbuild.3 and the new version is v1.10.1-eksbuild.1
    # resolve_conflicts_on_update = "OVERWRITE"
    # resolve_conflicts_on_create = "OVERWRITE"
    depends_on = [
    # aws_eks_cluster.eks,     
    module.self_managed_node_group_kafka_cluster,
    module.self_managed_node_group_admin_tools
    ]
    tags = {
      Name = "${var.env}-${var.eks_name}-pod_identity"
      Environment = var.env
    }
  }

data "tls_certificate" "eks" {
  url = aws_eks_cluster.eks.identity[0].oidc[0].issuer
}


resource "aws_iam_openid_connect_provider" "eks" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.eks.identity[0].oidc[0].issuer
}

resource "aws_iam_policy" "eks_cluster_autoscaler" {
  name   = "${var.eks_name}-autoscaler"
  policy = file("${path.module}/policies/cluster_autoscaler_policy.json")
}

data "aws_iam_policy_document" "eks_cluster_autoscaler_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:sub"
      values   = ["system:serviceaccount:monitoring:cluster-autoscaler"]
    }

    principals {
      identifiers = [aws_iam_openid_connect_provider.eks.arn]
      type        = "Federated"
    }
  }
}

resource "aws_iam_role" "eks_cluster_autoscaler" {
  assume_role_policy = data.aws_iam_policy_document.eks_cluster_autoscaler_assume_role_policy.json
  name               = "eks-cluster-autoscaler"
}

resource "aws_iam_role_policy_attachment" "eks_cluster_autoscaler_attach" {
  role       = aws_iam_role.eks_cluster_autoscaler.name
  policy_arn = aws_iam_policy.eks_cluster_autoscaler.arn
}


# 3. IAM Policy for External Secrets
resource "aws_iam_policy" "external_secrets_policy" {
  name        = "external-secrets-policy"
  path        = "/"
  description = "Policy for External Secrets to access AWS Secrets Manager"

    policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret",
          "secretsmanager:ListSecrets",
          "secretsmanager:CreateSecret",
          "secretsmanager:DeleteSecret",
          "secretsmanager:UpdateSecret",
          "secretsmanager:GetResourcePolicy",
          "secretsmanager:PutSecretValue",
          "secretsmanager:TagResource",
          "secretsmanager:UntagResource"
        ],
        Effect   = "Allow",
        Resource = "*"
      }
    ]
  })
}

data "aws_iam_openid_connect_provider" "eks" {
  arn = aws_iam_openid_connect_provider.eks.arn
}

# 4. IAM Role for External Secrets
resource "aws_iam_role" "external_secrets_role" {
  name = "external-secrets-role"
    assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Federated = data.aws_iam_openid_connect_provider.eks.arn
        },
        Action = "sts:AssumeRoleWithWebIdentity",
        Condition = {
          StringEquals = {
            "${replace(data.aws_iam_openid_connect_provider.eks.url, "https://", "")}:sub" : "system:serviceaccount:external-secrets:external-secrets"
          }
        }
      }
    ]
  })
}

# 5. Attach Policy to Role
resource "aws_iam_role_policy_attachment" "external_secrets_policy_attachment" {
  policy_arn = aws_iam_policy.external_secrets_policy.arn
  role       = aws_iam_role.external_secrets_role.name
}





