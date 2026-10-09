terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.67"
    }
  }

  # Configuracion parcial: bucket/region/key vienen de backend.hcl.
  # Bloqueo nativo en S3 (use_lockfile) -> no hace falta DynamoDB.
  backend "s3" {}
}

provider "aws" {
  region = var.region

  # Defensa en profundidad: aunque el pipeline asuma un rol equivocado,
  # Terraform se niega a operar fuera de la cuenta esperada.
  allowed_account_ids = [var.aws_account_id]

  default_tags {
    tags = {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
      Repository  = "sdm07/devops-terraform"
      CostCenter  = var.cost_center
    }
  }
}
