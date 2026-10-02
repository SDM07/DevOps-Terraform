variable "name" {
  description = "Prefijo de nombres (proyecto-entorno)."
  type        = string
}

variable "cidr_block" {
  description = "CIDR de la VPC."
  type        = string
}

variable "az_count" {
  description = "Numero de zonas de disponibilidad (2 en dev, 3 en prod)."
  type        = number
  default     = 2

  validation {
    condition     = var.az_count >= 2 && var.az_count <= 3
    error_message = "az_count debe estar entre 2 y 3."
  }
}

variable "single_nat_gateway" {
  description = "true = un NAT compartido (barato, dev). false = un NAT por AZ (HA, prod)."
  type        = bool
  default     = true
}

variable "flow_logs_retention_days" {
  description = "Retencion de VPC Flow Logs en CloudWatch."
  type        = number
  default     = 30
}

variable "kms_key_arn" {
  description = "KMS key para cifrar los logs."
  type        = string
}

variable "permissions_boundary_arn" {
  description = "Permissions boundary obligatorio para los roles IAM que crea el modulo."
  type        = string
}
