variable "name" {
  description = "Prefijo de nombres (proyecto-entorno)."
  type        = string
}

variable "environment" {
  description = "dev | prod."
  type        = string
}

variable "vpc_id" {
  description = "VPC donde se despliega el servicio."
  type        = string
}

variable "public_subnet_ids" {
  description = "Subredes publicas para el ALB."
  type        = list(string)
}

variable "private_subnet_ids" {
  description = "Subredes privadas para las tareas."
  type        = list(string)
}

variable "container_image" {
  description = "Imagen del contenedor. En prod debe ir por digest (@sha256:...) para ser inmutable."
  type        = string
}

variable "container_port" {
  description = "Puerto que expone el contenedor."
  type        = number
  default     = 8080
}

variable "health_check_path" {
  description = "Ruta del health check del ALB."
  type        = string
  default     = "/health"
}

variable "cpu" {
  description = "CPU de la tarea (unidades Fargate)."
  type        = number
  default     = 256
}

variable "memory" {
  description = "Memoria de la tarea (MiB)."
  type        = number
  default     = 512
}

variable "min_capacity" {
  description = "Tareas minimas."
  type        = number
  default     = 1
}

variable "max_capacity" {
  description = "Tareas maximas."
  type        = number
  default     = 4
}

variable "cpu_target" {
  description = "Objetivo de CPU promedio (%) para target tracking."
  type        = number
  default     = 60
}

variable "memory_target" {
  description = "Objetivo de memoria promedio (%) para target tracking."
  type        = number
  default     = 70
}

variable "requests_per_target" {
  description = "Objetivo de requests por tarea por minuto (ALBRequestCountPerTarget)."
  type        = number
  default     = 1000
}

variable "use_fargate_spot" {
  description = "Repartir las tareas por encima de on_demand_base entre Fargate y Fargate Spot."
  type        = bool
  default     = false
}

variable "on_demand_base" {
  description = "Numero minimo de tareas que siempre corren en Fargate on-demand."
  type        = number
  default     = 1
}

variable "certificate_arn" {
  description = "Certificado ACM para el listener HTTPS. Vacio = solo HTTP (unicamente para dev/demo)."
  type        = string
  default     = ""
}

variable "enable_waf" {
  description = "Asociar AWS WAF (reglas administradas) al ALB."
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "Retencion de logs de la aplicacion."
  type        = number
  default     = 30
}

variable "kms_key_arn" {
  description = "KMS key para logs y secretos."
  type        = string
}

variable "secrets" {
  description = "Mapa NOMBRE_VARIABLE => ARN del secreto en Secrets Manager. Se inyectan en runtime; nunca pasan por Terraform ni por el pipeline."
  type        = map(string)
  default     = {}
}

variable "environment_variables" {
  description = "Variables de entorno NO sensibles."
  type        = map(string)
  default     = {}
}

variable "permissions_boundary_arn" {
  description = "Permissions boundary obligatorio para los roles IAM."
  type        = string
}

variable "alarm_sns_topic_arn" {
  description = "Topic SNS para alarmas (vacio = sin notificacion)."
  type        = string
  default     = ""
}

variable "deletion_protection" {
  description = "Proteccion contra borrado del ALB."
  type        = bool
  default     = false
}
