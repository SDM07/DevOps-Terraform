# -----------------------------------------------------------------------------
# BOOTSTRAP (se ejecuta UNA vez por cuenta, por un administrador, con
# credenciales temporales de IAM Identity Center / SSO):
#   1. KMS key + bucket S3 para el estado remoto (versionado, cifrado, privado).
#   2. Identidad federada OIDC para GitHub Actions (roles plan / apply).
# Despues de esto, NADIE vuelve a necesitar credenciales para desplegar:
# todo pasa por el pipeline.
# -----------------------------------------------------------------------------

data "aws_caller_identity" "current" {}

locals {
  state_bucket = "${var.project}-tfstate-${var.environment}-${data.aws_caller_identity.current.account_id}"
}

data "aws_iam_policy_document" "state_kms" {
  # Patron estandar de AWS: la cuenta delega el control en IAM; el acceso
  # real lo limitan las policies de los roles plan/apply.
  #checkov:skip=CKV_AWS_109:Key policy por defecto; el acceso se acota via IAM
  #checkov:skip=CKV_AWS_111:Key policy por defecto; el acceso se acota via IAM
  #checkov:skip=CKV_AWS_356:En una key policy "*" significa "esta key"
  statement {
    sid       = "AccountAdmin"
    actions   = ["kms:*"]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }
}

resource "aws_kms_key" "state" {
  description             = "Cifrado del estado de Terraform (${var.environment})"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.state_kms.json
}

resource "aws_kms_alias" "state" {
  name          = "alias/${var.project}-tfstate-${var.environment}"
  target_key_id = aws_kms_key.state.key_id
}

resource "aws_s3_bucket" "state" {
  #checkov:skip=CKV_AWS_18:Los accesos al estado se auditan con CloudTrail data events a nivel organizacion
  #checkov:skip=CKV_AWS_144:El estado es reconstruible y esta versionado; CRR no compensa el costo
  #checkov:skip=CKV2_AWS_62:No se requieren notificaciones de eventos sobre el estado
  bucket = local.state_bucket

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.state.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    id     = "expire-old-state-versions"
    status = "Enabled"
    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 90
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# Solo TLS y solo los roles del pipeline (mas administradores break-glass).
data "aws_iam_policy_document" "state_bucket" {
  statement {
    sid     = "DenyInsecureTransport"
    effect  = "Deny"
    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.state.arn,
      "${aws_s3_bucket.state.arn}/*",
    ]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "state" {
  bucket = aws_s3_bucket.state.id
  policy = data.aws_iam_policy_document.state_bucket.json
}

module "github_oidc" {
  source = "../modules/github-oidc"

  environment       = var.environment
  github_repository = var.github_repository
  state_bucket_arn  = aws_s3_bucket.state.arn
  state_kms_key_arn = aws_kms_key.state.arn
}
