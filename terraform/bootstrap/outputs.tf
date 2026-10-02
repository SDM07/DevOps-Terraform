output "state_bucket" {
  description = "Bucket a usar en backend.hcl del entorno."
  value       = aws_s3_bucket.state.bucket
}

output "state_kms_key_arn" {
  description = "KMS key del estado."
  value       = aws_kms_key.state.arn
}

output "plan_role_arn" {
  description = "Guardar como variable AWS_PLAN_ROLE_ARN del GitHub Environment."
  value       = module.github_oidc.plan_role_arn
}

output "apply_role_arn" {
  description = "Guardar como variable AWS_APPLY_ROLE_ARN del GitHub Environment."
  value       = module.github_oidc.apply_role_arn
}

output "app_boundary_arn" {
  description = "Permissions boundary para los roles de la aplicacion."
  value       = module.github_oidc.app_boundary_arn
}
