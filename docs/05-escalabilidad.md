# 6. Cómo escalaría la solución

Hay que escalar **dos cosas**: la **aplicación** (más tráfico) y la **plataforma/pipeline** (más equipos, servicios y cuentas).

## 6.1 Escalar la aplicación (runtime)

### Horizontal y automático (implementado en `modules/ecs-service`)

| Política | Métrica | Objetivo | Por qué |
|---|---|---|---|
| Target tracking | `ECSServiceAverageCPUUtilization` | 60 % | Cargas limitadas por CPU |
| Target tracking | `ECSServiceAverageMemoryUtilization` | 70 % | Cargas limitadas por memoria |
| Target tracking | `ALBRequestCountPerTarget` | 1000 req/min por tarea | **Demanda real**: escala aunque la CPU no suba (apps limitadas por I/O) |

- **Scale-out rápido (60 s) y scale-in conservador (300 s)** para evitar oscilaciones (*flapping*).
- Con varias políticas, ECS escala hacia afuera si **cualquiera** lo pide y hacia adentro solo si **todas** lo permiten.
- `min_capacity = 3` en prod (una tarea por AZ, para sobrevivir a la caída de una AZ) y `max_capacity = 20` como tope de costos.
- **Alarma `at-max-capacity`**: avisa si el servicio llega al tope (hay que subir el máximo o revisar cuotas).
- Para picos conocidos (campañas, cierres de mes): **scheduled scaling**. Para patrones repetitivos: **predictive scaling**.

### Costo eficiente

- **Graviton (ARM64)**: cerca de 20 % más barato por la misma capacidad.
- **Fargate Spot**: prod usa 3 tareas on-demand de base y el excedente se reparte con Spot (hasta −70 %). Dev es 100 % Spot.
- **Compute Savings Plans** para la base estable.
- Right-sizing continuo con Compute Optimizer y Container Insights.

### Alta disponibilidad

- 3 AZs, NAT por AZ, ALB multi-AZ y tareas repartidas entre AZs.
- Circuit breaker con rollback automático y despliegue rolling (`min 100 % / max 200 %`): no se pierde capacidad durante el despliegue.
- **Siguiente nivel**: blue/green con CodeDeploy o canary con ECS (desplazar 10 % del tráfico, observar y continuar). DR multi-región (pilot light o warm standby) con Route 53 health checks y ECR/Secrets replicados.

### Capas de datos y caché (cuando aplique)

- Aurora Serverless v2 o RDS con réplicas de lectura, RDS Proxy para el pool de conexiones, ElastiCache para caché y SQS para desacoplar trabajo asíncrono.
- CloudFront delante del ALB para contenido estático y como capa extra de protección (Shield).

## 6.2 Escalar la plataforma y el pipeline

| Desafío al crecer | Solución |
|---|---|
| Más servicios | El módulo `ecs-service` se **versiona** (tags semver en un repo de módulos o en un registry privado). Cada servicio lo consume fijando la versión |
| Estados grandes y planes lentos | **Dividir el estado por dominio o capa**: `network` → `shared` → `service-x`, conectados con `terraform_remote_state` o data sources. Menor blast radius y planes más rápidos |
| Más cuentas y entornos | **AWS Control Tower / Account Factory for Terraform**: cuentas nuevas con baseline (CloudTrail, Config, GuardDuty, roles OIDC) en minutos |
| Repetición de código entre entornos | **Terragrunt** o Terraform Stacks para no duplicar configuración |
| Muchos PRs en paralelo | Planes solo de los directorios que cambiaron (`paths` filter / `dorny/paths-filter`), cache de providers y matrices dinámicas |
| Gobernanza a escala | Políticas como código con **OPA/Conftest** o Sentinel sobre el plan JSON: tags obligatorios, tipos de instancia permitidos, sin SG abiertos, límites de costo con **Infracost** en el PR |
| Más equipos | Plantillas de servicio (*golden paths*) en un portal tipo Backstage, CODEOWNERS por carpeta, runners propios o *larger runners* si el volumen lo exige |
