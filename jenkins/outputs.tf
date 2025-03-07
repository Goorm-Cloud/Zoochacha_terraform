output "jenkins_url" {
  description = "URL of the Jenkins service"
  value       = try(
    "http://${data.kubernetes_service.jenkins.status[0].load_balancer[0].ingress[0].hostname}:8080",
    "Jenkins URL is not available yet. Run 'kubectl get svc -n jenkins' to check the EXTERNAL-IP"
  )
}

output "admin_username" {
  description = "Jenkins admin username"
  value       = var.admin_username
}

output "admin_password_secret_name" {
  description = "Name of the AWS Secrets Manager secret containing the admin password"
  value       = data.aws_secretsmanager_secret.jenkins_admin_password.name
}

# Jenkins 서비스 정보 가져오기
data "kubernetes_service" "jenkins" {
  metadata {
    name      = "${var.helm_release_name}-jenkins"
    namespace = kubernetes_namespace.jenkins.metadata[0].name
  }

  depends_on = [
    helm_release.jenkins
  ]
} 