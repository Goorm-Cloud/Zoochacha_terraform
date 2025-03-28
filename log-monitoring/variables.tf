variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-northeast-2"
}

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
  default     = "zoochacha-eks-cluster"
}

variable "elastic_password" {
  description = "Elasticsearch password"
  type        = string
  sensitive   = true
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "subnet_id" {
  description = "Subnet ID"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.0.0.0/16"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "production"
}

variable "project" {
  description = "Project name"
  type        = string
  default     = "efk-stack"
}

variable "allowed_ssh_cidr_blocks" {
  description = "List of CIDR blocks allowed to SSH"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
  default     = "zoochacha"
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "secret_manager_arn" {
  description = "ARN of the secret in AWS Secrets Manager"
  type        = string
}

variable "instance_profile_name" {
  description = "IAM instance profile name"
  type        = string
  default     = "zoochacha-efk-profile"
}

variable "instance_type" {
  description = "EC2 instance type for EFK stack"
  type        = string
  default     = "t3.medium"
}

variable "volume_size" {
  description = "Size of the EBS volume in GB"
  type        = number
  default     = 100
} 