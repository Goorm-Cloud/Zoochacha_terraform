variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-northeast-2"
}

variable "ami_id" {
  description = "AMI ID for the EC2 instance"
  type        = string
  default     = "ami-0c9c942bd7bf113a2" # Ubuntu 22.04 AMI
}

variable "instance_type" {
  description = "Instance type for the EC2 instance"
  type        = string
  default     = "t3.medium" # 2 vCPU, 4 GiB Memory
}

variable "key_name" {
  description = "Key pair name for SSH access"
  type        = string
  default     = "jenkins-key"
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "subnet_id" {
  description = "서브넷 ID"
  type        = string
}

variable "cluster_name" {
  description = "EKS 클러스터 이름"
  type        = string
}

variable "jenkins_admin_password" {
  description = "Jenkins admin user password"
  type        = string
  sensitive   = true
} 