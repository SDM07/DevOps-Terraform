# 7. Controles de seguridad y alineación con Zero Trust

> **Zero Trust:** *"nunca confiar, siempre verificar"*. Estar dentro de la red no da permisos. Cada acceso se autentica, se autoriza con mínimo privilegio, es temporal y queda registrado. Se asume que ya hubo una brecha y se limita el daño (blast radius).

## 7.1 Principios de Zero Trust → cómo se implementan

| Principio | Implementación en esta propuesta |
|---|---|
| **Verificar explícitamente cada identidad** | Personas: SSO + MFA (IAM Identity Center). Pipeline: token OIDC firmado por GitHub, validado por STS con `aud` y `sub` exactos (repo + contexto) |
| **Mínimo privilegio** | Rol de plan de solo lectura con deny a secretos. Rol de apply limitado por servicio. IAM solo en `/app/*` con **permissions boundary**. Execution role con acceso solo a los secretos declarados. Task role que arranca sin permisos |
| **Acceso temporal (JIT)** | Credenciales STS de 1 h. Sin access keys estáticas. Escritura en prod solo con aprobación y tiempo limitado |
| **Contexto y postura** | El rol de apply de prod **solo** se asume desde el environment `prod` (rama main + aprobación de 2 personas). `allowed_account_ids` evita aplicar en la cuenta equivocada |
| **Asumir brecha / segmentación** | Una cuenta por entorno. Subredes privadas sin IP pública. **Microsegmentación SG→SG** (las tareas solo aceptan al ALB). VPC endpoints. Default SG cerrado |
| **Cifrar todo** | TLS 1.3 en el ALB, KMS (CMK con rotación) para estado, logs, secretos y SNS. Buckets con TLS obligatorio |
| **Inspeccionar y registrar todo** | CloudTrail organizacional, VPC Flow Logs, ALB access logs, logs de WAF, Container Insights, drift detection |

## 7.2 Seguridad en cada etapa (DevSecOps)

### Shift-left (desarrollador)
- `pre-commit`: fmt, validate, tflint, Checkov, Gitleaks, `detect-aws-credentials` y `detect-private-key`.

### Pipeline
- **Checkov** (IaC) con salida SARIF hacia GitHub Code Scanning. Las excepciones se justifican **en línea** (`#checkov:skip=ID:razón`) y quedan revisables en el PR.
- **Gitleaks** + GitHub **Secret Scanning con push protection**.
- **`terraform test`** con aserciones de seguridad (sin IP pública, HTTPS, boundary, sin ECS Exec en prod).
- **Guardia del plan**: destroy/replace en prod requiere una etiqueta explícita.
- **Endurecimiento de GitHub Actions:** `permissions` mínimos por job (por defecto `contents: read`), `id-token: write` solo donde se usa OIDC, PRs de forks sin acceso a AWS, Dependabot para las actions. **Recomendado:** fijar las actions por SHA (`uses: org/action@<sha>`), activar *StepSecurity Harden-Runner* para controlar la salida de red del runner y exigir **commits firmados**.
- **Supply chain de imágenes** (en el repo de la app): escaneo (Trivy / ECR Enhanced Scanning con Inspector), SBOM, firma con cosign / AWS Signer y despliegue en prod **por digest**.

### Runtime
- **WAF**: Common Rule Set, Known Bad Inputs (incluye Log4Shell) y rate limit por IP.
- **Contenedor endurecido**: `readonlyRootFilesystem`, usuario no root (`1000:1000`), `capabilities.drop = ALL`, Graviton, sin ECS Exec en prod.
- **ALB**: `drop_invalid_header_fields`, redirección a HTTPS, política TLS 1.2/1.3 y protección contra borrado en prod.

## 7.3 Controles adicionales que propondría (nivel organización)

| Control | Para qué |
|---|---|
| **SCPs** en Organizations | Negar regiones no usadas, negar la desactivación de CloudTrail/GuardDuty/Config, negar la creación de usuarios IAM o access keys, exigir cifrado, proteger los roles `gha-terraform-*` |
| **GuardDuty** (incluye ECS Runtime Monitoring) | Detección de amenazas: credenciales comprometidas, cripto-minería, comportamiento anómalo en contenedores |
| **Security Hub** + estándares CIS / AWS FSBP | Postura centralizada y priorizada |
| **AWS Config** + conformance packs | Cumplimiento continuo y detección de recursos no conformes fuera de Terraform |
| **IAM Access Analyzer** | Detectar accesos externos o públicos y policies sin usar (right-sizing de permisos) |
| **CloudTrail organizacional** en la cuenta Log Archive, con Object Lock | Auditoría inmutable |
| **Shield Advanced + CloudFront** (si el riesgo lo justifica) | Protección DDoS L3–L7 |
| **Verified Access** o **Client VPN + SSO** | Acceso de personas a herramientas internas sin VPN plana, según identidad y postura del dispositivo |
| **Policy as code (OPA/Conftest)** sobre el plan JSON | Reglas de negocio: tags obligatorios, sin `0.0.0.0/0` salvo en ALB, tamaños permitidos |
| **Infracost** en el PR | Que el revisor vea el impacto de costo del cambio |
| **Backup** (AWS Backup) con vault lock en otra cuenta | Resiliencia frente a ransomware o borrado accidental |
| **Runbooks + game days** | Preparación ante incidentes y pruebas de restauración |
