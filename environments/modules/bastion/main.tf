resource "tls_private_key" "pk" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "bastion_key" {
  key_name   = "${var.env}-${var.vpc_name}-bastion-host-key"       # Create "myKey" to AWS!!
  public_key = tls_private_key.pk.public_key_openssh

  provisioner "local-exec" { # Create "myKey.pem" to your computer!!
    command = "echo '${tls_private_key.pk.private_key_pem}' > ./${var.env}-bastion_key.pem"
  }
  tags = {
    Name        = "ssh key used to access bastion host of the ${var.env}-${var.vpc_name}"
    Environment = var.env
}
  depends_on = [tls_private_key.pk]
}

resource "local_file" "pem_file" {
  content  = tls_private_key.pk.private_key_pem
  filename = "${path.module}/${var.env}-bastion_key.pem"
}

# Upload the PEM file to an S3 bucket
resource "aws_s3_object" "pem_file_upload" {
  bucket = var.ssh_pem_bucket
  key    = "keys/${var.env}-bastion_key.pem"
  source = local_file.pem_file.filename
  acl    = "private"

  tags = {
    Name        = "${var.env}-${var.vpc_name}-bastion-pem-file"
    Environment = var.env
  }
}

resource "aws_security_group" "bastion_sg" {
  vpc_id = var.vpc_id
  name   = "${var.env}-${var.vpc_name}-bastion-security-group"

  tags = {
    Name        = "${var.env}-${var.vpc_name}-bastion-security-group"
    Environment = var.env
  }
}

# Create individual ingress rules using count and var.allowed_ips
resource "aws_vpc_security_group_ingress_rule" "bastion_ingress_ssh" {
  count            = length(var.allowed_ips)
  security_group_id = aws_security_group.bastion_sg.id
  from_port        = 22
  to_port          = 22
  ip_protocol      = "tcp"
  cidr_ipv4        = var.allowed_ips[count.index]  # Use cidr_ipv4 for IPv4 CIDR blocks

  tags = {
    Name        = "${var.env}-${var.vpc_name}-bastion-ingress-ssh-allowed-cidr-${count.index}"
    Environment = var.env
  }
  depends_on = [aws_security_group.bastion_sg]
}

# Create egress rule allowing all outbound traffic using aws_vpc_security_group_egress_rule
resource "aws_vpc_security_group_egress_rule" "bastion_egress_all" {
  security_group_id = aws_security_group.bastion_sg.id
  # from_port         = 0
  # to_port           = 0
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"  # Use cidr_ipv4 for allowing all IPv4 traffic

  tags = {
    Name        = "${var.env}-${var.vpc_name}-bastion-egress-all"
    Environment = var.env
  }
  depends_on = [aws_security_group.bastion_sg]
}

resource "aws_instance" "bastion" {
  ami                         = var.ami
  instance_type               = "t3.micro"
  subnet_id                   = var.public_subnet_id
  associate_public_ip_address = true
  key_name                    = var.key_name

  security_groups = [aws_security_group.bastion_sg.id]

  iam_instance_profile = var.instance_profile_name

  tags = {
    Name        = "${var.env}-${var.vpc_name} Bastion Host"
    Environment = var.env
  }

  lifecycle {
    ignore_changes = all
  }

  depends_on = [aws_security_group.bastion_sg, aws_key_pair.bastion_key]

  user_data = <<-EOF
    #!/bin/bash
    set -e

    LOG_FILE="/var/log/bastion_setup.log"
    exec > $LOG_FILE 2>&1

    echo "Starting the setup script" >> $LOG_FILE

    # Update and install dependencies
    echo "Updating the system and installing dependencies" >> $LOG_FILE
    sudo yum update -y
    sudo yum install -y curl unzip python3 python3-pip jq bash git ca-certificates gnupg2  --allowerasing

    # Install SSM Agent
    sudo yum install -y https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/linux_amd64/amazon-ssm-agent.rpm
    sudo systemctl enable amazon-ssm-agent
    sudo systemctl start amazon-ssm-agent

    # Install k9s
    curl -Lo k9s.tar.gz https://github.com/derailed/k9s/releases/download/v0.50.3/k9s_Linux_amd64.tar.gz
    tar -xzf k9s.tar.gz
    mv k9s /usr/local/bin/
    chmod +x /usr/local/bin/k9s
    rm -f k9s.tar.gz

    # Install Docker CLI
    echo "Installing Docker" >> $LOG_FILE
    sudo yum install docker -y
    sudo service docker start
    sudo usermod -a -G docker ec2-user

    # Install Terraform
    echo "Installing Terraform" >> $LOG_FILE
    curl -LO https://releases.hashicorp.com/terraform/1.9.5/terraform_1.9.5_linux_amd64.zip
    unzip terraform_1.9.5_linux_amd64.zip
    sudo mv terraform /usr/local/bin/
    rm terraform_1.9.5_linux_amd64.zip

    # Install AWS CLI v2
    echo "Installing AWS CLI" >> $LOG_FILE
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    unzip awscliv2.zip
    sudo ./aws/install
    rm -rf awscliv2.zip aws

    # Install kubectl
    echo "Installing kubectl" >> $LOG_FILE
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
    rm kubectl

    echo "Setup complete." >> $LOG_FILE
    EOF
}


# resource "aws_instance" "ubuntu_vm" {
#   ami                         = "ami-0a0e5d9c7acc336f1"   # Update the variable with Ubuntu AMI
#   instance_type               = "t3.micro"
#   subnet_id                   = var.public_subnet_id
#   associate_public_ip_address = true
#   key_name                    = var.key_name

#   security_groups = [aws_security_group.bastion_sg.id]

#   tags = {
#     Name        = "${var.env}-${var.vpc_name} Ubuntu VM"
#     Environment = var.env
#   }

#   lifecycle {
#     ignore_changes = all
#   }

#   depends_on = [aws_security_group.bastion_sg, aws_key_pair.bastion_key]
# }