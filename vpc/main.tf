provider "aws" {
  region = "ap-northeast-2"
  
  default_tags {
    tags = {
      "zoochacha-eks-iam-role" = "true"
    }
  }
}

terraform{
    required_providers {
      aws = {
        source = "hashicorp/aws"
        version = "~> 5.0"
      }
    }
}

# VPC
resource "aws_vpc" "this" {
  cidr_block           = "10.1.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "zoochacha-vpc"
  }

  lifecycle {
    create_before_destroy = false
  }
}

# Internet Gateway
resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "zoochacha-eks-igw"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Public Subnet 1
resource "aws_subnet" "pub_sub1" {
  vpc_id            = aws_vpc.this.id
  cidr_block        = "10.1.1.0/24"
  availability_zone = "ap-northeast-2a"

  tags = {
    Name = "zoochacha-pub-sub1"
    Type = "public"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Public Subnet 2
resource "aws_subnet" "pub_sub2" {
  vpc_id            = aws_vpc.this.id
  cidr_block        = "10.1.2.0/24"
  availability_zone = "ap-northeast-2c"

  tags = {
    Name = "zoochacha-pub-sub2"
    Type = "public"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Private Subnet 1
resource "aws_subnet" "pri_sub1" {
  vpc_id            = aws_vpc.this.id
  cidr_block        = "10.1.3.0/24"
  availability_zone = "ap-northeast-2a"

  tags = {
    Name = "zoochacha-pri-sub1"
    Type = "private"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Private Subnet 2
resource "aws_subnet" "pri_sub2" {
  vpc_id            = aws_vpc.this.id
  cidr_block        = "10.1.4.0/24"
  availability_zone = "ap-northeast-2c"

  tags = {
    Name = "zoochacha-pri-sub2"
    Type = "private"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Elastic IP for NAT Gateway
resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name = "zoochacha-eks-nat-ip"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# NAT Gateway
resource "aws_nat_gateway" "this" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.pub_sub1.id

  tags = {
    Name = "zoochacha-eks-nat"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Public Route Table
resource "aws_route_table" "pub_rt" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = {
    Name = "zoochacha-pub-rt"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Private Route Table
resource "aws_route_table" "pri_rt" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.this.id
  }

  tags = {
    Name = "zoochacha-pri-rt"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Route Table Association - Public Subnet 1
resource "aws_route_table_association" "pub_sub1_association" {
  subnet_id      = aws_subnet.pub_sub1.id
  route_table_id = aws_route_table.pub_rt.id

  depends_on = [aws_route_table.pub_rt, aws_subnet.pub_sub1]
  lifecycle {
    create_before_destroy = true
  }
}

# Route Table Association - Public Subnet 2
resource "aws_route_table_association" "pub_sub2_association" {
  subnet_id      = aws_subnet.pub_sub2.id
  route_table_id = aws_route_table.pub_rt.id

  depends_on = [aws_route_table.pub_rt, aws_subnet.pub_sub2]
  lifecycle {
    create_before_destroy = true
  }
}

# Route Table Association - Private Subnet 1
resource "aws_route_table_association" "pri_sub1_association" {
  subnet_id      = aws_subnet.pri_sub1.id
  route_table_id = aws_route_table.pri_rt.id

  depends_on = [aws_route_table.pri_rt, aws_subnet.pri_sub1]
  lifecycle {
    create_before_destroy = true
  }
}

# Route Table Association - Private Subnet 2
resource "aws_route_table_association" "pri_sub2_association" {
  subnet_id      = aws_subnet.pri_sub2.id
  route_table_id = aws_route_table.pri_rt.id

  depends_on = [aws_route_table.pri_rt, aws_subnet.pri_sub2]
  lifecycle {
    create_before_destroy = true
  }
}

# 보안그룹 생성
resource "aws_security_group" "eks-vpc-pub-sg" {
  name        = "zoochacha-eks-sg"
  description = "Security group for EKS cluster"
  vpc_id      = aws_vpc.this.id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 10250
    to_port     = 10250
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.this.cidr_block]
    description = "Kubelet API"
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # 노드 간 통신을 위한 모든 트래픽 허용
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [aws_vpc.this.cidr_block]
    description = "Allow all internal traffic"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "zoochacha-eks-sg"
  }

  lifecycle {
    create_before_destroy = false
  }

  depends_on = [aws_vpc.this]
}


