variable "project" {
  description = "Nombre corto del proyecto."
  type        = string
  default     = "simapp"
}

variable "environment" {
  description = "Cuenta/entorno que se inicializa (dev | prod)."
  type        = string

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment debe ser dev o prod."
  }
}

variable "region" {
  description = "Region AWS principal."
  type        = string
  default     = "us-east-1"
}

variable "github_repository" {
  description = "Repositorio GitHub autorizado (owner/repo)."
  type        = string
  default     = "sdm07/devops-terraform"
}
