# Puesta en marcha (paso a paso)

## 1. Bootstrap de cada cuenta (una sola vez, con SSO de administrador)

```bash
aws sso login --profile dev-admin
cd terraform/bootstrap
AWS_PROFILE=dev-admin terraform init
AWS_PROFILE=dev-admin terraform apply -var environment=dev
# Repetir con el perfil de prod y -var environment=prod (en otro workspace o directorio de estado)
```

Guarda los outputs: `state_bucket`, `plan_role_arn` y `apply_role_arn`.

> El bootstrap empieza con estado local. Después de crear el bucket, migra su propio estado a S3 (descomenta `backend "s3" {}` y ejecuta `terraform init -migrate-state`).

## 2. Actualizar la configuración del repo

- `terraform/envs/<env>/backend.hcl` → nombre real del bucket.
- `terraform/envs/<env>/terraform.tfvars` → `aws_account_id`, imagen, certificado y correo de alarmas.

## 3. Configurar GitHub

**Variables del repositorio** (Settings → Secrets and variables → Actions → Variables):

| Variable | Valor |
|---|---|
| `AWS_PLAN_ROLE_ARN_DEV` | `plan_role_arn` de dev |
| `AWS_PLAN_ROLE_ARN_PROD` | `plan_role_arn` de prod |

**Environments** (Settings → Environments):

| Environment | Variable `AWS_APPLY_ROLE_ARN` | Protección |
|---|---|---|
| `dev` | `apply_role_arn` de dev | Deployment branches: `main` |
| `prod` | `apply_role_arn` de prod | Required reviewers: 2 · Prevent self-review · Deployment branches: `main` · (opcional) wait timer |

**Ruleset de `main`** (Settings → Rules):
- Require a pull request: 1 aprobación, require review from Code Owners, dismiss stale approvals.
- Required status checks: `Validación estática y seguridad`, `Plan (dev)` y `Plan (prod)`.
- Require signed commits, block force pushes y require conversation resolution.
- Sin bypass para administradores.

**Seguridad del repo:** activar Secret scanning + Push protection, Dependabot alerts y Code scanning.

**Etiqueta:** crear la etiqueta `allow-destroy`.

## 4. Primer despliegue

1. Crear la rama `feature/primer-despliegue`, hacer un cambio y abrir el PR → revisar los planes comentados.
2. Aprobar y hacer merge → `terraform-cd` despliega dev, corre el smoke test y espera la aprobación de prod.
3. Aprobar en la pestaña Actions → se aplica prod.

## 5. Herramientas locales para desarrolladores

```bash
brew install terraform tflint checkov gitleaks pre-commit   # o equivalente
pre-commit install
```

> Lock files: se generaron para `linux_amd64` (runners de CI). Si trabajas en macOS, agrega tu plataforma con:
> `terraform providers lock -platform=linux_amd64 -platform=darwin_arm64 -platform=darwin_amd64`
