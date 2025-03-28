output "instance_id" {
  description = "EC2 인스턴스 ID"
  value       = aws_instance.efk.id
}

output "instance_public_ip" {
  description = "EC2 인스턴스의 공개 IP"
  value       = aws_instance.efk.public_ip
}

output "elasticsearch_security_group_id" {
  description = "Elasticsearch 보안 그룹 ID"
  value       = aws_security_group.elasticsearch.id
}

output "kibana_security_group_id" {
  description = "Kibana 보안 그룹 ID"
  value       = aws_security_group.kibana.id
}

output "grafana_security_group_id" {
  description = "Grafana 보안 그룹 ID"
  value       = aws_security_group.grafana.id
}

output "ssh_security_group_id" {
  description = "SSH 보안 그룹 ID"
  value       = aws_security_group.ssh.id
}

output "elasticsearch_endpoint" {
  description = "Elasticsearch endpoint URL"
  value       = "http://${aws_instance.efk.public_ip}:9200"
}

output "kibana_endpoint" {
  description = "Kibana endpoint URL"
  value       = "http://${aws_instance.efk.public_ip}:5601"
}

output "grafana_endpoint" {
  description = "Grafana endpoint URL"
  value       = "http://${aws_instance.efk.public_ip}:3000"
} 