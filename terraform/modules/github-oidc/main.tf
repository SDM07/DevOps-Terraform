# -----------------------------------------------------------------------------
# Identidad federada GitHub Actions -> AWS (sin access keys estaticas).
#
# Dos roles por cuenta, con minimo privilegio y confianza muy acotada:
#   * plan  : solo lectura. Lo asumen los Pull Requests y la rama main.
#   * apply : escritura. SOLO lo asume un job que corre dentro del
#             GitHub Environment del mismo nombre (dev / prod), es decir,
#             despues de pasar las reglas de proteccion (aprobadores).
# -----------------------------------------------------------------------------

locals {
  oidc_host = "token.actions.githubusercontent.com"
  repo      = var.github_repository
}

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_oidc_provider ? 1 : 0

  url            = "https://${local.oidc_host}"
  client_id_list = ["sts.amazonaws.com"]
  # AWS ya valida el certificado de GitHub contra su CA de confianza;
  # el thumbprint se mantiene por compatibilidad con el provider.
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

data "aws_iam_openid_connect_provider" "github" {
  count = var.create_oidc_provider ? 0 : 1
  url   = "https://${local.oidc_host}"
}

locals {
  oidc_provider_arn = var.create_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : data.aws_iam_openid_connect_provider.github[0].arn
}

# ------------------------------- Rol PLAN ------------------------------------
data "aws_iam_policy_document" "plan_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:aud"
      values   = ["sts.amazonaws.com"]
    }

    # PRs del repo y ejecuciones sobre main (drift detection / plan previo al apply).
    condition {
      test     = "StringLike"
      variable = "${local.oidc_host}:sub"
      values = [
        "repo:${local.repo}:pull_request",
        "repo:${local.repo}:ref:refs/heads/main",
      ]
    }
  }
}

resource "aws_iam_role" "plan" {
  name                 = "gha-terraform-plan-${var.environment}"
  description          = "GitHub Actions - terraform plan (solo lectura) en ${var.environment}"
  assume_role_policy   = data.aws_iam_policy_document.plan_trust.json
  max_session_duration = 3600
}

resource "aws_iam_role_policy_attachment" "plan_readonly" {
  role       = aws_iam_role.plan.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/ReadOnlyAccess"
}

# El plan necesita leer el estado y usar el lockfile en S3, nada mas.
data "aws_iam_policy_document" "state_access" {
  statement {
    sid       = "StateList"
    actions   = ["s3:ListBucket"]
    resources = [var.state_bucket_arn]
  }

  statement {
    sid       = "StateReadWrite"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["${var.state_bucket_arn}/*"]
  }

  statement {
    sid       = "StateKms"
    actions   = ["kms:Decrypt", "kms:Encrypt", "kms:GenerateDataKey", "kms:DescribeKey"]
    resources = [var.state_kms_key_arn]
  }
}

resource "aws_iam_role_policy" "plan_state" {
  name   = "terraform-state"
  role   = aws_iam_role.plan.id
  policy = data.aws_iam_policy_document.state_access.json
}

# Deny explicito: aunque ReadOnlyAccess lo permitiera, el rol de plan
# nunca puede leer valores de secretos.
data "aws_iam_policy_document" "plan_deny_secrets" {
  statement {
    effect = "Deny"
    actions = [
      "secretsmanager:GetSecretValue",
      "ssm:GetParameter*",
      "kms:Decrypt",
    ]
    not_resources = [var.state_kms_key_arn]
  }
}

resource "aws_iam_role_policy" "plan_deny_secrets" {
  name   = "deny-secret-values"
  role   = aws_iam_role.plan.id
  policy = data.aws_iam_policy_document.plan_deny_secrets.json
}

# ------------------------------- Rol APPLY -----------------------------------
data "aws_iam_policy_document" "apply_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Solo jobs dentro del GitHub Environment protegido de este entorno.
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:sub"
      values   = ["repo:${local.repo}:environment:${var.environment}"]
    }
  }
}

resource "aws_iam_role" "apply" {
  name                 = "gha-terraform-apply-${var.environment}"
  description          = "GitHub Actions - terraform apply en ${var.environment}"
  assume_role_policy   = data.aws_iam_policy_document.apply_trust.json
  max_session_duration = 3600
}

resource "aws_iam_role_policy" "apply_state" {
  name   = "terraform-state"
  role   = aws_iam_role.apply.id
  policy = data.aws_iam_policy_document.state_access.json
}

# Permisos acotados a los servicios que gestiona este repositorio.
data "aws_iam_policy_document" "apply_services" {
  # El rol de apply necesita crear infraestructura; su alcance se limita por
  # servicios, por la confianza OIDC (solo environment protegido), por el
  # permissions boundary obligatorio y por las SCPs de la organizacion.
  #checkov:skip=CKV_AWS_107:Rol de despliegue; acotado por OIDC + environment + SCP
  #checkov:skip=CKV_AWS_109:Rol de despliegue; IAM acotado a /app/* con boundary obligatorio
  #checkov:skip=CKV_AWS_111:Rol de despliegue; acotado por OIDC + environment + SCP
  #checkov:skip=CKV_AWS_356:Rol de despliegue; acotado por OIDC + environment + SCP
  statement {
    sid = "ManagedServices"
    actions = [
      "ec2:*",
      "ecs:*",
      "ecr:*",
      "elasticloadbalancing:*",
      "application-autoscaling:*",
      "cloudwatch:*",
      "logs:*",
      "wafv2:*",
      "acm:DescribeCertificate",
      "acm:ListCertificates",
      "kms:*",
      "secretsmanager:CreateSecret",
      "secretsmanager:DeleteSecret",
      "secretsmanager:DescribeSecret",
      "secretsmanager:TagResource",
      "secretsmanager:UntagResource",
      "secretsmanager:PutResourcePolicy",
      "secretsmanager:GetResourcePolicy",
      "secretsmanager:DeleteResourcePolicy",
      "secretsmanager:UpdateSecret",
      "sns:*",
    ]
    resources = ["*"]
  }

  # IAM: solo puede crear/gestionar roles bajo el path /app/ y SIEMPRE con
  # el permissions boundary obligatorio -> evita escalamiento de privilegios.
  statement {
    sid = "IamScopedRoles"
    actions = [
      "iam:CreateRole",
      "iam:PutRolePolicy",
      "iam:AttachRolePolicy",
      "iam:DetachRolePolicy",
      "iam:DeleteRolePolicy",
      "iam:PutRolePermissionsBoundary",
    ]
    resources = ["arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/app/*"]

    condition {
      test     = "StringEquals"
      variable = "iam:PermissionsBoundary"
      values   = [aws_iam_policy.app_boundary.arn]
    }
  }

  statement {
    sid = "IamScopedRolesNoBoundaryCondition"
    actions = [
      "iam:DeleteRole",
      "iam:GetRole",
      "iam:GetRolePolicy",
      "iam:ListRolePolicies",
      "iam:ListAttachedRolePolicies",
      "iam:ListInstanceProfilesForRole",
      "iam:TagRole",
      "iam:UntagRole",
      "iam:UpdateRole",
      "iam:UpdateAssumeRolePolicy",
      "iam:PassRole",
    ]
    resources = ["arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/app/*"]
  }

  statement {
    sid       = "ServiceLinkedRoles"
    actions   = ["iam:CreateServiceLinkedRole"]
    resources = ["*"]
  }

  statement {
    sid       = "ReadIam"
    actions   = ["iam:Get*", "iam:List*"]
    resources = ["*"]
  }

  # Nunca puede tocar sus propios roles de pipeline ni el boundary.
  statement {
    sid    = "ProtectPipelineIdentity"
    effect = "Deny"
    actions = [
      "iam:*Role*",
      "iam:*Policy*",
    ]
    resources = [
      "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/gha-terraform-*",
      aws_iam_policy.app_boundary.arn,
    ]
  }
}

resource "aws_iam_role_policy" "apply_services" {
  name   = "managed-services"
  role   = aws_iam_role.apply.id
  policy = data.aws_iam_policy_document.apply_services.json
}

# Permissions boundary: techo maximo de cualquier rol que cree el pipeline
# (task roles de ECS, etc.). Aunque alguien escriba una policy "*:*" en un
# modulo, el rol efectivo nunca podra salir de este limite.
data "aws_iam_policy_document" "app_boundary" {
  # Un boundary es un TECHO, no otorga permisos: cada rol los recibe en su
  # propia policy con recursos concretos.
  #checkov:skip=CKV_AWS_108:Boundary (techo); los permisos efectivos se acotan en cada rol
  #checkov:skip=CKV_AWS_111:Boundary (techo); los permisos efectivos se acotan en cada rol
  #checkov:skip=CKV_AWS_356:Boundary (techo); los permisos efectivos se acotan en cada rol
  statement {
    sid = "AllowedForWorkloads"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams",
      "ecr:GetAuthorizationToken",
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
      "secretsmanager:GetSecretValue",
      "kms:Decrypt",
      "s3:GetObject",
      "s3:PutObject",
      "ssmmessages:*",
      "xray:PutTraceSegments",
      "xray:PutTelemetryRecords",
      "cloudwatch:PutMetricData",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "DenyIam"
    effect    = "Deny"
    actions   = ["iam:*", "organizations:*", "sts:AssumeRole"]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "app_boundary" {
  name        = "app-workload-boundary"
  description = "Permissions boundary obligatorio para roles creados por el pipeline"
  policy      = data.aws_iam_policy_document.app_boundary.json
}
