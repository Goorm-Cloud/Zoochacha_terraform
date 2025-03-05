variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-northeast-2"
}

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
  default     = "zoochacha-eks-cluster"
}

variable "cluster_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.31"
}

variable "eks-vpc-id" {
  description = "VPC ID for EKS cluster"
  type        = string
}

variable "pri-sub1-id" {
  description = "Private subnet 1 ID"
  type        = string
}

variable "pri-sub2-id" {
  description = "Private subnet 2 ID"
  type        = string
}

variable "pub-sub1-id" {
  description = "Public subnet 1 ID"
  type        = string
}

variable "pub-sub2-id" {
  description = "Public subnet 2 ID"
  type        = string
}