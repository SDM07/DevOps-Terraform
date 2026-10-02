output "alb_dns_name" {
  description = "DNS publico del ALB."
  value       = aws_lb.this.dns_name
}

output "service_url" {
  description = "URL del servicio."
  value       = "${var.certificate_arn != "" ? "https" : "http"}://${aws_lb.this.dns_name}"
}

output "cluster_name" {
  description = "Nombre del cluster ECS."
  value       = aws_ecs_cluster.this.name
}

output "service_name" {
  description = "Nombre del servicio ECS."
  value       = aws_ecs_service.app.name
}

output "task_role_arn" {
  description = "Rol de la aplicacion (para agregar permisos puntuales)."
  value       = aws_iam_role.task.arn
}
