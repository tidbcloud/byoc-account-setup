#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<USAGE
Usage: $0 --customer-id <id> --subscription-id <id> --yes

Revokes the temporary TiDB Cloud initial deployment access by deleting the
customer-specific Azure Deployment Stack that owns:
  - the temporary subscription-scope Contributor role assignment to the
    Deployment application

This does not delete the BYOC deployment resource group, ACR, dataplane
resources, O11Y resources, or onboarding state stack.
USAGE
  exit "${1:-1}"
}

CUSTOMER_ID=""
SUBSCRIPTION_ID=""
YES=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --customer-id) [[ $# -ge 2 ]] || usage; CUSTOMER_ID="$2"; shift 2 ;;
    --subscription-id) [[ $# -ge 2 ]] || usage; SUBSCRIPTION_ID="$2"; shift 2 ;;
    --yes) YES=true; shift ;;
    -h|--help) usage 0 ;;
    *) echo "Error: unknown option '$1'"; usage ;;
  esac
done

[[ -n "$CUSTOMER_ID" && -n "$SUBSCRIPTION_ID" ]] || usage
[[ "$YES" == "true" ]] || {
  cat <<MSG
Refusing to delete without --yes.

This command will delete only the temporary initial deploy access stack:
  cust-${CUSTOMER_ID}-tidbcloud-byoc-setup-initial-deploy-access

Re-run with --yes after the first BYOC deployment completes.
MSG
  exit 1
}

INITIAL_DEPLOY_ACCESS_STACK_NAME=cust-${CUSTOMER_ID}-tidbcloud-byoc-setup-initial-deploy-access
LEGACY_INITIAL_DEPLOY_ACCESS_STACK_NAME=tidbcloud-byoc-setup-initial-deploy-access-${CUSTOMER_ID}

az account set --subscription "$SUBSCRIPTION_ID"

if ! az stack sub show --name "$INITIAL_DEPLOY_ACCESS_STACK_NAME" >/dev/null 2>&1; then
  if az stack sub show --name "$LEGACY_INITIAL_DEPLOY_ACCESS_STACK_NAME" >/dev/null 2>&1; then
    INITIAL_DEPLOY_ACCESS_STACK_NAME="$LEGACY_INITIAL_DEPLOY_ACCESS_STACK_NAME"
  else
    echo "Initial deploy access stack '$INITIAL_DEPLOY_ACCESS_STACK_NAME' was not found. Access is already revoked or was never created."
    exit 0
  fi
fi

az stack sub delete \
  --name "$INITIAL_DEPLOY_ACCESS_STACK_NAME" \
  --action-on-unmanage deleteAll \
  --bypass-stack-out-of-sync-error true \
  --yes

echo "Revoked temporary initial deployment access: ${INITIAL_DEPLOY_ACCESS_STACK_NAME}"
