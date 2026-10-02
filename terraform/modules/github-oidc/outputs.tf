output "plan_role_arn" {
  description = "Rol que asume GitHub Actions para terraform plan."
  value       = aws_iam_role.plan.arn
}

output "apply_role_arn" {
  description = "Rol que asume GitHub Actions para terraform apply."
  value       = aws_iam_role.apply.arn
}

output "app_boundary_arn" {
  description = "Permissions boundary obligatorio para roles de la aplicacion."
  value       = aws_iam_policy.app_boundary.arn
}
