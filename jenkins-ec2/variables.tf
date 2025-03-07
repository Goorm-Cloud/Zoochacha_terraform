variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-northeast-2"
}

variable "ami_id" {
  description = "AMI ID for the EC2 instance"
  type        = string
  default     = "ami-0c9c942bd7bf113a2" # Amazon Linux 2023 AMI (ap-northeast-2)
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