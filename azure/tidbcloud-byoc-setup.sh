#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

usage() {
  cat <<USAGE
Usage: $0 [OPTIONS]

Required:
  --customer-id <id>
  --location <azure-region>
  --tenant-id <tenant-id>
  --subscription-id <subscription-id>
  --dns-zone-subscription-id <subscription-id>
  --dns-zone-resource-group <resource-group>
  --dns-zone-root-domain <dns-zone-name>
  --deployment-app-id <client-id>
  --dataplane-app-id <client-id>

Optional:
  --acr-resource-group <name>             Default: rg-tidbcloud-<customer-id>-acr
  --acr-name <name>                       Default: deterministic tidbcloud<customer-id>acr name
  -h, --help                              Show this help message
USAGE
  exit "${1:-1}"
}

require_arg() { [[ $# -ge 2 && "${2-}" != -* ]] || { echo "Error: $1 requires a value"; usage; }; }

CUSTOMER_ID=""; LOCATION=""; TENANT_ID=""; SUBSCRIPTION_ID=""; DNS_ZONE_SUBSCRIPTION_ID=""; DNS_ZONE_RESOURCE_GROUP=""; DNS_ZONE_ROOT_DOMAIN=""; DEPLOYMENT_APP_ID=""; DATAPLANE_APP_ID=""
ACR_RESOURCE_GROUP=""; ACR_NAME=""; AUDIT_LOG_CONTAINER_NAME="audit-log"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --customer-id) require_arg "$@"; CUSTOMER_ID="$2"; shift 2 ;;
    --location) require_arg "$@"; LOCATION="$2"; shift 2 ;;
    --tenant-id) require_arg "$@"; TENANT_ID="$2"; shift 2 ;;
    --subscription-id) require_arg "$@"; SUBSCRIPTION_ID="$2"; shift 2 ;;
    --dns-zone-subscription-id) require_arg "$@"; DNS_ZONE_SUBSCRIPTION_ID="$2"; shift 2 ;;
    --dns-zone-resource-group) require_arg "$@"; DNS_ZONE_RESOURCE_GROUP="$2"; shift 2 ;;
    --dns-zone-root-domain) require_arg "$@"; DNS_ZONE_ROOT_DOMAIN="$2"; shift 2 ;;
    --deployment-app-id) require_arg "$@"; DEPLOYMENT_APP_ID="$2"; shift 2 ;;
    --dataplane-app-id) require_arg "$@"; DATAPLANE_APP_ID="$2"; shift 2 ;;
    --acr-resource-group) require_arg "$@"; ACR_RESOURCE_GROUP="$2"; shift 2 ;;
    --acr-name) require_arg "$@"; ACR_NAME="$2"; shift 2 ;;
    -h|--help) usage 0 ;;
    *) echo "Error: unknown option '$1'"; usage ;;
  esac
done

missing=()
for pair in CUSTOMER_ID:--customer-id LOCATION:--location TENANT_ID:--tenant-id SUBSCRIPTION_ID:--subscription-id DNS_ZONE_SUBSCRIPTION_ID:--dns-zone-subscription-id DNS_ZONE_RESOURCE_GROUP:--dns-zone-resource-group DNS_ZONE_ROOT_DOMAIN:--dns-zone-root-domain DEPLOYMENT_APP_ID:--deployment-app-id DATAPLANE_APP_ID:--dataplane-app-id; do
  var=${pair%%:*}; flag=${pair#*:}; [[ -n "${!var}" ]] || missing+=("$flag")
done
[[ ${#missing[@]} -eq 0 ]] || { echo "Error: missing required parameters: ${missing[*]}"; usage; }
compact=$(echo "$CUSTOMER_ID" | tr -cd '[:alnum:]' | tr '[:upper:]' '[:lower:]')
[[ -n "$compact" ]] || { echo "Error: --customer-id must contain at least one letter or digit"; exit 1; }
if ((${#compact} > 12)); then
  audit_storage_customer_part=${compact: -12}
else
  audit_storage_customer_part=$compact
fi
DEPLOYMENT_RESOURCE_GROUP=rg-tidbcloud-${CUSTOMER_ID}-deploy
ACR_RESOURCE_GROUP=${ACR_RESOURCE_GROUP:-rg-tidbcloud-${CUSTOMER_ID}-acr}
STORAGE_RESOURCE_GROUP=rg-tidbcloud-${CUSTOMER_ID}-storage
IDENTITIES_RESOURCE_GROUP=rg-tidbcloud-${CUSTOMER_ID}-identities
O11Y_RESOURCE_GROUP=rg-tidbcloud-${CUSTOMER_ID}-o11y
ACR_NAME=${ACR_NAME:-tidbcloud${compact}acr}
AUDIT_LOG_STORAGE_ACCOUNT_NAME=st${audit_storage_customer_part}auditlog
AKS_ADMIN_GROUP_NAME=tidbcloud-${CUSTOMER_ID}-aks-admins
AKS_CONTROL_PLANE_IDENTITY_NAME=tidbcloud-${CUSTOMER_ID}-aks-control-plane
AKS_KUBELET_IDENTITY_NAME=tidbcloud-${CUSTOMER_ID}-aks-kubelet
DEPLOY_STACK_NAME=cust-${CUSTOMER_ID}-tidbcloud-byoc-setup-deploy
INITIAL_DEPLOY_ACCESS_STACK_NAME=cust-${CUSTOMER_ID}-tidbcloud-byoc-setup-initial-deploy-access
DATAPLANE_STACK_NAME=cust-${CUSTOMER_ID}-tidbcloud-byoc-setup-dataplane
O11Y_STACK_NAME=cust-${CUSTOMER_ID}-tidbcloud-byoc-setup-o11y
STATE_STACK_NAME=cust-${CUSTOMER_ID}-tidbcloud-byoc-setup-state

validate_max_length() {
  local label=$1 value=$2 max_length=$3
  if ((${#value} > max_length)); then
    echo "Error: ${label} '${value}' is ${#value} characters; Azure limit is ${max_length}. Shorten --customer-id." >&2
    exit 1
  fi
}

for stack_name in "$DEPLOY_STACK_NAME" "$INITIAL_DEPLOY_ACCESS_STACK_NAME" "$DATAPLANE_STACK_NAME" "$O11Y_STACK_NAME" "$STATE_STACK_NAME"; do
  validate_max_length "deployment stack name" "$stack_name" 90
done

az account set --subscription "$SUBSCRIPTION_ID"
current_tenant=$(az account show --query tenantId -o tsv)
[[ "$current_tenant" == "$TENANT_ID" ]] || { echo "Error: current Azure CLI tenant '$current_tenant' does not match --tenant-id '$TENANT_ID'"; exit 1; }

ensure_service_principal() {
  local app_id=$1
  local object_id
  object_id=$(az ad sp show --id "$app_id" --query id -o tsv 2>/dev/null || true)
  if [[ -z "$object_id" || "$object_id" == "null" ]]; then
    object_id=$(az ad sp list --filter "appId eq '$app_id'" --query "[0].id" -o tsv 2>/dev/null || true)
  fi
  if [[ -z "$object_id" || "$object_id" == "null" ]]; then
    object_id=$(az ad sp create --id "$app_id" --query id -o tsv 2>/tmp/tidbcloud-byoc-sp-create.err) || {
      object_id=$(az ad sp list --filter "appId eq '$app_id'" --query "[0].id" -o tsv 2>/dev/null || true)
      if [[ -z "$object_id" || "$object_id" == "null" ]]; then
        cat /tmp/tidbcloud-byoc-sp-create.err >&2
        return 1
      fi
    }
  fi
  printf '%s\n' "$object_id"
}

ensure_group() {
  local name=$1
  az ad group show --group "$name" --query id -o tsv 2>/dev/null || az ad group create --display-name "$name" --mail-nickname "$name" --query id -o tsv
}

ensure_group_member() {
  local group_id=$1 member_id=$2
  if [[ "$(az ad group member check --group "$group_id" --member-id "$member_id" --query value -o tsv)" != "true" ]]; then
    az ad group member add --group "$group_id" --member-id "$member_id"
  fi
}

echo "Ensuring enterprise applications and AKS admin group..."
DEPLOYMENT_SP_OBJECT_ID=$(ensure_service_principal "$DEPLOYMENT_APP_ID")
DATAPLANE_SP_OBJECT_ID=$(ensure_service_principal "$DATAPLANE_APP_ID")
AKS_ADMIN_GROUP_OBJECT_ID=$(ensure_group "$AKS_ADMIN_GROUP_NAME")
ensure_group_member "$AKS_ADMIN_GROUP_OBJECT_ID" "$DATAPLANE_SP_OBJECT_ID"

deploy_stack() {
  local name=$1 template=$2; shift 2
  az stack sub create \
    --name "$name" \
    --location "$LOCATION" \
    --template-file "$template" \
    --action-on-unmanage detachAll \
    --deny-settings-mode none \
    --output none \
    --parameters "$@"
}

deploy_stack_delete_unmanaged() {
  local name=$1 template=$2; shift 2
  az stack sub create \
    --name "$name" \
    --location "$LOCATION" \
    --template-file "$template" \
    --action-on-unmanage deleteAll \
    --deny-settings-mode none \
    --output none \
    --parameters "$@"
}

echo "Creating or updating deployment stack: deploy"
deploy_stack "$DEPLOY_STACK_NAME" "${SCRIPT_DIR}/tidbcloud-byoc-setup-deploy.bicep" \
  customerId="$CUSTOMER_ID" location="$LOCATION" deploymentPrincipalObjectId="$DEPLOYMENT_SP_OBJECT_ID" deploymentResourceGroupName="$DEPLOYMENT_RESOURCE_GROUP" acrResourceGroupName="$ACR_RESOURCE_GROUP" acrName="$ACR_NAME"

echo "Creating or updating deployment stack: initial deploy access"
deploy_stack_delete_unmanaged "$INITIAL_DEPLOY_ACCESS_STACK_NAME" "${SCRIPT_DIR}/tidbcloud-byoc-setup-initial-deploy-access.bicep" \
  deploymentPrincipalObjectId="$DEPLOYMENT_SP_OBJECT_ID"

ACR_RESOURCE_ID="/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${ACR_RESOURCE_GROUP}/providers/Microsoft.ContainerRegistry/registries/${ACR_NAME}"

echo "Creating or updating deployment stack: dataplane"
deploy_stack "$DATAPLANE_STACK_NAME" "${SCRIPT_DIR}/tidbcloud-byoc-setup-dataplane.bicep" \
  customerId="$CUSTOMER_ID" location="$LOCATION" dataplanePrincipalObjectId="$DATAPLANE_SP_OBJECT_ID" \
  dnsZoneSubscriptionId="$DNS_ZONE_SUBSCRIPTION_ID" dnsZoneResourceGroupName="$DNS_ZONE_RESOURCE_GROUP" dnsZoneName="$DNS_ZONE_ROOT_DOMAIN" \
  acrSubscriptionId="$SUBSCRIPTION_ID" acrResourceGroupName="$ACR_RESOURCE_GROUP" acrName="$ACR_NAME" \
  storageResourceGroupName="$STORAGE_RESOURCE_GROUP" identitiesResourceGroupName="$IDENTITIES_RESOURCE_GROUP" auditLogStorageAccountName="$AUDIT_LOG_STORAGE_ACCOUNT_NAME" auditLogContainerName="$AUDIT_LOG_CONTAINER_NAME" \
  aksControlPlaneIdentityName="$AKS_CONTROL_PLANE_IDENTITY_NAME" aksKubeletIdentityName="$AKS_KUBELET_IDENTITY_NAME"

echo "Creating or updating deployment stack: o11y"
deploy_stack "$O11Y_STACK_NAME" "${SCRIPT_DIR}/tidbcloud-byoc-setup-o11y.bicep" \
  customerId="$CUSTOMER_ID" location="$LOCATION" o11yResourceGroupName="$O11Y_RESOURCE_GROUP"

ACR_LOGIN_SERVER=$(az acr show --name "$ACR_NAME" --resource-group "$ACR_RESOURCE_GROUP" --query loginServer -o tsv)
echo "Creating or updating deployment stack: state"
deploy_stack_delete_unmanaged "$STATE_STACK_NAME" "${SCRIPT_DIR}/tidbcloud-byoc-setup-state.bicep" \
  customerId="$CUSTOMER_ID" location="$LOCATION" tenantId="$TENANT_ID" subscriptionId="$SUBSCRIPTION_ID" \
  dnsZoneSubscriptionId="$DNS_ZONE_SUBSCRIPTION_ID" dnsZoneResourceGroupName="$DNS_ZONE_RESOURCE_GROUP" dnsZoneName="$DNS_ZONE_ROOT_DOMAIN" \
  deploymentAppId="$DEPLOYMENT_APP_ID" dataplaneAppId="$DATAPLANE_APP_ID" \
  deploymentResourceGroupName="$DEPLOYMENT_RESOURCE_GROUP" acrResourceGroupName="$ACR_RESOURCE_GROUP" storageResourceGroupName="$STORAGE_RESOURCE_GROUP" identitiesResourceGroupName="$IDENTITIES_RESOURCE_GROUP" \
  o11yResourceGroupName="$O11Y_RESOURCE_GROUP" \
  deployStackName="$DEPLOY_STACK_NAME" initialDeployAccessStackName="$INITIAL_DEPLOY_ACCESS_STACK_NAME" dataplaneStackName="$DATAPLANE_STACK_NAME" o11yStackName="$O11Y_STACK_NAME" stateStackName="$STATE_STACK_NAME" \
  acrName="$ACR_NAME" acrResourceId="$ACR_RESOURCE_ID" acrLoginServer="$ACR_LOGIN_SERVER" \
  auditLogStorageAccountName="$AUDIT_LOG_STORAGE_ACCOUNT_NAME" auditLogContainerName="$AUDIT_LOG_CONTAINER_NAME" \
  aksAdminGroupName="$AKS_ADMIN_GROUP_NAME" aksAdminGroupObjectId="$AKS_ADMIN_GROUP_OBJECT_ID" \
  aksControlPlaneIdentityName="$AKS_CONTROL_PLANE_IDENTITY_NAME" aksKubeletIdentityName="$AKS_KUBELET_IDENTITY_NAME"

cat <<OUTPUT
Setup complete.

Share these values with PingCAP:
  customerId: ${CUSTOMER_ID}
  tenantId: ${TENANT_ID}
  subscriptionId: ${SUBSCRIPTION_ID}
  onboardingStateStack: ${STATE_STACK_NAME}

TiDB Cloud deployment application can read this onboarding state stack.
OUTPUT
