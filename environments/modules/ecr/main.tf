
# Create an ECR repository
resource "aws_ecr_repository" "my_repo" {
  name = var.repository_name

  # Optional: Enable image scanning on push
  image_scanning_configuration {
    scan_on_push = true
  }

  # Optional: Allow mutable tags (vs. IMMUTABLE)
  image_tag_mutability = "MUTABLE"
}

resource "null_resource" "build_and_push" {
  provisioner "local-exec" {
    command = <<-EOF
      # 1. Build the Docker image
      docker build \
        -t ${var.image_name}:latest \
        -f "${path.module}/kafka-connect-cluster/dockerfile" \
        "${path.module}/kafka-connect-cluster"

      # 2. Authenticate Docker to ECR
      aws ecr get-login-password --region ${var.aws_region} \
        | docker login --username AWS --password-stdin ${aws_ecr_repository.my_repo.repository_url}

      # 3. Tag the image for ECR
      docker tag ${var.image_name}:latest ${aws_ecr_repository.my_repo.repository_url}:latest

      # 4. Push the image
      docker push ${aws_ecr_repository.my_repo.repository_url}:latest

      # 5. Logout from Docker and remove local config file
      docker logout || true
      rm -f ~/.docker/config.json
    EOF
  }

  depends_on = [
    aws_ecr_repository.my_repo
  ]
}
