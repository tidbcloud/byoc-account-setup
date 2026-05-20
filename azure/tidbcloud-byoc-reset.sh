#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<USAGE
Usage: $0 --deploy-name <id> --subscription-id <id> --yes [--delete-acr] [--delete-enterprise-apps]

Deletes the Azure resources created by the BYOC setup scripts for a test reset.
This is intended for non-production retesting only.

Deleted:
  - setup-created Azure Deployment Stacks
  - setup-created resource groups and resources managed by those stacks, except ACR by default
  - setup-created role assignments and custom role definitions managed by those stacks
  - setup-created AKS admin Microsoft Entra group

Not deleted:
  - ACR resource group and ACR, unless --delete-acr is set
  - customer-prepared public DNS zone
  - PingCAP enterprise applications, unless --delete-enterprise-apps is set

Warning:
  - deleteAll removes setup-created resource groups. Any later resources placed
    inside those resource groups will also be deleted by Azure resource-group
    deletion. Destroy BYOC deployments first before using this reset script.
USAGE
  exit "${1:-1}"
}

DEPLOY_NAME=""
SUBSCRIPTION_ID=""
YES=false
DELETE_ACR=false
DELETE_ENTERPRISE_APPS=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --deploy-name) [[ $# -ge 2 ]] || usage; DEPLOY_NAME="$2"; shift 2 ;;
    --subscription-id) [[ $# -ge 2 ]] || usage; SUBSCRIPTION_ID="$2"; shift 2 ;;
    --yes) YES=true; shift ;;
    --delete-acr) DELETE_ACR=true; shift ;;
    --delete-enterprise-apps) DELETE_ENTERPRISE_APPS=true; shift ;;
    -h|--help) usage 0 ;;
    *) echo "Error: unknown option '$1'"; usage ;;
  esac
done

[[ -n "$DEPLOY_NAME" && -n "$SUBSCRIPTION_ID" ]] || usage
command -v jq >/dev/null || { echo "Error: jq is required to read onboarding state."; exit 1; }
[[ "$YES" == "true" ]] || {
  cat <<MSG
Refusing to delete without --yes.

This command is destructive and is intended only for test reset.
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

DEPLOY_STACK_NAME=$(jq -r --arg fallback "$(stack_name deploy)" '.deployStackName // $fallback' <<<"$SETUP_STATE_JSON")
INITIAL_DEPLOY_ACCESS_STACK_NAME=$(jq -r --arg fallback "$(stack_name initial-deploy-access)" '.initialDeployAccessStackName // $fallback' <<<"$SETUP_STATE_JSON")
DATAPLANE_STACK_NAME=$(jq -r --arg fallback "$(stack_name dataplane)" '.dataplaneStackName // $fallback' <<<"$SETUP_STATE_JSON")
O11Y_STACK_NAME=$(jq -r --arg fallback "$(stack_name o11y)" '.o11yStackName // $fallback' <<<"$SETUP_STATE_JSON")
DEPLOYMENT_RESOURCE_GROUP=$(jq -r '.deploymentResourceGroupName' <<<"$SETUP_STATE_JSON")
ACR_RESOURCE_GROUP=$(jq -r '.acrResourceGroupName' <<<"$SETUP_STATE_JSON")
ACR_RESOURCE_ID=$(jq -r '.acrResourceId' <<<"$SETUP_STATE_JSON")
AKS_ADMIN_GROUP_OBJECT_ID=$(jq -r '.aksAdminGroupObjectId // empty' <<<"$SETUP_STATE_JSON")
DEPLOYMENT_APP_ID=$(jq -r '.deploymentAppId // empty' <<<"$SETUP_STATE_JSON")
DATAPLANE_APP_ID=$(jq -r '.dataplaneAppId // empty' <<<"$SETUP_STATE_JSON")

delete_stack_if_exists() {
  local name=$1 action_on_unmanage=${2:-deleteAll}
  if az stack sub show --name "$name" >/dev/null 2>&1; then
    echo "Deleting deployment stack: $name (action-on-unmanage: $action_on_unmanage)"
    az stack sub delete --name "$name" --action-on-unmanage "$action_on_unmanage" --bypass-stack-out-of-sync-error true --yes --output none
  else
    echo "Deployment stack not found, skipping: $name"
  fi
}

delete_resource_group_if_exists() {
  local name=$1
  [[ -n "$name" && "$name" != "null" ]] || return 0
  if az group show --name "$name" >/dev/null 2>&1; then
    echo "Deleting resource group: $name"
    az group delete --name "$name" --yes --output none
  else
    echo "Resource group not found, skipping: $name"
  fi
}

find_service_principal_object_id() {
  local app_id=$1
  [[ -n "$app_id" && "$app_id" != "null" ]] || return 0
  az ad sp show --id "$app_id" --query id -o tsv 2>/dev/null || true
}

delete_role_assignments_for_scope() {
  local assignee_object_id=$1 scope=$2 label=$3
  [[ -n "$assignee_object_id" && "$assignee_object_id" != "null" ]] || return 0
  [[ -n "$scope" && "$scope" != "null" ]] || return 0

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

delete_group_if_exists() {
  local group_id=$1
  [[ -n "$group_id" && "$group_id" != "null" ]] || return 0
  if az ad group show --group "$group_id" >/dev/null 2>&1; then
    echo "Deleting Microsoft Entra group: $group_id"
    az ad group delete --group "$group_id"
  else
    echo "Microsoft Entra group not found, skipping: $group_id"
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

cat <<PLAN
Test reset will delete setup-managed resources for deployName: ${DEPLOY_NAME}

Deployment stacks:
  ${INITIAL_DEPLOY_ACCESS_STACK_NAME}
  ${DATAPLANE_STACK_NAME}
  ${O11Y_STACK_NAME}
  ${DEPLOY_STACK_NAME}
  ${STATE_STACK_NAME}

Microsoft Entra group:
  ${AKS_ADMIN_GROUP_OBJECT_ID:-<none>}

Enterprise applications:
  deleteAcr: ${DELETE_ACR}
  deleteEnterpriseApps: ${DELETE_ENTERPRISE_APPS}
  deploymentAppId: ${DEPLOYMENT_APP_ID:-<none>}
  dataplaneAppId: ${DATAPLANE_APP_ID:-<none>}
PLAN

DEPLOYMENT_SP_OBJECT_ID=$(find_service_principal_object_id "$DEPLOYMENT_APP_ID")

delete_stack_if_exists "$INITIAL_DEPLOY_ACCESS_STACK_NAME"
delete_stack_if_exists "$DATAPLANE_STACK_NAME"
delete_stack_if_exists "$O11Y_STACK_NAME"

if [[ "$DELETE_ACR" == "true" ]]; then
  delete_stack_if_exists "$DEPLOY_STACK_NAME" deleteAll
else
  delete_stack_if_exists "$DEPLOY_STACK_NAME" detachAll
  delete_role_assignments_for_scope "$DEPLOYMENT_SP_OBJECT_ID" "$ACR_RESOURCE_ID" "Deployment application ACR access"
  if [[ "$DEPLOYMENT_RESOURCE_GROUP" != "$ACR_RESOURCE_GROUP" ]]; then
    delete_resource_group_if_exists "$DEPLOYMENT_RESOURCE_GROUP"
  else
    echo "Deployment resource group is the ACR resource group; keeping it because --delete-acr was not set."
  fi
  echo "Keeping ACR resource group and ACR. Use --delete-acr to remove them during test reset."
fi

delete_stack_if_exists "$STATE_STACK_NAME"

delete_group_if_exists "$AKS_ADMIN_GROUP_OBJECT_ID"

if [[ "$DELETE_ENTERPRISE_APPS" == "true" ]]; then
  delete_enterprise_app_if_exists "$DEPLOYMENT_APP_ID"
  delete_enterprise_app_if_exists "$DATAPLANE_APP_ID"
else
  echo "Keeping PingCAP enterprise applications. Use --delete-enterprise-apps for a full test reset in an isolated test tenant."
fi

echo "Test reset complete for deployName: ${DEPLOY_NAME}"
