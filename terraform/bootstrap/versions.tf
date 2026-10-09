terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.67"
    }
  }

  # El bootstrap crea el bucket de estado, por eso arranca con estado local.
  # Tras el primer apply se migra con: terraform init -migrate-state
  # descomentando el bloque backend "s3" de abajo.
  # backend "s3" {}
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
      Stack       = "bootstrap"
    }
  }
}
