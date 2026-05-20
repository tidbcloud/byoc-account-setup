#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<USAGE
Usage: $0 --deploy-name <id> --subscription-id <id> --yes [--keep-enterprise-apps]

Revokes PingCAP multi-tenant application access while keeping customer-created
Azure resources. Use this when the customer wants to stop using TiDB Cloud BYOC
but keep the Azure resources for review or manual cleanup.

Revoked:
  - Deployment application temporary initial deployment access
  - Deployment application role assignments, including ACR-scoped Contributor
  - Dataplane management application role assignments
  - Dataplane management application membership in the AKS admin group
  - PingCAP enterprise applications/service principals, unless --keep-enterprise-apps is set

Kept:
  - setup-created resource groups and resources
  - setup-created customer-owned managed identities
  - setup-created customer-owned managed identity role assignments
  - onboarding state stack
USAGE
  exit "${1:-1}"
}

DEPLOY_NAME=""
SUBSCRIPTION_ID=""
YES=false
KEEP_ENTERPRISE_APPS=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --deploy-name) [[ $# -ge 2 ]] || usage; DEPLOY_NAME="$2"; shift 2 ;;
    --subscription-id) [[ $# -ge 2 ]] || usage; SUBSCRIPTION_ID="$2"; shift 2 ;;
    --yes) YES=true; shift ;;
    --keep-enterprise-apps) KEEP_ENTERPRISE_APPS=true; shift ;;
    -h|--help) usage 0 ;;
    *) echo "Error: unknown option '$1'"; usage ;;
  esac
done

[[ -n "$DEPLOY_NAME" && -n "$SUBSCRIPTION_ID" ]] || usage
command -v jq >/dev/null || { echo "Error: jq is required to read onboarding state."; exit 1; }
[[ "$YES" == "true" ]] || {
  cat <<MSG
Refusing to revoke without --yes.

This command removes PingCAP application access but keeps Azure resources.
MSG
  exit 1
}

az account set --subscription "$SUBSCRIPTION_ID"

stack_name() {
  printf 'cust-%s-tidbcloud-byoc-setup-%s\n' "$DEPLOY_NAME" "$1"
}

legacy_stack_name() {
  printf 'tidbcloud-byoc-setup-%s-%s\n' "$1" "$DEPLOY_NAME"
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

INITIAL_DEPLOY_ACCESS_STACK_NAME=$(jq -r --arg fallback "$(stack_name initial-deploy-access)" '.initialDeployAccessStackName // $fallback' <<<"$SETUP_STATE_JSON")
DEPLOYMENT_APP_ID=$(jq -r '.deploymentAppId // empty' <<<"$SETUP_STATE_JSON")
DATAPLANE_APP_ID=$(jq -r '.dataplaneAppId // empty' <<<"$SETUP_STATE_JSON")
ACR_RESOURCE_ID=$(jq -r '.acrResourceId // empty' <<<"$SETUP_STATE_JSON")
DNS_ZONE_SUBSCRIPTION_ID=$(jq -r '.dnsZoneSubscriptionId // empty' <<<"$SETUP_STATE_JSON")
DNS_ZONE_RESOURCE_GROUP=$(jq -r '.dnsZoneResourceGroupName // empty' <<<"$SETUP_STATE_JSON")
DNS_ZONE_NAME=$(jq -r '.dnsZoneName // empty' <<<"$SETUP_STATE_JSON")
AKS_ADMIN_GROUP_OBJECT_ID=$(jq -r '.aksAdminGroupObjectId // empty' <<<"$SETUP_STATE_JSON")

find_service_principal_object_id() {
  local app_id=$1
  [[ -n "$app_id" && "$app_id" != "null" ]] || return 0
  az ad sp show --id "$app_id" --query id -o tsv 2>/dev/null || true
}

delete_stack_if_exists() {
  local name=$1
  if az stack sub show --name "$name" >/dev/null 2>&1; then
    echo "Deleting temporary initial deployment access stack: $name"
    az stack sub delete --name "$name" --action-on-unmanage deleteAll --bypass-stack-out-of-sync-error true --yes --output none
  else
    echo "Temporary initial deployment access stack not found, skipping: $name"
  fi
}

delete_role_assignments_for_scope() {
  local subscription_id=$1 assignee_object_id=$2 scope=$3 label=$4
  [[ -n "$assignee_object_id" && "$assignee_object_id" != "null" ]] || return 0
  [[ -n "$scope" && "$scope" != "null" ]] || return 0

  az account set --subscription "$subscription_id"
  local ids
  ids=$(az role assignment list --assignee "$assignee_object_id" --scope "$scope" --query "[].id" -o tsv 2>/dev/null || true)
  if [[ -z "$ids" ]]; then
    echo "No role assignments found for $label at scope: $scope"
    return 0
  fi
  while IFS= read -r id; do
    [[ -n "$id" ]] || continue
    echo "Deleting role assignment for $label: $id"
    az role assignment delete --ids "$id"
  done <<<"$ids"
}

remove_group_member_if_exists() {
  local group_id=$1 member_id=$2
  [[ -n "$group_id" && "$group_id" != "null" ]] || return 0
  [[ -n "$member_id" && "$member_id" != "null" ]] || return 0
  if [[ "$(az ad group member check --group "$group_id" --member-id "$member_id" --query value -o tsv 2>/dev/null || true)" == "true" ]]; then
    echo "Removing dataplane application from AKS admin group: $group_id"
    az ad group member remove --group "$group_id" --member-id "$member_id"
  else
    echo "Dataplane application is not a member of AKS admin group, skipping."
  fi
}

delete_enterprise_app_if_exists() {
  local app_id=$1
  [[ -n "$app_id" && "$app_id" != "null" ]] || return 0
  if az ad sp show --id "$app_id" >/dev/null 2>&1; then
    echo "Deleting enterprise application/service principal for appId: $app_id"
    az ad sp delete --id "$app_id"
  else
    echo "Enterprise application/service principal not found, skipping appId: $app_id"
  fi
}

DEPLOYMENT_SP_OBJECT_ID=$(find_service_principal_object_id "$DEPLOYMENT_APP_ID")
DATAPLANE_SP_OBJECT_ID=$(find_service_principal_object_id "$DATAPLANE_APP_ID")
DNS_ZONE_SCOPE="/subscriptions/${DNS_ZONE_SUBSCRIPTION_ID}/resourceGroups/${DNS_ZONE_RESOURCE_GROUP}/providers/Microsoft.Network/dnsZones/${DNS_ZONE_NAME}"

cat <<PLAN
Revoking PingCAP application access for deployName: ${DEPLOY_NAME}

Deployment app:
  appId: ${DEPLOYMENT_APP_ID:-<none>}
  objectId: ${DEPLOYMENT_SP_OBJECT_ID:-<not found>}

Dataplane app:
  appId: ${DATAPLANE_APP_ID:-<none>}
  objectId: ${DATAPLANE_SP_OBJECT_ID:-<not found>}

Resources are kept. Enterprise applications deleted: $([[ "$KEEP_ENTERPRISE_APPS" == "true" ]] && echo "false" || echo "true")
PLAN

delete_stack_if_exists "$INITIAL_DEPLOY_ACCESS_STACK_NAME"

delete_role_assignments_for_scope "$SUBSCRIPTION_ID" "$DEPLOYMENT_SP_OBJECT_ID" "$ACR_RESOURCE_ID" "Deployment application ACR access"
delete_role_assignments_for_scope "$SUBSCRIPTION_ID" "$DATAPLANE_SP_OBJECT_ID" "/subscriptions/${SUBSCRIPTION_ID}" "Dataplane management application subscription access"
delete_role_assignments_for_scope "$DNS_ZONE_SUBSCRIPTION_ID" "$DATAPLANE_SP_OBJECT_ID" "$DNS_ZONE_SCOPE" "Dataplane management application DNS access"

az account set --subscription "$SUBSCRIPTION_ID"
remove_group_member_if_exists "$AKS_ADMIN_GROUP_OBJECT_ID" "$DATAPLANE_SP_OBJECT_ID"

if [[ "$KEEP_ENTERPRISE_APPS" != "true" ]]; then
  delete_enterprise_app_if_exists "$DEPLOYMENT_APP_ID"
  delete_enterprise_app_if_exists "$DATAPLANE_APP_ID"
else
  echo "Keeping PingCAP enterprise applications because --keep-enterprise-apps was set."
fi

echo "PingCAP application access revoked. Customer Azure resources were kept."
