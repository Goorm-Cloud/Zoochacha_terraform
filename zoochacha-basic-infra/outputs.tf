output "helm_release_name" {
  description = "The name of the Helm release"
  value       = try(helm_release.basic_infra[0].name, null)
}

output "helm_release_status" {
  description = "The status of the Helm release"
  value       = try(helm_release.basic_infra[0].status, null)
}

output "eks_cluster_status" {
  description = "The status of the EKS cluster"
  value       = data.aws_eks_cluster.this.status
} 