# 2. Código Terraform, validación y aprobación de cambios

## 2.1 Cómo está organizado el código

| Capa | Ruta | Propósito |
|---|---|---|
| Bootstrap | `terraform/bootstrap` | Se corre **una vez por cuenta**, de forma manual y con SSO. Crea el bucket de estado, la KMS y los roles OIDC. Después de eso nadie necesita credenciales para desplegar |
| Módulos | `terraform/modules/*` | Bloques reutilizables y probados (`network`, `ecs-service`, `github-oidc`) |
| Entornos | `terraform/envs/{dev,prod}` | Composición del entorno. Cada uno tiene su **propio estado, su propia cuenta y su propio rol** |

Decisiones clave del código:

- **Un estado por entorno.** Un error en dev no puede tocar el estado de prod.
- **`allowed_account_ids`** en el provider. Si por error el pipeline asumiera el rol de otra cuenta, Terraform se niega a ejecutar.
- **`default_tags`** (Project, Environment, ManagedBy, Repository, CostCenter): sirven para trazabilidad, costos y políticas ABAC.
- **Versiones fijadas** de Terraform y del provider, con `.terraform.lock.hcl` versionado. Dependabot las actualiza vía PR.
- **`lifecycle { ignore_changes = [desired_count] }`** en el servicio ECS. Así Terraform no pelea con el autoscaling.
- **`prevent_destroy`** en el bucket de estado.

## 2.2 Validación (en cada Pull Request → `terraform-ci.yml`)

| Etapa | Herramienta | Qué detecta |
|---|---|---|
| Formato | `terraform fmt -check` | Estilo inconsistente |
| Sintaxis y tipos | `terraform validate` | Errores de configuración en bootstrap, dev y prod |
| Pruebas unitarias | `terraform test` + `mock_provider` | Reglas de negocio del módulo, sin credenciales: sin IP pública, HTTPS, rollback, boundary, límites de escalado |
| Lint | `tflint` + ruleset AWS | Tipos de instancia inválidos, variables sin documentar, malas prácticas |
| Seguridad IaC | **Checkov** → SARIF en GitHub Code Scanning | Misconfiguraciones (S3 público, SG abiertos, falta de cifrado…). Hoy: 330 OK, 0 fallidos, y cada excepción tiene su justificación en línea |
| Secretos | **Gitleaks** | Llaves o tokens commiteados por error |
| Plan | `terraform plan` en dev **y** prod | Muestra **qué** va a cambiar. Usa un rol de **solo lectura** |
| Guardia | `scripts/plan-guard.sh` | Si el plan de prod destruye o reemplaza recursos, falla salvo que el PR tenga la etiqueta `allow-destroy` |

Estas mismas validaciones corren antes de cada commit gracias a `pre-commit`, para tener feedback en segundos.

## 2.3 Aprobación de cambios

La aprobación tiene **dos puertas**, cada una con su propio propósito:

### Puerta 1: revisión del Pull Request (se aprueba el *código* y el *plan*)

1. El pipeline publica en el PR un comentario por entorno con un resumen del tipo `Crear | Modificar | Reemplazar | Destruir`, la lista de **recursos críticos** que cambian (IAM, red, KMS, ALB, secretos) y el plan completo desplegable.
2. **Branch protection / Ruleset en `main`:**
   - PR obligatorio, sin push directo (tampoco para administradores).
   - **Checks obligatorios:** `Validación estática y seguridad`, `Plan (dev)` y `Plan (prod)`.
   - **Al menos 1 aprobación de CODEOWNERS.** Para `envs/prod`, `modules/github-oidc` y `.github/` se exige también al equipo de seguridad.
   - Las aprobaciones se descartan si llega un commit nuevo (*dismiss stale approvals*).
   - Conversaciones resueltas, rama al día con `main` y commits firmados.
3. El revisor **aprueba el plan, no solo el diff**. Un cambio de una línea puede reemplazar una base de datos, y eso solo se ve en el plan.

### Puerta 2: aprobación del despliegue a prod (se aprueba la *ejecución*)

- El job `apply-prod` corre dentro del **GitHub Environment `prod`**, que está configurado con:
  - **Required reviewers**: 2 personas, sin auto-aprobación (*prevent self-review*).
  - **Deployment branches**: solo `main`.
  - **Wait timer** opcional, y ventanas de despliegue si la empresa las usa.
- El aprobador ve en el *job summary* el resumen del **plan de prod recién generado**, que es exactamente el que se va a aplicar.
- Hay además una **garantía técnica**, no solo de proceso: el rol `gha-terraform-apply-prod` **solo confía** en tokens OIDC con `sub = repo:sdm07/devops-terraform:environment:prod`. Si un job no pasó por la aprobación del environment, AWS simplemente no le da credenciales.

## 3. Despliegue DEV → PROD

`terraform-cd.yml` se dispara con el merge a `main`:

```
plan-dev ─► apply-dev ─► smoke-dev ─► plan-prod ─► [🔒 aprobación] ─► apply-prod ─► smoke-prod
```

### En DEV

1. **plan-dev**: corre con el rol de plan y guarda el `tfplan` como artefacto.
2. **apply-dev** (environment `dev`, sin aprobadores o con uno, según el equipo): asume el rol de apply de dev y ejecuta `terraform apply tfplan`.
3. **Verificación**: `aws ecs wait services-stable` más un smoke test a `/health`. Si falla, **prod no arranca**.

### En PROD

4. **plan-prod**: se genera el plan contra el estado real de prod y se publica para el aprobador.
5. **Aprobación manual** en el environment `prod`.
6. **apply-prod**: aplica **el plan guardado**, sin volver a calcularlo. Si alguien cambió el estado entre el plan y el apply, Terraform rechaza el plan por *stale* y hay que reiniciar el flujo. Así se aplica exactamente lo que se aprobó.
7. **Verificación**: espera la estabilidad del servicio y corre el smoke test. A nivel de aplicación, el **circuit breaker de ECS** revierte solo a la task definition anterior si las tareas nuevas no pasan los health checks.

### Principios

- **Promover, no reconstruir:** el mismo commit (y la misma imagen, por digest) pasa por dev y luego por prod.
- **Concurrencia 1** (`concurrency: terraform-cd`, `cancel-in-progress: false`): nunca hay dos applies a la vez y nunca se cancela uno a medias.
- **Rollback de infraestructura** = `git revert` del PR y el pipeline normal. El repositorio es la única fuente de verdad.
- **Drift detection** diaria (`terraform-drift.yml`): si alguien cambió algo en la consola, se abre un issue automáticamente.

### ¿Y la imagen de la aplicación?

El repo de la app tiene su propio pipeline: build → tests → scan de la imagen (Trivy/Inspector) → firma (cosign / AWS Signer) → push a ECR en Shared Services. Después **abre un PR automático en este repo** que actualiza `container_image`: un tag en dev y un **digest** en prod. Con eso, el despliegue de la app sigue el mismo flujo de revisión, plan, aprobación y apply, y queda auditado (GitOps).
