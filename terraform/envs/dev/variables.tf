variable "project" {
  description = "Nombre corto del proyecto."
  type        = string
}

variable "environment" {
  description = "dev | prod."
  type        = string

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment debe ser dev o prod."
  }
}

variable "aws_account_id" {
  description = "Cuenta AWS donde DEBE aplicarse este entorno."
  type        = string
}

variable "region" {
  description = "Region AWS."
  type        = string
  default     = "us-east-1"
}

variable "cost_center" {
  description = "Centro de costos para tagging."
  type        = string
  default     = "platform"
}

variable "vpc_cidr" {
  description = "CIDR de la VPC."
  type        = string
}

variable "az_count" {
  description = "Numero de AZs."
  type        = number
}

variable "single_nat_gateway" {
  description = "Un NAT compartido (dev) o uno por AZ (prod)."
  type        = bool
}

variable "container_image" {
  description = "Imagen a desplegar (en prod: por digest). La inyecta el pipeline de la aplicacion."
  type        = string
}

variable "cpu" {
  description = "CPU por tarea."
  type        = number
}

variable "memory" {
  description = "Memoria por tarea (MiB)."
  type        = number
}

variable "min_capacity" {
  description = "Tareas minimas."
  type        = number
}

variable "max_capacity" {
  description = "Tareas maximas."
  type        = number
}

variable "use_fargate_spot" {
  description = "Usar Fargate Spot para el excedente."
  type        = bool
}

variable "on_demand_base" {
  description = "Tareas minimas en Fargate on-demand."
  type        = number
}

variable "certificate_arn" {
  description = "Certificado ACM (vacio = solo HTTP)."
  type        = string
  default     = ""
}

variable "log_retention_days" {
  description = "Retencion de logs."
  type        = number
}

variable "alarm_email" {
  description = "Correo que recibe las alarmas (vacio = sin suscripcion)."
  type        = string
  default     = ""
}
