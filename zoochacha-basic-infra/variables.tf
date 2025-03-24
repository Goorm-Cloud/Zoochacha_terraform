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

variable "helm_chart_path" {
  description = "Path to the Helm chart"
  type        = string
  default     = "/Users/hyunjunson/zoochacha/fix/manifest/zoochacha-manifest"
}

variable "helm_chart_version" {
  description = "Version of the Helm chart"
  type        = string
  default     = "0.1.0"
} 