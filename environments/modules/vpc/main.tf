resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  enable_network_address_usage_metrics = true
  instance_tenancy     = "default"
  tags = {
    Name        = var.vpc_name
    Environment = var.env
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name        = "${var.vpc_name}-igw"
    Environment = var.env
  }
  depends_on = [aws_vpc.main]
}

resource "aws_subnet" "public" {
  count                   = length(var.public_subnets)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = element(var.public_subnets, count.index)
  map_public_ip_on_launch = true
  availability_zone       = element(var.azs, count.index)
  tags = {

    "kubernetes.io/role/elb"                           = "1"
    "kubernetes.io/cluster/${var.env}-${var.eks_name}" = "owned"
    Name        = "${var.vpc_name}-public-${count.index}"
    Environment = var.env
  }
  depends_on = [aws_vpc.main]
}

resource "aws_subnet" "private" {
  count             = length(var.private_subnets)
  vpc_id            = aws_vpc.main.id
  cidr_block        = element(var.private_subnets, count.index)
  availability_zone = element(var.azs, count.index)

  tags = {
    Name        = "${var.vpc_name}-private-${count.index}"
    Environment = var.env
    "kubernetes.io/cluster/${var.env}-${var.eks_name}" = "owned"
    "kubernetes.io/role/internal-elb"                      = "1"
  }
  depends_on = [aws_vpc.main]
}

resource "aws_subnet" "private_outpost" {
  count             = length(var.outpost_private_subnets)
  vpc_id            = aws_vpc.main.id
  cidr_block        = element(var.outpost_private_subnets, count.index)
  availability_zone = var.azs[0]
  outpost_arn = "arn:aws:outposts:eu-central-1:827893513553:outpost/op-015359bb8da97c505"
  
  tags = {
    Name        = "${var.vpc_name}-private-${count.index}"
    Environment = var.env
    "kubernetes.io/cluster/${var.env}-${var.eks_name}" = "owned"
    "kubernetes.io/role/internal-elb"                      = "1"
  }
  depends_on = [aws_vpc.main]
}

resource "aws_eip" "nat" {
  domain = "vpc"
  tags = {
    Name        = "${var.vpc_name}-nat-eip"
    Environment = var.env
  }

  depends_on = [aws_internet_gateway.igw]
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[1].id
  tags = {
    Name        = "${var.vpc_name}-nat"
    Environment = var.env
  }
  depends_on = [aws_subnet.public, aws_eip.nat]
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name        = "${var.vpc_name}-public-rt"
    Environment = var.env
  }

  depends_on = [aws_vpc.main, aws_internet_gateway.igw, aws_subnet.public]
}

resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id

  depends_on = [aws_subnet.public, aws_route_table.public]
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }

  lifecycle {
    ignore_changes = [route]
  }
  
  tags = {
    Name        = "${var.vpc_name}-private-rt"
    Environment = var.env
  }
}

resource "aws_route_table_association" "private" {
  count          = length(aws_subnet.private)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "private_outpost" {
  count          = length(aws_subnet.private_outpost)
  subnet_id      = aws_subnet.private_outpost[count.index].id
  route_table_id = aws_route_table.private.id
}

resource "aws_security_group" "eks_sg" {
  vpc_id = aws_vpc.main.id
  name        = "${var.env}-${var.eks_name}-sg"

  tags = {
    Name        = "${var.env}-${var.eks_name}-sg"
    Environment = var.env
  }
}

# Allow inbound traffic from the VPC CIDR block
resource "aws_vpc_security_group_ingress_rule" "eks_sg_ingress" {
  security_group_id = aws_security_group.eks_sg.id
  cidr_ipv4      = var.vpc_cidr

  # from_port   = 0
  # to_port     = 0
  ip_protocol    = "-1"

  description = "Allow all inbound traffic"
}

# Allow all egress traffic 
resource "aws_vpc_security_group_egress_rule" "eks_egress_to_vpc" {
  security_group_id = aws_security_group.eks_sg.id
  cidr_ipv4       = "0.0.0.0/0"

  # from_port   = 0
  # to_port     = 0
  ip_protocol    = "-1"

  description = "Allow all egress traffic to 0.0.0.0/0"
}