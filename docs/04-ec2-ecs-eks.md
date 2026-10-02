# 5. Decisión EC2 vs ECS vs EKS

## Recomendación: **ECS sobre Fargate**

Para una aplicación contenerizada típica (API o web stateless) y un equipo de plataforma pequeño o mediano, **ECS Fargate da el mejor equilibrio entre carga operativa, seguridad, costo y velocidad de entrega**.

## Comparación

| Criterio | EC2 (ASG) | ECS Fargate | EKS |
|---|---|---|---|
| **Qué gestiono yo** | SO, parches, AMIs, agente, runtime, escalado de nodos | Solo la tarea (imagen + CPU/memoria) | Control plane gestionado, pero nodos, add-ons, upgrades de versión cada ~14 meses, CNI, ingress, RBAC |
| **Carga operativa** | Alta | **Baja** | Alta (requiere equipo con experiencia en Kubernetes) |
| **Aislamiento** | Por instancia | **Cada tarea en su propia micro-VM (Firecracker)** | Pods comparten nodo (se puede mejorar con Fargate profiles) |
| **Superficie de ataque** | SO completo y SSH | Sin hosts ni SSH | Nodos + API de Kubernetes |
| **Velocidad de escalado** | Minutos (arranque de instancias) | Decenas de segundos | Segundos (pods) a minutos (nodos, más rápido con Karpenter) |
| **Costo** | El más bajo por cómputo si se usa bien (RI/Savings Plans), pero se paga lo ocioso | Paga por tarea. Spot hasta −70 % y Graviton −20 % | US$ ~73/mes por control plane + nodos. Eficiente a gran escala (bin-packing) |
| **Portabilidad** | Baja | Baja (API de AWS) | **Alta** (Kubernetes estándar, multi-cloud) |
| **Ecosistema** | — | Integración nativa (ALB, IAM por tarea, Secrets, CloudWatch) | **Enorme** (Helm, operators, service mesh, ArgoCD) |
| **Curva de aprendizaje** | Baja | **Baja** | Alta |

## Cuándo elegiría cada uno

**EC2:**
- Software que no se puede contenerizar, licencias atadas a host o kernels o drivers específicos.
- GPUs o instancias especializadas con uso alto y constante. Aun así, primero miraría ECS o EKS sobre EC2.
- Cargas muy estables donde Savings Plans en EC2 abaratan bastante.

**ECS Fargate (esta propuesta):**
- Microservicios o APIs stateless, equipos que quieren concentrarse en el producto y no en operar clusters.
- Cuando importan la seguridad por defecto (sin hosts, aislamiento por tarea) y el tiempo de salida a producción.
- Si el volumen crece mucho, se puede pasar a **ECS sobre EC2 con capacity providers** sin cambiar el modelo de despliegue.

**EKS:**
- La organización **ya opera Kubernetes** o tiene un estándar corporativo de K8s.
- Decenas o cientos de servicios, con necesidad de bin-packing, service mesh, operators o GitOps con ArgoCD.
- Requisitos de portabilidad multi-cloud o híbrida (EKS Anywhere).

## Cómo hace el diseño para "soportar" las tres opciones

La arquitectura está pensada para que el cómputo **sea intercambiable**:

- `modules/network` (VPC, subredes privadas, endpoints) y `modules/github-oidc` (identidad del pipeline) **no dependen** del cómputo.
- El pipeline (validación → plan → aprobación → apply) es el mismo para cualquier tipo de cómputo.
- El cómputo vive en un módulo propio (`modules/ecs-service`). Para otra opción se agrega un módulo hermano con la misma interfaz (`vpc_id`, subredes, imagen, min/max, secretos):
  - `modules/ec2-asg`: Launch Template (IMDSv2 obligatorio, AMI endurecida, SSM en vez de SSH) + ASG + el mismo ALB.
  - `modules/eks-cluster`: EKS (endpoint privado, Pod Identity / IRSA, Karpenter, add-ons gestionados). El despliegue de la app pasa a ArgoCD o Helm.
- En el entorno solo cambia qué módulo se llama.
