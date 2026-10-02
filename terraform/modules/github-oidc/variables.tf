variable "environment" {
  description = "Entorno de la cuenta (dev | prod)."
  type        = string
}

variable "github_repository" {
  description = "Repositorio autorizado a asumir los roles, formato owner/repo."
  type        = string
}

variable "state_bucket_arn" {
  description = "ARN del bucket S3 que guarda el estado de Terraform."
  type        = string
}

variable "state_kms_key_arn" {
  description = "ARN de la KMS key que cifra el estado."
  type        = string
}

variable "create_oidc_provider" {
  description = "Crear el OIDC provider de GitHub (solo uno por cuenta)."
  type        = bool
  default     = true
}
