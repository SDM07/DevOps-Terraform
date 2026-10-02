#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Analiza un plan de Terraform (JSON) y bloquea cambios peligrosos.
#
#   uso: plan-guard.sh <plan.json> <entorno> [allow-destroy=true|false]
#
# Reglas:
#   * Cualquier delete o replace en prod falla salvo que el PR tenga la
#     etiqueta "allow-destroy" (decision humana explicita).
#   * Cambios sobre recursos criticos (red, IAM, KMS, ALB) se resaltan para
#     que el revisor los mire con lupa.
# Escribe un resumen en markdown en plan-summary.md.
# -----------------------------------------------------------------------------
set -euo pipefail

PLAN_JSON="$1"
ENVIRONMENT="$2"
ALLOW_DESTROY="${3:-false}"

count() {
  jq "[.resource_changes[]? | select(.change.actions | $1)] | length" "$PLAN_JSON"
}

ADD=$(count 'index("create") and (index("delete") | not)')
CHANGE=$(count '. == ["update"]')
REPLACE=$(count 'index("create") and index("delete")')
DESTROY=$(count '. == ["delete"]')

CRITICAL=$(jq -r '
  [.resource_changes[]?
   | select(.change.actions != ["no-op"] and .change.actions != ["read"])
   | select(.type | test("^aws_(vpc|subnet|route|nat_gateway|iam_|kms_|lb|security_group|vpc_security_group|ecs_cluster|secretsmanager)"))
   | "| `\(.address)` | \(.change.actions | join(", ")) |"]
  | .[]' "$PLAN_JSON")

{
  echo "### Terraform plan · \`${ENVIRONMENT}\`"
  echo
  echo "| Crear | Modificar | Reemplazar | Destruir |"
  echo "|---:|---:|---:|---:|"
  echo "| ${ADD} | ${CHANGE} | ${REPLACE} | ${DESTROY} |"
  echo
  if [[ -n "$CRITICAL" ]]; then
    echo "<details><summary>⚠️ Cambios en recursos críticos (revisar con detalle)</summary>"
    echo
    echo "| Recurso | Acción |"
    echo "|---|---|"
    echo "$CRITICAL"
    echo
    echo "</details>"
  fi
} > plan-summary.md

cat plan-summary.md

if [[ "$ENVIRONMENT" == "prod" && $((REPLACE + DESTROY)) -gt 0 && "$ALLOW_DESTROY" != "true" ]]; then
  echo "::error::El plan de prod destruye o reemplaza ${REPLACE}+${DESTROY} recursos. Agrega la etiqueta 'allow-destroy' al PR si es intencional."
  echo -e "\n❌ **Bloqueado:** destruye/reemplaza recursos en prod. Requiere la etiqueta \`allow-destroy\`." >> plan-summary.md
  exit 1
fi
