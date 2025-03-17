variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-northeast-2"
}

variable "ami_id" {
  description = "Ubuntu 22.04 LTS AMI ID"
  type        = string
  default     = "ami-0e9bfdb247cc8de84" # Ubuntu 22.04 LTS in ap-northeast-2
}

variable "instance_type" {
  description = "EC2 instance type for Jenkins"
  type        = string
  default     = "t3.small" # 테스트 환경은 더 작은 인스턴스 타입 사용
}

variable "key_name" {
  description = "Name of the SSH key pair"
  type        = string
  default     = "jenkins-key"
}

variable "jenkins_admin_password" {
  description = "Jenkins admin password"
  type        = string
  default     = "admin123!" # 테스트 환경용 기본 비밀번호
} 