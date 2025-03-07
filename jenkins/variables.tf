variable "namespace" {
  description = "Kubernetes namespace for Jenkins"
  type        = string
  default     = "jenkins"
}

variable "helm_release_name" {
  description = "Name of the Helm release"
  type        = string
  default     = "jenkins"
}

variable "jenkins_version" {
  description = "Version of Jenkins Helm chart"
  type        = string
  default     = "5.8.17"
}

variable "jenkins_image_tag" {
  description = "Jenkins controller image tag (version)"
  type        = string
  default     = "2.479.3-lts-jdk17"
}

variable "admin_username" {
  description = "Jenkins admin username"
  type        = string
  default     = "zoochacha"
}

variable "secret_name" {
  description = "Name of the AWS Secrets Manager secret"
  type        = string
  default     = "jenkins-admin-password"
}

variable "persistence_size" {
  description = "Size of the persistent volume for Jenkins"
  type        = string
  default     = "10Gi"
}

variable "controller_resources" {
  description = "Resource limits and requests for Jenkins controller"
  type = object({
    requests = object({
      cpu    = string
      memory = string
    })
    limits = object({
      cpu    = string
      memory = string
    })
  })
  default = {
    requests = {
      cpu    = "500m"
      memory = "1Gi"
    }
    limits = {
      cpu    = "1000m"
      memory = "2Gi"
    }
  }
}

variable "agent_resources" {
  description = "Resource limits and requests for Jenkins agents"
  type = object({
    requests = object({
      cpu    = string
      memory = string
    })
    limits = object({
      cpu    = string
      memory = string
    })
  })
  default = {
    requests = {
      cpu    = "250m"
      memory = "256Mi"
    }
    limits = {
      cpu    = "500m"
      memory = "512Mi"
    }
  }
}

variable "github_organization" {
  description = "GitHub 조직 또는 사용자 이름"
  type        = string
}

variable "github_repositories" {
  description = "모니터링할 GitHub 저장소 목록"
  type        = list(string)
  default     = []
}

variable "shared_library_repo" {
  description = "Jenkins shared library GitHub 저장소"
  type        = string
}

variable "github_token" {
  description = "GitHub API 토큰"
  type        = string
  sensitive   = true
}

variable "webhook_secret" {
  description = "GitHub webhook 시크릿"
  type        = string
  sensitive   = true
}

variable "discord_webhook_url" {
  description = "Discord webhook URL"
  type        = string
  sensitive   = true
} 