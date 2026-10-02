# PROD: alta disponibilidad, imagen inmutable por digest, mas retencion.
project        = "simapp"
environment    = "prod"
aws_account_id = "222222222222"
region         = "us-east-1"

vpc_cidr           = "10.20.0.0/16"
az_count           = 3
single_nat_gateway = false # un NAT por AZ: sin punto unico de falla

# Mismo artefacto validado en dev, referenciado por digest (inmutable).
container_image  = "333333333333.dkr.ecr.us-east-1.amazonaws.com/simapp@sha256:0000000000000000000000000000000000000000000000000000000000000000"
cpu              = 512
memory           = 1024
min_capacity     = 3 # al menos una tarea por AZ
max_capacity     = 20
use_fargate_spot = true
on_demand_base   = 3 # piso estable en on-demand, picos en Spot

certificate_arn    = "arn:aws:acm:us-east-1:222222222222:certificate/00000000-0000-0000-0000-000000000000"
log_retention_days = 365
alarm_email        = "oncall@example.com"
