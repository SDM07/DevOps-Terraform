# Guion del video (≈ 15–18 minutos)

> Consejo: graba en bloques, uno por sección, y luego une los clips. Ten abiertos en pestañas: el diagrama `docs/diagramas/arquitectura.drawio` en app.diagrams.net (3 páginas), VS Code con el repo, el PR de ejemplo en GitHub y la pestaña Actions.

| # | Bloque | Tiempo | Qué mostrar en pantalla |
|---|---|---|---|
| 0 | Intro | 0:00–0:45 | Tu cara / portada |
| 1 | Arquitectura | 0:45–3:30 | `docs/diagramas/01` y `02` |
| 2 | Código Terraform + aprobación | 3:30–7:00 | VS Code + PR en GitHub |
| 3 | Despliegue DEV → PROD | 7:00–9:00 | `terraform-cd.yml` + diagrama 03 + Environments |
| 4 | Ramas, secretos y credenciales | 9:00–11:00 | `github-oidc/main.tf` + Settings |
| 5 | EC2 / ECS / EKS | 11:00–12:15 | Tabla de `04-ec2-ecs-eks.md` |
| 6 | Escalado | 12:15–13:30 | Bloque de autoscaling del módulo |
| 7 | Seguridad adicional | 13:30–14:45 | `06-seguridad-zero-trust.md` |
| 8 | Casos prácticos | 14:45–17:30 | `07-casos-practicos.md` |
| 9 | Cierre | 17:30–18:00 | README |

---

### 0 · Intro (45 s)
> "Hola, soy ___. Voy a presentar una propuesta de pipeline y arquitectura operativa para gestionar infraestructura en AWS con Terraform: cómo se validan y aprueban los cambios, cómo se despliegan a dev y prod, cómo se manejan credenciales y secretos, y cómo todo esto se alinea con Zero Trust. Todo el código está en el repositorio y lo validé con `terraform validate`, pruebas unitarias y Checkov."

### 1 · Arquitectura (2:45)
Muestra el **diagrama 01**:
> "A la izquierda está GitHub, que es la única puerta de entrada para cambiar infraestructura. A la derecha, AWS Organizations con cuentas separadas: shared services para las imágenes, dev y prod. Separo por cuenta porque es el límite de aislamiento más fuerte de AWS: si se comprometen credenciales de dev, prod no se toca."

> "Fíjense que no hay llaves de AWS en ningún lado. GitHub se autentica con OIDC: cada ejecución recibe un token firmado y AWS le entrega credenciales temporales de una hora. Hay dos roles por cuenta: uno de solo lectura para el plan y otro de escritura que solo se puede asumir desde el environment protegido."

Cambia al **diagrama 02**:
> "En runtime: WAF, después un ALB con TLS 1.3 en subredes públicas, y las tareas de ECS Fargate en subredes privadas sin IP pública. El security group de las tareas solo acepta tráfico del security group del ALB: eso es microsegmentación. Para hablar con ECR, Secrets Manager o CloudWatch se usan VPC endpoints, así que ese tráfico no sale a Internet. Prod usa 3 zonas, con un NAT por zona."

### 2 · Código Terraform y aprobación (3:30)
En VS Code, recorre el árbol:
> "Tres capas. El **bootstrap**, que se corre una sola vez por cuenta y crea el bucket de estado cifrado con KMS y los roles OIDC. Los **módulos** reutilizables: network, ecs-service y github-oidc. Y los **entornos** dev y prod, que llaman a los mismos módulos y solo cambian los valores del tfvars. Así lo que probé en dev es lo que llega a prod."

Abre `envs/prod/versions.tf` y señala `allowed_account_ids` y `use_lockfile`. Abre `modules/ecs-service/main.tf` (task definition endurecida y circuit breaker).

Abre `terraform-ci.yml`:
> "En cada PR corre fmt, validate, tflint, pruebas unitarias con `terraform test` y proveedor simulado, Checkov para seguridad y Gitleaks para secretos. Después, un plan contra dev y contra prod con el rol de solo lectura."

Muestra el PR con el comentario del plan (o `scripts/plan-guard.sh`):
> "El plan se publica en el PR con un resumen de qué se crea, modifica, reemplaza o destruye, y resalta los recursos críticos. Si el plan de prod destruye o reemplaza algo, el pipeline lo bloquea salvo que alguien ponga la etiqueta `allow-destroy`, que es una decisión humana explícita."

> "La aprobación tiene dos puertas. Primera: el PR. Branch protection en main, checks obligatorios y aprobación de CODEOWNERS, y seguridad cuando se toca prod o IAM. El revisor aprueba el **plan**, no solo el diff. Segunda: el despliegue a prod, que pide la aprobación de dos personas en el GitHub Environment."

### 3 · Despliegue DEV → PROD (2:00)
Muestra el **diagrama 03** y `terraform-cd.yml`:
> "Al hacer merge a main, el mismo commit va primero a dev: plan, apply del plan guardado, espera a que ECS se estabilice y un smoke test. Si dev falla, prod ni arranca. Después se genera el plan de prod, el aprobador lo ve en el resumen del job y, cuando aprueba, se aplica **exactamente ese plan**. Si el estado cambió en el medio, Terraform rechaza el plan por stale."

> "Hay concurrencia 1, así que nunca hay dos applies a la vez. El rollback es un `git revert`, y además ECS tiene un circuit breaker que revierte solo si las tareas nuevas no quedan sanas. Y cada día un workflow de drift detection compara AWS con el código y abre un issue si alguien cambió algo a mano."

Muestra Settings → Environments → prod (*required reviewers* y *deployment branches: main*).

### 4 · Ramas, secretos y credenciales (2:00)
> "Uso **trunk-based**: main es la única rama larga, las feature branches viven poco y se hace merge squash. No uso una rama por entorno porque dev y prod terminan divergiendo; aquí la promoción la hace el pipeline, no git."

Abre `modules/github-oidc/main.tf` y muestra la condición `sub`:
> "El rol de apply de prod solo confía en tokens cuyo subject sea `environment:prod`. Si un job no pasó la aprobación, AWS no le da credenciales: es un control técnico, no solo de proceso. Además, todo rol que cree el pipeline lleva un **permissions boundary**, así que aunque alguien escriba una policy con asterisco, el permiso efectivo no sale del techo."

> "Para secretos de la aplicación, Terraform crea el secreto en Secrets Manager pero **no su valor**, así que no queda en el código, en el plan ni en el state. ECS lo inyecta al arrancar la tarea y el execution role solo puede leer esos ARNs. Las personas entran con SSO y MFA, sin usuarios IAM."

### 5 · EC2 / ECS / EKS (1:15)
> "Elegí **ECS Fargate**: no hay servidores que parchear, cada tarea corre aislada en su propia micro-VM, escala en segundos y se integra de forma nativa con ALB, IAM y Secrets. EC2 lo usaría si hay software que no se puede contenerizar o licencias por host. EKS, si la organización ya opera Kubernetes, tiene decenas de servicios o necesita portabilidad multi-cloud. Como red, identidad y pipeline no dependen del cómputo, cambiar a EKS es agregar un módulo hermano."

### 6 · Escalado (1:15)
> "Escalo por tres métricas: CPU, memoria y **requests por tarea**. Esta última es clave porque una app limitada por I/O se pone lenta sin que suba la CPU. Scale-out en 60 segundos y scale-in en 5 minutos para evitar oscilaciones. Mínimo 3 tareas en prod, una por zona. Para costos: Graviton y Fargate Spot para el excedente. A nivel plataforma: módulos versionados, estado dividido por dominio y Control Tower para crear cuentas nuevas."

### 7 · Seguridad adicional (1:15)
> "Además de lo que ya mostré, propondría: SCPs para negar regiones y la desactivación de CloudTrail, GuardDuty con runtime monitoring para ECS, Security Hub con CIS, Config, Access Analyzer, CloudTrail organizacional inmutable, firma de imágenes y despliegue por digest, policy as code con OPA sobre el plan, Infracost en el PR, fijar las GitHub Actions por SHA y backups con vault lock en otra cuenta."

### 8 · Casos prácticos (2:45)
- **Caso 1:** "Primero mitigo: congelo el pipeline y hago revert. Luego reviso el **plan aprobado**: casi siempre un cambio pequeño escondía un replace o un destroy. Después, drift, security groups, IAM y health checks, y CloudTrail. Prevención: la guardia del plan, `prevent_destroy`, `create_before_destroy` y apply solo desde el pipeline."
- **Caso 2:** "Si el código es el mismo, la diferencia es el entorno: permisos o SCPs de prod, variables que solo existen en prod, drift o lock del estado, cuotas, recursos que ya existen, código condicional que solo corre en prod, o el environment de GitHub mal configurado."
- **Caso 3:** "Verifico que la política exista y que su alarma reciba datos. Después, que la métrica represente el cuello de botella: CPU no sirve para apps I/O-bound. Luego, si escaló pero no ayudó (máximo, base de datos saturada, tareas que no arrancan) y que nada lo bloquee, como Terraform pisando desired_count o el scaling suspendido."

### 9 · Cierre (30 s)
> "En resumen: cambios solo vía PR, validados y con plan visible; dos puertas de aprobación; el mismo artefacto promovido de dev a prod; cero credenciales estáticas; y mínimo privilegio en cada capa. Gracias."
