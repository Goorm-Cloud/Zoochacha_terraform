output "prefix" {
  value = "zoochacha"
  description = "Prefix for all resources"
}

output "vpc_id" {
  value = aws_vpc.this.id
  description = "VPC ID"
}

output "private_subnet_ids" {
  value = [aws_subnet.pri_sub1.id, aws_subnet.pri_sub2.id]
  description = "Private subnet IDs"
}

output "public_subnet_ids" {
  value = [aws_subnet.pub_sub1.id, aws_subnet.pub_sub2.id]
  description = "Public subnet IDs"
}

output "pub_sub1_id" {
  value = aws_subnet.pub_sub1.id
  description = "Public subnet 1 ID"
}

output "pub_sub2_id" {
  value = aws_subnet.pub_sub2.id
  description = "Public subnet 2 ID"
}

output "pri_sub1_id" {
  value = aws_subnet.pri_sub1.id
  description = "Private subnet 1 ID"
}

output "pri_sub2_id" {
  value = aws_subnet.pri_sub2.id
  description = "Private subnet 2 ID"
}

output "eks_sg_id" {
  value = aws_security_group.eks-vpc-pub-sg.id
  description = "Security group ID for EKS cluster"
}