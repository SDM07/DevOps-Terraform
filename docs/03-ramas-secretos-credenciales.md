# 4. Estrategia de ramas, manejo de secretos y credenciales

## 4.1 Estrategia de ramas: trunk-based development

```
main  ──●────────●──────────●────────►   (siempre desplegable · protegida)
         \      / \        /
 feature/ ●──●─●   ●──●───●               (vida corta: horas o pocos días)
```

| Rama | Uso | Reglas |
|---|---|---|
| `main` | Única rama de larga vida. Lo que hay en `main` está (o va a estar) en dev y en prod | PR obligatorio, checks verdes, CODEOWNERS, commits firmados, sin force-push |
| `feature/<ticket>-<desc>` | Cualquier cambio | Vida corta, un cambio lógico por PR, merge **squash** |
| `hotfix/<ticket>` | Urgencias | **Mismo flujo** que el resto (con revisores de guardia). No existe un atajo a prod |

**¿Por qué no una rama por entorno (`develop` → `staging` → `main`)?**

- Con ramas por entorno, el código de dev y el de prod **divergen** (cherry-picks, merges cruzados) y lo probado en dev ya no es lo que se despliega en prod.
- En trunk-based, **la promoción la hace el pipeline, no git**: el mismo commit pasa por dev y luego por prod. Los entornos se diferencian por carpeta (`envs/dev`, `envs/prod`) y por valores, no por rama.
- Para releases auditables se pueden usar **tags semánticos** (`v1.4.0`) sobre `main`.

**Convenciones:** Conventional Commits (`feat:`, `fix:`, `chore:`) y la plantilla de PR, con checklist de plan revisado, impacto en prod y plan de rollback.

## 4.2 Credenciales de AWS: cero llaves estáticas

### Pipeline (máquinas) → GitHub OIDC

```
GitHub Actions ──(JWT firmado por GitHub, dura minutos)──► AWS STS AssumeRoleWithWebIdentity
                                                             │  valida: aud = sts.amazonaws.com
                                                             │          sub = repo:sdm07/devops-terraform:<contexto>
                                                             ▼
                                         credenciales temporales (1 h) del rol que corresponda
```

| Rol (por cuenta) | Quién lo puede asumir (`sub`) | Permisos |
|---|---|---|
| `gha-terraform-plan-<env>` | `pull_request` y `ref:refs/heads/main` | `ReadOnlyAccess` + lectura y escritura del estado. **Deny explícito** a `secretsmanager:GetSecretValue` y `ssm:GetParameter*` |
| `gha-terraform-apply-<env>` | **Solo** `environment:<env>`, es decir, después de pasar las reglas del GitHub Environment | Servicios que gestiona el repo. IAM limitado a roles en `/app/*` **con permissions boundary obligatorio**. Deny para modificar sus propios roles |

Por qué funciona:

- **No hay nada que robar:** no existen `AWS_ACCESS_KEY_ID` en GitHub Secrets ni en laptops.
- Las credenciales **caducan solas** (1 h) y llevan el `run_id` en el nombre de sesión, así que CloudTrail sabe qué ejecución hizo cada llamada.
- Un PR de un fork **no recibe token OIDC**.
- **Permissions boundary** (`app-workload-boundary`): aunque alguien escriba en un módulo una policy `"Action": "*"` para un rol de la app, el permiso efectivo nunca sale del techo del boundary. Esto evita escalar privilegios a través del pipeline.

### Personas → IAM Identity Center (SSO)

- Login con el IdP corporativo (Entra ID / Okta / Google) + **MFA**. Se usan *permission sets* por rol (ReadOnly, Developer, Admin-BreakGlass).
- Las sesiones son temporales (`aws sso login`). **No hay usuarios IAM ni access keys personales.**
- En prod las personas tienen **solo lectura** por defecto. El acceso de escritura es *just-in-time*: se aprueba, tiene tiempo limitado y queda auditado.
- Cuenta **break-glass** con credenciales en caja fuerte, alarma en cada uso y revisión posterior.

## 4.3 Secretos de la aplicación

| Principio | Implementación |
|---|---|
| **El valor nunca está en git, ni en el plan, ni en el state** | Terraform crea el *contenedor* `aws_secretsmanager_secret`, pero **no** el `secret_version`. El valor se carga fuera de banda (CLI con SSO) o, mejor aún, lo genera y lo rota AWS (`manage_master_user_password` en RDS) |
| **Inyección en runtime** | La task definition referencia el ARN (`secrets = [{ name, valueFrom }]`). El agente de ECS lo lee al arrancar la tarea con el *execution role* |
| **Mínimo privilegio** | El execution role puede hacer `GetSecretValue` **solo** sobre los ARNs declarados en el servicio |
| **Cifrado** | KMS con llave propia por entorno (CMK) y rotación anual automática |
| **Rotación** | Rotación automática de Secrets Manager (Lambda de rotación de RDS) |
| **Separación** | Secretos de dev y de prod en cuentas distintas: un desarrollador con acceso a dev no ve los de prod |
| **Detección** | Gitleaks en pre-commit y en CI, y GitHub Secret Scanning + push protection |

**Secretos del pipeline:** en GitHub solo se guardan **variables no sensibles** (ARNs de roles). Si alguna vez hiciera falta un secreto real (un token de un SaaS), va como *environment secret* del environment correspondiente. Así solo lo ven los jobs que pasaron la aprobación de ese entorno.

**¿Y el state?** El state puede contener valores sensibles (por ejemplo, outputs de recursos). Por eso el bucket está cifrado con KMS, es privado, exige TLS y solo lo pueden leer los roles del pipeline. Las variables sensibles se marcan con `sensitive = true` y se usa `ephemeral` / write-only arguments (Terraform ≥ 1.10/1.11) cuando el provider lo soporta, para que el valor no se guarde en el state.
