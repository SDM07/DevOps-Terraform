# Diálogo completo del video

> Texto para leer o memorizar, palabra por palabra. Entre corchetes **[PANTALLA]** va lo que debe verse en ese momento.
> Duración aproximada: 16–18 minutos a ritmo tranquilo (≈ 130 palabras por minuto).
> Antes de grabar, abre en pestañas: `docs/diagramas/arquitectura.drawio` en app.diagrams.net, VS Code con el repo, GitHub (pestañas *Actions* y *Settings → Environments*).

---

## 0. Introducción (≈ 45 s)

**[PANTALLA]** Tu cámara, o el README del repositorio.

> Hola, mi nombre es **[tu nombre]** y en este video les voy a presentar mi propuesta de pipeline y arquitectura operativa para gestionar infraestructura en AWS con Terraform.
>
> Voy a cubrir siete puntos: el diagrama de la arquitectura, el código de Terraform y cómo se aprueban los cambios, cómo se despliega a dev y luego a prod, la estrategia de ramas y el manejo de secretos y credenciales, por qué elegí ECS frente a EC2 o EKS, cómo escalaría la solución y qué controles de seguridad adicionales agregaría. Al final respondo los tres casos prácticos.
>
> Todo lo que voy a mostrar está en el repositorio. El código lo validé con `terraform validate`, pruebas unitarias con `terraform test`, tflint y Checkov, que pasa sin hallazgos abiertos.

---

## 1. Arquitectura e infraestructura (≈ 3 min)

**[PANTALLA]** draw.io, página **"1 · Arquitectura general"**. Señala a la izquierda el bloque de GitHub.

> Empiezo por la vista general. A la izquierda está GitHub, que es la **única puerta de entrada** para cambiar la infraestructura. Nadie modifica AWS desde la consola ni desde su computador: todo cambio entra por un Pull Request.

**[PANTALLA]** Señala el bloque grande de AWS Organizations.

> A la derecha está AWS, organizado con **AWS Organizations y varias cuentas**. Arriba están las cuentas de soporte: la cuenta Management, con Organizations, las políticas de control de servicio (las SCPs) y el inicio de sesión único con IAM Identity Center. La cuenta de Seguridad y Log Archive, donde se centralizan CloudTrail, GuardDuty, Security Hub y Config. Y la cuenta de Shared Services, donde vive el registro de imágenes, ECR.
>
> Abajo están las dos cuentas de trabajo: **DEV y PROD**. Las separé en cuentas distintas porque la cuenta es el límite de aislamiento más fuerte que tiene AWS. Si alguien compromete credenciales de dev, prod no se toca. Además, cada cuenta tiene su propio estado de Terraform, sus propios roles y sus propias políticas.

**[PANTALLA]** Señala las flechas de colores entre GitHub y los roles IAM OIDC.

> Fíjense en las flechas. En toda esta arquitectura **no hay llaves de acceso de AWS guardadas en ningún lado**. GitHub Actions se autentica con OIDC: cada ejecución recibe un token firmado por GitHub, AWS lo valida y entrega credenciales temporales que duran una hora.
>
> En cada cuenta hay dos roles. La flecha azul punteada es el rol de **plan**, que es de solo lectura y lo usan los Pull Requests. Las flechas verde y ámbar son el rol de **apply**, que tiene permisos de escritura, y que solo se puede asumir desde el *environment* protegido de GitHub. Es decir, en prod solo después de que dos personas aprobaron.

**[PANTALLA]** Cambia a la página **"2 · Runtime prod (ECS Fargate)"**.

> Ahora el detalle del runtime en producción. El tráfico de los usuarios entra por HTTPS, pasa primero por **AWS WAF**, que bloquea ataques comunes y limita las peticiones por IP, y llega a un **Application Load Balancer** con TLS 1.3 que redirige todo el HTTP a HTTPS.
>
> La VPC está repartida en **tres zonas de disponibilidad**. En las subredes públicas solo están el balanceador y los NAT Gateways, uno por zona para no tener un punto único de falla. Las **tareas de ECS Fargate** corren en subredes privadas, **sin IP pública**.
>
> El security group de las tareas solo acepta tráfico que venga del security group del balanceador, y solo en el puerto de la aplicación. Eso es microsegmentación. Y para hablar con ECR, Secrets Manager, CloudWatch o KMS, las tareas usan **VPC endpoints**, así que ese tráfico nunca sale a Internet.
>
> A la derecha está el plano de control: el autoscaling, CloudWatch con las alarmas que notifican por SNS, Secrets Manager y KMS para el cifrado.

---

## 2. Código Terraform y aprobación de cambios (≈ 3 min 30 s)

**[PANTALLA]** VS Code, árbol de la carpeta `terraform/`.

> Pasemos al código. Lo organicé en tres capas.
>
> La primera es el **bootstrap**. Se ejecuta una sola vez por cuenta, de forma manual, por un administrador con SSO. Crea el bucket S3 donde se guarda el estado, cifrado con KMS y con versionado, y crea los roles OIDC del pipeline. Después de esto, nadie vuelve a necesitar credenciales para desplegar.
>
> La segunda capa son los **módulos** reutilizables: `network` para la VPC, `ecs-service` para el servicio con el balanceador, el WAF y el autoscaling, y `github-oidc` para la identidad del pipeline.
>
> La tercera son los **entornos**, dev y prod. Los dos llaman exactamente a los mismos módulos; lo único que cambia es el archivo `terraform.tfvars`. Así, lo que probé en dev es lo mismo que llega a prod.

**[PANTALLA]** Abre `terraform/envs/prod/versions.tf`.

> Un par de detalles. El estado usa el **bloqueo nativo de S3**, con `use_lockfile`, así que ya no necesito DynamoDB. Y en el provider puse `allowed_account_ids`: si por error el pipeline asumiera el rol de otra cuenta, Terraform se niega a ejecutar.

**[PANTALLA]** Abre `.github/workflows/terraform-ci.yml`.

> Ahora, cómo **se validan** los cambios. En cada Pull Request corre este workflow. Primero, la validación estática: `terraform fmt`, `terraform validate` en todos los entornos, `tflint`, y **pruebas unitarias** con `terraform test` usando un proveedor simulado, sin necesidad de credenciales. Las pruebas verifican, por ejemplo, que las tareas no tengan IP pública, que se fuerce HTTPS y que el rollback automático esté activo.
>
> Después viene la seguridad: **Checkov** busca malas configuraciones en el código y **Gitleaks** busca secretos que se hayan subido por error. Finalmente se ejecuta un **plan contra dev y contra prod** con el rol de solo lectura.

**[PANTALLA]** Abre `scripts/plan-guard.sh` (o un PR con el comentario del plan).

> El plan se publica como comentario en el PR, con un resumen de cuántos recursos se crean, se modifican, se reemplazan y se destruyen, y resalta los recursos críticos: IAM, red, KMS o el balanceador. Además hay una **guardia**: si el plan de prod destruye o reemplaza algo, el pipeline falla, salvo que alguien agregue la etiqueta `allow-destroy`. Así, destruir algo en producción siempre es una decisión humana explícita.

> Y ahora, cómo **se aprueban** los cambios. La aprobación tiene **dos puertas**.
>
> La primera es el Pull Request. La rama `main` está protegida: no se puede hacer push directo, los checks son obligatorios y se necesita la aprobación de los CODEOWNERS. Si el cambio toca prod, IAM o el pipeline, también tiene que aprobar el equipo de seguridad. Algo importante: **el revisor aprueba el plan, no solo el código**. Un cambio de una línea puede reemplazar un recurso completo, y eso solo se ve en el plan.
>
> La segunda puerta es el despliegue a producción, que veremos en el siguiente punto.

---

## 3. Despliegue en DEV y luego en PROD (≈ 2 min)

**[PANTALLA]** draw.io, página **"3 · Pipeline CI/CD"**, carril inferior. Luego `.github/workflows/terraform-cd.yml`.

> Cuando el PR se aprueba y se hace merge a `main`, arranca el workflow de despliegue. El mismo commit pasa **primero por dev**.
>
> Se genera el plan de dev y se aplica **exactamente ese plan guardado**. Después el pipeline espera a que el servicio de ECS se estabilice y hace un *smoke test* contra el endpoint `/health`. Si algo falla en dev, **prod ni siquiera arranca**.
>
> Si dev sale bien, se genera el plan de producción y se publica en el resumen del job para que el aprobador vea exactamente qué va a cambiar.

**[PANTALLA]** GitHub → Settings → Environments → `prod`.

> Aquí está la segunda puerta. El job de apply en prod corre dentro del *environment* `prod` de GitHub, que exige la aprobación de **dos personas**, no permite que el autor se apruebe a sí mismo y solo acepta despliegues desde `main`.
>
> Y no es solo un control de proceso, es un **control técnico**: el rol de escritura de la cuenta prod solo confía en tokens cuyo *subject* sea `environment:prod`. Si un job no pasó por esa aprobación, AWS simplemente no le entrega credenciales.
>
> Al aprobar, se aplica el plan guardado. Si el estado cambió entre el plan y el apply, Terraform rechaza el plan por desactualizado, así que siempre se aplica exactamente lo que se aprobó. Luego vuelve a correr el smoke test.
>
> Tres cosas más: hay concurrencia uno, así que nunca corren dos despliegues al mismo tiempo. El rollback de infraestructura es un `git revert` que pasa por el mismo flujo. Y cada día un workflow de **detección de drift** compara AWS con el código y abre un issue si alguien cambió algo a mano.

---

## 4. Estrategia de ramas, secretos y credenciales (≈ 2 min)

**[PANTALLA]** `docs/03-ramas-secretos-credenciales.md`, sección de ramas.

> Para las ramas uso **trunk-based development**. `main` es la única rama de larga vida y siempre está lista para desplegar. Cada cambio se hace en una rama `feature/` de vida corta y entra con merge *squash*. Los hotfix siguen exactamente el mismo flujo: no existe un atajo a producción.
>
> No uso una rama por entorno, tipo develop, staging y main, porque con el tiempo esas ramas divergen y lo que se probó en dev deja de ser lo que llega a prod. Aquí **la promoción la hace el pipeline, no git**.

**[PANTALLA]** `terraform/modules/github-oidc/main.tf`, la condición `sub` del rol de apply.

> Para las **credenciales del pipeline**, como ya mostré, uso OIDC: credenciales temporales y cero llaves estáticas. Además, todo rol IAM que cree el pipeline debe llevar un **permissions boundary**. Aunque alguien escriba una política con asterisco en un módulo, el permiso real nunca puede superar ese techo. Eso evita escalar privilegios a través del pipeline.
>
> Para las **personas**: acceso con SSO y MFA desde IAM Identity Center, sin usuarios IAM ni llaves personales. En producción el acceso por defecto es de solo lectura.
>
> Y para los **secretos de la aplicación**: Terraform crea el secreto en Secrets Manager, pero **no su valor**. El valor se carga por fuera o lo rota AWS automáticamente, así que nunca aparece en el código, en el plan ni en el estado. ECS inyecta el secreto en la tarea al arrancar, y el rol de ejecución solo puede leer los secretos declarados para ese servicio. Todo está cifrado con llaves KMS propias de cada entorno.

---

## 5. Decisión entre EC2, ECS y EKS (≈ 1 min 30 s)

**[PANTALLA]** `docs/04-ec2-ecs-eks.md`, tabla comparativa.

> Para la aplicación elegí **ECS sobre Fargate**, y explico por qué.
>
> Con Fargate no hay servidores que parchear ni sistemas operativos que mantener; cada tarea corre aislada en su propia micro máquina virtual; escala en segundos y se integra de forma nativa con el balanceador, con IAM por tarea y con Secrets Manager. Para un equipo pequeño o mediano es el mejor equilibrio entre carga operativa, seguridad y costo.
>
> **EC2** lo usaría si hay software que no se puede contenerizar, licencias atadas al servidor o cargas muy estables donde los Savings Plans de EC2 abaratan bastante.
>
> **EKS** lo elegiría si la organización ya opera Kubernetes, si hay decenas o cientos de servicios, o si se necesita portabilidad entre nubes. Pero tiene un costo operativo alto: actualizaciones de versión frecuentes, add-ons, nodos y RBAC.
>
> Lo importante es que el diseño soporta cualquiera de los tres: la red, la identidad y el pipeline no dependen del cómputo. Pasar a EKS o EC2 es agregar un módulo hermano con la misma interfaz.

---

## 6. Cómo escalaría la solución (≈ 1 min 30 s)

**[PANTALLA]** `terraform/modules/ecs-service/main.tf`, bloque de autoscaling.

> El escalado lo pienso en dos niveles.
>
> **Primero, la aplicación.** El servicio escala con tres políticas de *target tracking*: CPU al 60 %, memoria al 70 % y **peticiones por tarea**. Esta última es clave, porque una aplicación limitada por entrada y salida se pone lenta sin que suba la CPU. El escalado hacia afuera reacciona en 60 segundos y el escalado hacia adentro espera 5 minutos para evitar oscilaciones.
>
> En prod tengo un mínimo de tres tareas, una por zona, para sobrevivir a la caída de una zona completa, y un máximo de veinte, con una alarma que avisa si se alcanza ese tope. Para costos uso procesadores **Graviton** y **Fargate Spot** para el excedente, manteniendo una base estable on-demand.
>
> **Segundo, la plataforma.** Cuando crezcan los equipos y servicios: módulos versionados, el estado dividido por dominio para reducir el impacto de un error, Control Tower para crear cuentas nuevas con todo el baseline de seguridad, y políticas como código con OPA sobre el plan.

---

## 7. Controles de seguridad adicionales (≈ 1 min 30 s)

**[PANTALLA]** `docs/06-seguridad-zero-trust.md`.

> Todo esto está alineado con **Zero Trust**: nunca confiar, siempre verificar. Cada identidad se verifica, los permisos son mínimos y temporales, la red está segmentada, todo va cifrado y todo queda registrado.
>
> Además de lo que ya mostré, agregaría estos controles:
> - **SCPs** para bloquear regiones que no se usan, impedir que se desactive CloudTrail o GuardDuty y prohibir la creación de usuarios IAM.
> - **GuardDuty** con monitoreo en tiempo de ejecución para ECS, y **Security Hub** con el estándar CIS.
> - **AWS Config** y **IAM Access Analyzer** para cumplimiento continuo y para detectar permisos que sobran.
> - **CloudTrail organizacional** guardado de forma inmutable en la cuenta de Log Archive.
> - **Firma y escaneo de imágenes**, desplegando en producción siempre por *digest*.
> - **Fijar las GitHub Actions por SHA**, exigir commits firmados y controlar la salida de red de los runners.
> - **Infracost** en el PR, para que el revisor vea el impacto en costos, y **AWS Backup** con *vault lock* en otra cuenta, como protección frente a ransomware.

---

## 8. Casos prácticos (≈ 3 min)

**[PANTALLA]** `docs/07-casos-practicos.md`.

### Caso 1: "Un cambio pequeño en Terraform tumbó producción"

> Lo primero es **estabilizar**, no investigar. Declaro el incidente, congelo el pipeline para que no entren más cambios y revierto: `git revert` del commit y pasa por el pipeline. Si se perdieron datos, restauro desde backup.
>
> Después reviso **el plan que se aprobó**. En la gran mayoría de los casos, un cambio "pequeño" escondía un **reemplazo o un destroy** que nadie vio: renombrar un recurso, cambiar el nombre de un target group o el CIDR de una subred fuerza un reemplazo. Luego reviso si hubo drift, si se tocó un security group, una política IAM o el health check del balanceador, y confirmo en CloudTrail qué se ejecutó.
>
> Para prevenirlo: la guardia del plan que ya implementé, `prevent_destroy` en recursos críticos, `create_before_destroy` y que solo el pipeline pueda aplicar en prod.

### Caso 2: "El pipeline falla solo en prod, pero en dev funciona bien"

> Si el código es el mismo, la diferencia está en el entorno. Mis hipótesis, en orden:
>
> Primero, **permisos**: el rol de prod tiene menos permisos, una SCP de la cuenta de prod niega la acción, o la relación de confianza OIDC no coincide con el nombre del environment.
> Segundo, **variables propias de prod**: un certificado, una imagen por digest que no existe, un CIDR o un tamaño inválido.
> Tercero, el **estado**: drift por cambios manuales, un lock huérfano o un plan desactualizado.
> Cuarto, **cuotas de servicio**: prod pide más NAT, más IPs elásticas o más tareas.
> Quinto, **recursos que ya existen** con el mismo nombre.
> Y sexto, **código condicional** que solo se ejecuta en prod y que dev nunca ejercitó, o el environment de GitHub mal configurado.
>
> Para evitarlo: paridad entre entornos y planes de prod en cada PR, que ya están implementados, así el error aparece antes del merge.

### Caso 3: "El autoscaling de ECS no responde aunque la app está lenta"

> Que la app esté lenta no significa que la métrica de escalado haya superado su umbral.
>
> Primero verifico que la política exista, que esté asociada al servicio correcto y que su alarma de CloudWatch esté recibiendo datos. Las actividades de escalado dicen exactamente por qué no escaló.
>
> Segundo, y es la causa más común: **la métrica no representa el cuello de botella**. Si escalo solo por CPU y la aplicación está esperando a la base de datos o a una API externa, la CPU se queda baja mientras la latencia sube. Por eso escalo también por peticiones por tarea, y se puede usar latencia o una métrica personalizada.
>
> Tercero, reviso si **escaló pero no ayudó**: ya llegó al máximo, la base de datos está saturada, o las tareas nuevas no arrancan por falta de IPs, cuotas o health checks que fallan.
>
> Y cuarto, que nada lo esté bloqueando: por ejemplo, Terraform sobrescribiendo el número deseado de tareas, que en mi módulo evito con `ignore_changes`, o el escalado suspendido después de un despliegue.

---

## 9. Cierre (≈ 30 s)

**[PANTALLA]** draw.io, página 1, o tu cámara.

> Para resumir: todo cambio entra por un Pull Request, validado con pruebas y análisis de seguridad, y con el plan visible. Hay dos puertas de aprobación. El mismo commit se promueve de dev a prod aplicando exactamente el plan aprobado. No existen credenciales estáticas, y cada capa sigue el principio de mínimo privilegio.
>
> El código, los diagramas y la documentación están en el repositorio. Muchas gracias por su tiempo; quedo atento a sus preguntas.
