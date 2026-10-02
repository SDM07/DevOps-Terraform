# DEV: barato, rapido de iterar, misma topologia que prod.
project        = "simapp"
environment    = "dev"
aws_account_id = "111111111111"
region         = "us-east-1"

vpc_cidr           = "10.10.0.0/16"
az_count           = 2
single_nat_gateway = true # un solo NAT: ahorro de costos

container_image  = "333333333333.dkr.ecr.us-east-1.amazonaws.com/simapp:dev-latest"
cpu              = 256
memory           = 512
min_capacity     = 1
max_capacity     = 3
use_fargate_spot = true
on_demand_base   = 0 # dev puede correr 100% en Spot

certificate_arn    = ""
log_retention_days = 14
alarm_email        = ""
