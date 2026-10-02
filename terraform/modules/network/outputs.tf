output "vpc_id" {
  description = "ID de la VPC."
  value       = aws_vpc.this.id
}

output "public_subnet_ids" {
  description = "Subredes publicas (ALB)."
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "Subredes privadas (tareas ECS)."
  value       = aws_subnet.private[*].id
}
