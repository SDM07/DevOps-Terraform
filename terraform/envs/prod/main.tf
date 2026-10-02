# -----------------------------------------------------------------------------
# Composicion del entorno. dev y prod usan EXACTAMENTE los mismos modulos;
# solo cambian los valores de terraform.tfvars (tamano, HA, retencion...).
# Asi lo que se probo en dev es lo mismo que llega a prod.
# -----------------------------------------------------------------------------

locals {
  name = "${var.project}-${var.environment}"
}

data "aws_caller_identity" "current" {}

# Creado por el bootstrap: techo de permisos de todo rol del pipeline.
data "aws_iam_policy" "app_boundary" {
  name = "app-workload-boundary"
}

# ------------------------------- Cifrado -------------------------------------
data "aws_iam_policy_document" "kms" {
  #checkov:skip=CKV_AWS_109:Key policy; "*" significa "esta key" y el acceso se acota via IAM
  #checkov:skip=CKV_AWS_111:Key policy; "*" significa "esta key" y el acceso se acota via IAM
  #checkov:skip=CKV_AWS_356:Key policy; "*" significa "esta key" y el acceso se acota via IAM
  statement {
    sid       = "AccountAdmin"
    actions   = ["kms:*"]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }

  statement {
    sid = "CloudWatchLogs"
    actions = [
      "kms:Encrypt*",
      "kms:Decrypt*",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:Describe*",
    ]
    resources = ["*"]
    principals {
      type        = "Service"
      identifiers = ["logs.${var.region}.amazonaws.com"]
    }
    condition {
      test     = "ArnLike"
      variable = "kms:EncryptionContext:aws:logs:arn"
      values   = ["arn:aws:logs:${var.region}:${data.aws_caller_identity.current.account_id}:*"]
    }
  }

  statement {
    sid       = "CloudWatchAlarmsToSns"
    actions   = ["kms:Decrypt", "kms:GenerateDataKey*"]
    resources = ["*"]
    principals {
      type        = "Service"
      identifiers = ["cloudwatch.amazonaws.com"]
    }
  }
}

resource "aws_kms_key" "main" {
  description             = "Cifrado de logs, secretos y SNS de ${local.name}"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.kms.json
}

resource "aws_kms_alias" "main" {
  name          = "alias/${local.name}"
  target_key_id = aws_kms_key.main.key_id
}

# ------------------------------- Secretos ------------------------------------
# Terraform crea el "contenedor" del secreto pero NUNCA su valor: el valor
# se carga fuera de banda (consola/CLI con SSO o rotacion automatica), por
# lo que no aparece en el codigo, en el plan ni en el state.
resource "aws_secretsmanager_secret" "db_password" {
  #checkov:skip=CKV2_AWS_57:La rotacion se habilita al crear la base de datos (Lambda de rotacion RDS)
  name                    = "${local.name}/db-password"
  description             = "Credencial de base de datos de la aplicacion"
  kms_key_id              = aws_kms_key.main.arn
  recovery_window_in_days = var.environment == "prod" ? 30 : 7
}

# ------------------------------- Alarmas -------------------------------------
resource "aws_sns_topic" "alarms" {
  name              = "${local.name}-alarms"
  kms_master_key_id = aws_kms_key.main.id
}

resource "aws_sns_topic_subscription" "alarms_email" {
  count     = var.alarm_email == "" ? 0 : 1
  topic_arn = aws_sns_topic.alarms.arn
  protocol  = "email"
  endpoint  = var.alarm_email
}

# -------------------------------- Modulos ------------------------------------
module "network" {
  source = "../../modules/network"

  name                     = local.name
  cidr_block               = var.vpc_cidr
  az_count                 = var.az_count
  single_nat_gateway       = var.single_nat_gateway
  flow_logs_retention_days = var.log_retention_days
  kms_key_arn              = aws_kms_key.main.arn
  permissions_boundary_arn = data.aws_iam_policy.app_boundary.arn
}

module "app" {
  source = "../../modules/ecs-service"

  name               = local.name
  environment        = var.environment
  vpc_id             = module.network.vpc_id
  public_subnet_ids  = module.network.public_subnet_ids
  private_subnet_ids = module.network.private_subnet_ids

  container_image  = var.container_image
  cpu              = var.cpu
  memory           = var.memory
  min_capacity     = var.min_capacity
  max_capacity     = var.max_capacity
  use_fargate_spot = var.use_fargate_spot
  on_demand_base   = var.on_demand_base

  certificate_arn     = var.certificate_arn
  enable_waf          = true
  deletion_protection = var.environment == "prod"
  log_retention_days  = var.log_retention_days

  kms_key_arn              = aws_kms_key.main.arn
  permissions_boundary_arn = data.aws_iam_policy.app_boundary.arn
  alarm_sns_topic_arn      = aws_sns_topic.alarms.arn

  environment_variables = {
    APP_ENV   = var.environment
    LOG_LEVEL = var.environment == "prod" ? "info" : "debug"
  }

  secrets = {
    DB_PASSWORD = aws_secretsmanager_secret.db_password.arn
  }
}
