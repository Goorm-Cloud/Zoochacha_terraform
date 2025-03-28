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

variable "use_recovery_ami" {
  description = "배포 실패 시 복구 AMI를 사용할지 여부"
  type        = bool
  default     = true
}

variable "recovery_ami_id" {
  description = "복구에 사용할 AMI ID (지정된 경우 use_recovery_ami 값과 상관없이 이 AMI 사용)"
  type        = string
  default     = "ami-0c9c942bd7bf113a2"  # zoochacha-jenkins-server-20250321
}

variable "pub_sub1_id" {
  description = "Public Subnet 1 ID"
  type        = string
} 