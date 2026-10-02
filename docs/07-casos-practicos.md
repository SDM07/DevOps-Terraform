# Casos prácticos

---

## Caso 1: "Un cambio pequeño en Terraform tumbó producción. ¿Qué revisarías primero?"

### Primero: estabilizar (mitigar antes de investigar)
1. **Declarar el incidente**, avisar al canal y nombrar un responsable. Congelar el pipeline de CD (*desactivar workflow* o bloquear el environment `prod`) para que no se apliquen más cambios encima.
2. **Revertir lo más rápido posible**:
   - Infra: `git revert <commit>` → PR express → pipeline. Si el apply dejó recursos a medias, se aplica el plan del revert.
   - Si es la app: el circuit breaker de ECS ya debió hacer rollback. Si no, `update-service` a la task definition anterior.
   - Si se borró un recurso con datos: restaurar desde snapshot / PITR / versión anterior del objeto S3.

### Luego: revisar, en este orden
1. **¿Qué cambió exactamente?** El commit del PR, el **plan que se aprobó** (comentario en el PR y artefacto `tfplan`) y el **log del apply**. La pregunta clave: ¿el plan mostraba un **replace (`-/+`)** o un **destroy** que pasó desapercibido? Muchos cambios "pequeños" fuerzan un reemplazo: renombrar un recurso o un SG, cambiar `name` en un ALB o target group, cambiar `cidr_block` o la AZ de una subred, cambiar `engine_version` / `identifier` en RDS, cambiar el `user_data` de un Launch Template.
2. **¿Se aplicó lo que se aprobó?** Comparar el plan del PR con el plan aplicado. Ver si alguien aplicó desde su laptop o si había **drift** (cambios manuales que Terraform "corrigió" y revirtió).
3. **Efectos colaterales no evidentes en el plan:**
   - **Security groups / NACL / rutas**: un `ingress` reemplazado deja una ventana sin reglas, o una ruta al NAT desaparece.
   - **IAM**: una policy reescrita le quitó a la app un permiso (`AccessDenied` en los logs).
   - **Orden de dependencias**: `create_before_destroy` faltante → se destruyó antes de crear.
   - **Health check** del target group cambiado (ruta o puerto) → todas las tareas marcadas *unhealthy*.
   - **Valores por defecto** de un módulo o del provider que cambiaron al actualizar la versión (`~>` demasiado amplio).
   - **`desired_count` / tamaños** sobrescritos que pisaron el autoscaling.
4. **Evidencia en AWS:** CloudTrail (qué API se llamó, quién y cuándo), eventos del servicio ECS, health del target group, alarmas 5XX y logs de la app.

### Prevención (post-mortem sin culpables)
- La **guardia del plan** bloquea destroy/replace en prod sin la etiqueta `allow-destroy` (ya implementado).
- `lifecycle { prevent_destroy = true }` en recursos con estado, `create_before_destroy` donde aplique, deletion protection en ALB/RDS.
- **Apply del plan guardado** (ya implementado) y prohibir apply local en prod (los permisos solo los tiene el pipeline).
- Pruebas de módulo (`terraform test`) que cubran el caso, y dev como entorno representativo de prod.
- Cambios grandes partidos en PRs pequeños, y despliegue canary / blue-green para la app.

---

## Caso 2: "El pipeline falla solo en prod, pero en dev funciona bien. ¿Qué hipótesis revisarías?"

El código es el mismo, así que la diferencia está en **el entorno, los permisos, el estado o los datos**. Hipótesis ordenadas de la más probable a la menos probable:

| # | Hipótesis | Cómo la verifico |
|---|---|---|
| 1 | **Permisos / identidad**: el rol de prod tiene menos permisos, una **SCP** de la OU de prod niega la acción (región, tipo de instancia, cifrado obligatorio), o la trust policy no coincide (`sub` del environment, nombre del environment mal escrito) | El error dice `AccessDenied` / `explicit deny in a service control policy` / `Not authorized to perform sts:AssumeRoleWithWebIdentity`. Revisar CloudTrail y IAM Policy Simulator |
| 2 | **Diferencias de variables / tfvars**: valores que solo existen en prod (certificado ACM, dominio, digest de la imagen, CIDR, tamaños) son inválidos, no existen o están en otra región | Comparar `envs/dev/terraform.tfvars` contra `envs/prod/terraform.tfvars`. Validar el ARN del certificado, que la imagen por digest exista en ECR y que prod tenga permiso de *pull* cross-account |
| 3 | **Estado / drift**: alguien cambió prod a mano, el estado está bloqueado (lock huérfano de un apply cancelado) o el plan quedó *stale* porque el estado cambió entre el plan y el apply | `terraform plan` en prod para ver diferencias inesperadas. Mensaje `Error acquiring the state lock` → revisar quién lo tiene antes de `force-unlock`. `Saved plan is stale` → regenerar |
| 4 | **Cuotas y límites de servicio**: prod pide más (3 AZ, 3 NAT, 20 tareas, más EIPs) y choca con cuotas de la cuenta (EIPs por región = 5, tareas Fargate, VPCs) | Service Quotas / mensaje `LimitExceeded`. Pedir aumento |
| 5 | **Recursos que ya existen / nombres únicos globales**: un bucket S3 o un nombre de ALB/rol ya existe en prod (creado a mano) | `AlreadyExists` / `BucketAlreadyOwnedByYou` → `terraform import` o un bloque `import {}` |
| 6 | **Configuración exclusiva de prod**: HTTPS / WAF / deletion protection / Multi-AZ solo están activos en prod (`count` / condicionales), así que ese código **nunca se ejercitó en dev** | Revisar condicionales `var.environment == "prod"`. Solución: que dev ejercite los mismos caminos (certificado también en dev) |
| 7 | **Protección del environment de GitHub**: el job espera aprobación, la rama no está permitida, faltan las variables del environment `prod` (`AWS_APPLY_ROLE_ARN`) o el secreto existe solo en dev | Settings → Environments → prod. Ver si el job quedó en *waiting* o si la variable sale vacía |
| 8 | **Red / dependencias externas**: el smoke test de prod falla por DNS, certificado o WAF bloqueando al runner (rate limit, geo), o el health check usa otra ruta | Revisar logs del WAF (`aws-waf-logs-*`), los eventos del servicio ECS y la salud de los targets |
| 9 | **Datos / escala**: migraciones o volumen de datos que solo existen en prod (timeouts del deploy, health check grace period corto) | Logs de la app, duración del arranque, subir `health_check_grace_period_seconds` |
| 10 | **Versiones**: el lock file o la versión de Terraform/provider difieren por cómo se ejecutó cada job | Ver que ambos usen `TF_VERSION` y el mismo `.terraform.lock.hcl` |

**Para que no vuelva a pasar:** paridad dev ↔ prod (mismos módulos y mismos caminos de código), un **entorno staging** en una cuenta con las mismas SCPs que prod, drift detection diario y planes de prod en cada PR (ya implementado). Así el fallo aparece **antes del merge** y no en el apply.

---

## Caso 3: "El autoscaling de ECS no responde aunque la app está lenta."

Que la app esté lenta **no significa** que la métrica de escalado haya pasado su umbral. Diagnóstico ordenado:

### 1. ¿La política existe y está viendo la métrica correcta?
- `aws application-autoscaling describe-scalable-targets --service-namespace ecs` y `describe-scaling-policies`: ¿hay *scalable target* registrado? ¿El `resource_id` apunta al cluster/servicio correcto (después de renombrar un servicio el target queda huérfano)?
- `describe-scaling-activities`: muestra **por qué** no escaló (por ejemplo, *"Failed to set desired count"* o ya estaba en el máximo).
- Las **alarmas de CloudWatch** que crea el target tracking: ¿están en `ALARM`, `OK` o `INSUFFICIENT_DATA`? Si están en `INSUFFICIENT_DATA`, la métrica no llega (por ejemplo, el `resource_label` del ALB está mal).

### 2. ¿La métrica refleja el cuello de botella real? (la causa más común)
- Si escala **solo por CPU** pero la app está limitada por **I/O**: espera a la base de datos, a una API externa, a un pool de conexiones o a threads. La CPU se queda en 20 % mientras la latencia sube, y nunca escala.
  - **Solución:** escalar por **`ALBRequestCountPerTarget`** (ya implementado), por **latencia** o por una **métrica custom** (profundidad de cola en SQS, conexiones activas, *backlog per task*).
- Si el **CPU/memory reservation** de la task es mayor que lo que la app usa, el porcentaje promedio nunca llega al objetivo.
- Si el target está **promediado** entre tareas y una sola tarea está saturada (hot task, sesiones sticky), el promedio esconde el problema.

### 3. ¿Escaló, pero no sirvió o no se nota?
- **Ya está en `max_capacity`** → alarma `at-max-capacity` (implementada). Subir el máximo.
- **El cuello de botella está aguas abajo**: la base de datos (CPU, conexiones, locks), una API externa o el NAT Gateway. Agregar tareas incluso **empeora** las cosas (más conexiones a la base de datos). La solución es RDS Proxy, réplicas de lectura, caché o colas.
- **Las tareas nuevas no arrancan**: falta de capacidad Fargate/Spot en la AZ (`capacity provider` sin base on-demand), **cuota** de tareas, **IPs agotadas** en las subredes privadas, error al bajar la imagen (sin endpoint de ECR ni NAT) o secretos inaccesibles. Revisar `describe-services` → *events*.
- **Las tareas arrancan pero no reciben tráfico**: el health check falla o el grace period es muy corto, así que el ALB las marca *unhealthy* y ECS las recicla en bucle.

### 4. ¿Está escalando demasiado lento?
- Cooldowns largos o un `scale_out_cooldown` mal puesto, y alarmas de target tracking que necesitan varios datapoints (≈ 3 min).
- Métricas con resolución de 1 minuto más el tiempo de arranque de la tarea (pull de la imagen + inicio de la app). **Mitigar con:** imágenes más livianas, health checks rápidos, `min_capacity` mayor, **scheduled scaling** antes de picos conocidos o **predictive scaling**.

### 5. ¿Alguien la está bloqueando?
- **Terraform** sobrescribiendo `desired_count` en cada apply. Por eso el módulo tiene `ignore_changes = [desired_count]`.
- El scalable target **suspendido** (`SuspendedState` → `DynamicScalingOutSuspended = true`) después de un despliegue o de un mantenimiento.
- Un despliegue en curso, o el circuit breaker haciendo rollback.

**Resumen para la respuesta en el video:** *"Primero confirmo que la política existe y que su alarma ve datos. Después, que la métrica represente el cuello de botella real (CPU no sirve para apps I/O-bound: uso requests por target o latencia). Luego verifico si escaló pero no ayudó (máximo alcanzado, base de datos saturada, tareas que no arrancan por IPs, cuotas o health checks). Por último, que nada lo esté bloqueando (Terraform pisando desired_count o scaling suspendido)."*
