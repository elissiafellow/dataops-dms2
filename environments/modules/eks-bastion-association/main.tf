
data "aws_iam_policy_document" "bastion_trust" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_policy" "eks_admin" {
  name        = "EksAdminPolicy"
  description = "Provides full administration access to EKS clusters"
  policy      = <<-EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "EKSEverything",
      "Effect": "Allow",
      "Action": [
        "eks:*"
      ],
      "Resource": "*"
    }
  ]
}
EOF
}

resource "aws_iam_role" "bastion_role" {
  name               = "bastion-role"
  assume_role_policy = data.aws_iam_policy_document.bastion_trust.json
}


resource "aws_iam_role_policy_attachment" "ssm_managed_instance" {
  role       = aws_iam_role.bastion_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "bastion_role" {
  policy_arn = aws_iam_policy.eks_admin.arn
  role       = aws_iam_role.bastion_role.name
  depends_on = [aws_iam_role.bastion_role]
}

resource "aws_iam_instance_profile" "bastion_instance_profile" {
  name = "bastion-instance-profile"
  role = aws_iam_role.bastion_role.name
}

resource "aws_eks_access_entry" "bastion_eks_access" {
  cluster_name      = var.cluster_name
  principal_arn     = aws_iam_role.bastion_role.arn
  kubernetes_groups = [""]
  type              = "STANDARD"
}

resource "aws_eks_access_policy_association" "bastion-eks-policy-association" {
  cluster_name  = var.cluster_name
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  principal_arn =  aws_iam_role.bastion_role.arn

  access_scope {
    type       = "cluster"
    # namespaces = ["example-namespace"]
  }
}