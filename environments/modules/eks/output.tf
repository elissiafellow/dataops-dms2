
output "cluster_name" {
  value = aws_eks_cluster.eks.name
}

output "cluster_endpoint" {
  description = "The endpoint for your EKS Kubernetes API server."
  value       = aws_eks_cluster.eks.endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64 encoded certificate data required to communicate with your cluster."
  value       = aws_eks_cluster.eks.certificate_authority[0].data
}

data "aws_eks_cluster_auth" "eks" {
  name = aws_eks_cluster.eks.name
}

output "cluster_token" {
  description = "A token used to authenticate against the EKS cluster."
  value       = data.aws_eks_cluster_auth.eks.token
}
