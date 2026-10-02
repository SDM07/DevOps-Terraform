# Pruebas unitarias del modulo con proveedor simulado (sin credenciales AWS).
# Se ejecutan en el pipeline con: terraform test

mock_provider "aws" {
  mock_data "aws_region" {
    defaults = { name = "us-east-1" }
  }

  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }

  mock_resource "aws_lb" {
    defaults = {
      arn        = "arn:aws:elasticloadbalancing:us-east-1:111111111111:loadbalancer/app/test/abc"
      arn_suffix = "app/test/abc"
    }
  }

  mock_resource "aws_lb_target_group" {
    defaults = {
      arn        = "arn:aws:elasticloadbalancing:us-east-1:111111111111:targetgroup/test/abc"
      arn_suffix = "targetgroup/test/abc"
    }
  }

  mock_resource "aws_wafv2_web_acl" {
    defaults = { arn = "arn:aws:wafv2:us-east-1:111111111111:regional/webacl/test/abc" }
  }

  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::111111111111:role/app/test" }
  }

  mock_resource "aws_ecs_task_definition" {
    defaults = { arn = "arn:aws:ecs:us-east-1:111111111111:task-definition/test:1" }
  }

  mock_resource "aws_cloudwatch_log_group" {
    defaults = { arn = "arn:aws:logs:us-east-1:111111111111:log-group:/ecs/test" }
  }
}

variables {
  name                     = "simapp-test"
  environment              = "prod"
  vpc_id                   = "vpc-123"
  public_subnet_ids        = ["subnet-a", "subnet-b"]
  private_subnet_ids       = ["subnet-c", "subnet-d"]
  container_image          = "333333333333.dkr.ecr.us-east-1.amazonaws.com/simapp@sha256:abc"
  kms_key_arn              = "arn:aws:kms:us-east-1:111111111111:key/test"
  permissions_boundary_arn = "arn:aws:iam::111111111111:policy/app-workload-boundary"
  certificate_arn          = "arn:aws:acm:us-east-1:111111111111:certificate/test"
  min_capacity             = 3
  max_capacity             = 10
}

run "tareas_sin_ip_publica" {
  command = plan

  assert {
    condition     = aws_ecs_service.app.network_configuration[0].assign_public_ip == false
    error_message = "Las tareas no deben tener IP publica."
  }
}

run "http_redirige_a_https_con_certificado" {
  command = plan

  assert {
    condition     = aws_lb_listener.http.default_action[0].type == "redirect"
    error_message = "Con certificado, el listener HTTP debe redirigir a HTTPS."
  }

  assert {
    condition     = aws_lb_listener.https[0].ssl_policy == "ELBSecurityPolicy-TLS13-1-2-2021-06"
    error_message = "El listener HTTPS debe usar politica TLS 1.2+/1.3."
  }
}

run "ecs_exec_deshabilitado_en_prod" {
  command = plan

  assert {
    condition     = aws_ecs_service.app.enable_execute_command == false
    error_message = "ECS Exec no debe estar habilitado en prod."
  }
}

run "rollback_automatico" {
  command = plan

  assert {
    condition     = aws_ecs_service.app.deployment_circuit_breaker[0].rollback == true
    error_message = "El circuit breaker con rollback debe estar habilitado."
  }
}

run "roles_con_permissions_boundary" {
  command = plan

  assert {
    condition     = aws_iam_role.task.permissions_boundary == var.permissions_boundary_arn && aws_iam_role.execution.permissions_boundary == var.permissions_boundary_arn
    error_message = "Todos los roles deben llevar el permissions boundary."
  }
}

run "autoscaling_respeta_limites" {
  command = plan

  assert {
    condition     = aws_appautoscaling_target.app.min_capacity == 3 && aws_appautoscaling_target.app.max_capacity == 10
    error_message = "Los limites de autoscaling no coinciden con las variables."
  }
}
