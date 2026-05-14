#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
usage() {
  cat <<USAGE
Usage: $0 --customer-id <id> --subscription-id <id> --stack <deploy|initial-deploy-access|dataplane|o11y|state|all>

Reads durable onboarding state from the customer subscription, then reruns one
or more Azure Deployment Stacks. Re-running a deployment stack updates managed
resources in place. Re-running setup or updating initial-deploy-access recreates
temporary initial deployment access if it has been revoked.
USAGE
  exit "${1:-1}"
}
CUSTOMER_ID=""; SUBSCRIPTION_ID=""; STACK=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --customer-id) [[ $# -ge 2 ]] || usage; CUSTOMER_ID="$2"; shift 2 ;;
    --subscription-id) [[ $# -ge 2 ]] || usage; SUBSCRIPTION_ID="$2"; shift 2 ;;
    --stack) [[ $# -ge 2 ]] || usage; STACK="$2"; shift 2 ;;
    -h|--help) usage 0 ;;
    *) echo "Error: unknown option '$1'"; usage ;;
  esac
done
[[ -n "$CUSTOMER_ID" && -n "$SUBSCRIPTION_ID" && -n "$STACK" ]] || usage
command -v jq >/dev/null || { echo "Error: jq is required to read onboarding state."; exit 1; }
az account set --subscription "$SUBSCRIPTION_ID"

stack_name() {
  printf 'cust-%s-tidbcloud-byoc-setup-%s\n' "$CUSTOMER_ID" "$1"
}

legacy_stack_name() {
  printf 'tidbcloud-byoc-setup-%s-%s\n' "$1" "$CUSTOMER_ID"
}

STATE_STACK_NAME=$(stack_name state)
STATE_DEPLOYMENT_ID=$(az stack sub show --name "$STATE_STACK_NAME" --query deploymentId -o tsv 2>/dev/null || true)
if [[ -z "$STATE_DEPLOYMENT_ID" || "$STATE_DEPLOYMENT_ID" == "null" ]]; then
  LEGACY_STATE_STACK_NAME=$(legacy_stack_name state)
  STATE_DEPLOYMENT_ID=$(az stack sub show --name "$LEGACY_STATE_STACK_NAME" --query deploymentId -o tsv 2>/dev/null || true)
  if [[ -n "$STATE_DEPLOYMENT_ID" && "$STATE_DEPLOYMENT_ID" != "null" ]]; then
    STATE_STACK_NAME="$LEGACY_STATE_STACK_NAME"
  fi
fi
[[ -n "$STATE_DEPLOYMENT_ID" && "$STATE_DEPLOYMENT_ID" != "null" ]] \
  || { echo "Error: onboarding state stack '$(stack_name state)' was not found in subscription '$SUBSCRIPTION_ID'."; exit 1; }
STATE_DEPLOYMENT_NAME=${STATE_DEPLOYMENT_ID##*/}
SETUP_STATE_JSON=$(az deployment sub show --name "$STATE_DEPLOYMENT_NAME" --query properties.outputs.setupState.value -o json)

DEPLOY_STACK_NAME=$(jq -r --arg fallback "$(stack_name deploy)" '.deployStackName // $fallback' <<<"$SETUP_STATE_JSON")
INITIAL_DEPLOY_ACCESS_STACK_NAME=$(jq -r --arg fallback "$(stack_name initial-deploy-access)" '.initialDeployAccessStackName // $fallback' <<<"$SETUP_STATE_JSON")
DATAPLANE_STACK_NAME=$(jq -r --arg fallback "$(stack_name dataplane)" '.dataplaneStackName // $fallback' <<<"$SETUP_STATE_JSON")
O11Y_STACK_NAME=$(jq -r --arg fallback "$(stack_name o11y)" '.o11yStackName // $fallback' <<<"$SETUP_STATE_JSON")

LOCATION=$(jq -r '.location' <<<"$SETUP_STATE_JSON")
TENANT_ID=$(jq -r '.tenantId' <<<"$SETUP_STATE_JSON")
DNS_ZONE_SUBSCRIPTION_ID=$(jq -r '.dnsZoneSubscriptionId' <<<"$SETUP_STATE_JSON")
DNS_ZONE_RESOURCE_GROUP=$(jq -r '.dnsZoneResourceGroupName' <<<"$SETUP_STATE_JSON")
DNS_ZONE_ROOT_DOMAIN=$(jq -r '.dnsZoneName' <<<"$SETUP_STATE_JSON")
DEPLOYMENT_APP_ID=$(jq -r '.deploymentAppId' <<<"$SETUP_STATE_JSON")
DATAPLANE_APP_ID=$(jq -r '.dataplaneAppId' <<<"$SETUP_STATE_JSON")
DEPLOYMENT_RESOURCE_GROUP=$(jq -r '.deploymentResourceGroupName' <<<"$SETUP_STATE_JSON")
ACR_RESOURCE_GROUP=$(jq -r '.acrResourceGroupName' <<<"$SETUP_STATE_JSON")
STORAGE_RESOURCE_GROUP=$(jq -r '.storageResourceGroupName' <<<"$SETUP_STATE_JSON")
IDENTITIES_RESOURCE_GROUP=$(jq -r '.identitiesResourceGroupName' <<<"$SETUP_STATE_JSON")
O11Y_RESOURCE_GROUP=$(jq -r '.o11yResourceGroupName' <<<"$SETUP_STATE_JSON")
ACR_NAME=$(jq -r '.acrName' <<<"$SETUP_STATE_JSON")
ACR_RESOURCE_ID=$(jq -r '.acrResourceId' <<<"$SETUP_STATE_JSON")
ACR_LOGIN_SERVER=$(jq -r '.acrLoginServer' <<<"$SETUP_STATE_JSON")
AUDIT_LOG_STORAGE_ACCOUNT_NAME=$(jq -r '.auditLogStorageAccountName' <<<"$SETUP_STATE_JSON")
AUDIT_LOG_CONTAINER_NAME=$(jq -r '.auditLogContainerName' <<<"$SETUP_STATE_JSON")
AKS_ADMIN_GROUP_NAME=$(jq -r '.aksAdminGroupName' <<<"$SETUP_STATE_JSON")
AKS_ADMIN_GROUP_OBJECT_ID=$(jq -r '.aksAdminGroupObjectId' <<<"$SETUP_STATE_JSON")
AKS_CONTROL_PLANE_IDENTITY_NAME=$(jq -r '.aksControlPlaneIdentityName' <<<"$SETUP_STATE_JSON")
AKS_KUBELET_IDENTITY_NAME=$(jq -r '.aksKubeletIdentityName' <<<"$SETUP_STATE_JSON")

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

ensure_group_member() {
  local group_id=$1 member_id=$2
  if [[ -z "$group_id" || "$group_id" == "null" ]]; then
    echo "Error: AKS admin group object ID is missing from onboarding state." >&2
    exit 1
  fi
  if [[ "$(az ad group member check --group "$group_id" --member-id "$member_id" --query value -o tsv)" != "true" ]]; then
    az ad group member add --group "$group_id" --member-id "$member_id"
  fi
}

deploy_stack() {
  local name=$1 template=$2; shift 2
  az stack sub create --name "$name" --location "$LOCATION" --template-file "$template" --action-on-unmanage detachAll --deny-settings-mode none --output none --parameters "$@"
}
deploy_stack_delete_unmanaged() {
  local name=$1 template=$2; shift 2
  az stack sub create --name "$name" --location "$LOCATION" --template-file "$template" --action-on-unmanage deleteAll --deny-settings-mode none --output none --parameters "$@"
}
update_deploy() {
  local deployment_sp_object_id
  deployment_sp_object_id=$(ensure_service_principal "$DEPLOYMENT_APP_ID")
  deploy_stack "$DEPLOY_STACK_NAME" "${SCRIPT_DIR}/tidbcloud-byoc-setup-deploy.bicep" \
    customerId="$CUSTOMER_ID" location="$LOCATION" deploymentPrincipalObjectId="$deployment_sp_object_id" deploymentResourceGroupName="$DEPLOYMENT_RESOURCE_GROUP" acrResourceGroupName="$ACR_RESOURCE_GROUP" acrName="$ACR_NAME"
}
update_initial_deploy_access() {
  local deployment_sp_object_id
  deployment_sp_object_id=$(ensure_service_principal "$DEPLOYMENT_APP_ID")
  deploy_stack_delete_unmanaged "$INITIAL_DEPLOY_ACCESS_STACK_NAME" "${SCRIPT_DIR}/tidbcloud-byoc-setup-initial-deploy-access.bicep" \
    deploymentPrincipalObjectId="$deployment_sp_object_id"
}
update_dataplane() {
  local dataplane_sp_object_id
  dataplane_sp_object_id=$(ensure_service_principal "$DATAPLANE_APP_ID")
  ensure_group_member "$AKS_ADMIN_GROUP_OBJECT_ID" "$dataplane_sp_object_id"
  deploy_stack "$DATAPLANE_STACK_NAME" "${SCRIPT_DIR}/tidbcloud-byoc-setup-dataplane.bicep" \
    customerId="$CUSTOMER_ID" location="$LOCATION" dataplanePrincipalObjectId="$dataplane_sp_object_id" \
    dnsZoneSubscriptionId="$DNS_ZONE_SUBSCRIPTION_ID" dnsZoneResourceGroupName="$DNS_ZONE_RESOURCE_GROUP" dnsZoneName="$DNS_ZONE_ROOT_DOMAIN" \
    acrSubscriptionId="$SUBSCRIPTION_ID" acrResourceGroupName="$ACR_RESOURCE_GROUP" acrName="$ACR_NAME" \
    storageResourceGroupName="$STORAGE_RESOURCE_GROUP" identitiesResourceGroupName="$IDENTITIES_RESOURCE_GROUP" auditLogStorageAccountName="$AUDIT_LOG_STORAGE_ACCOUNT_NAME" auditLogContainerName="$AUDIT_LOG_CONTAINER_NAME" \
    aksControlPlaneIdentityName="$AKS_CONTROL_PLANE_IDENTITY_NAME" aksKubeletIdentityName="$AKS_KUBELET_IDENTITY_NAME"
}
update_o11y() {
  deploy_stack "$O11Y_STACK_NAME" "${SCRIPT_DIR}/tidbcloud-byoc-setup-o11y.bicep" \
    customerId="$CUSTOMER_ID" location="$LOCATION" o11yResourceGroupName="$O11Y_RESOURCE_GROUP"
}
update_state() {
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
}
case "$STACK" in
  deploy) update_deploy ;;
  initial-deploy-access) update_initial_deploy_access ;;
  dataplane) update_dataplane ;;
  o11y) update_o11y ;;
  state) update_state ;;
  all) update_deploy; update_dataplane; update_o11y; update_state ;;
  *) echo "Error: unknown stack '$STACK'. Must be one of: deploy, initial-deploy-access, dataplane, o11y, state, all"; exit 1 ;;
esac
