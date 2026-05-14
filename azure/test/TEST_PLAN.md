# TiDB Cloud BYOC Azure Setup Test Plan

This plan validates the Azure BYOC setup scripts, Bicep templates, onboarding
state, lifecycle scripts, and cleanup behavior.

Use an isolated Azure test tenant and subscription for destructive phases.
Do not run reset tests against production or shared customer environments.

## 0. Test Inputs

Create a local environment file for the test run:

```bash
cat > /tmp/tidbcloud-byoc-azure-test.env <<'EOF'
export CUSTOMER_ID="test-customer-001"
export LOCATION="eastus"
export TENANT_ID="<tenant-id>"
export SUBSCRIPTION_ID="<byoc-subscription-id>"
export DNS_ZONE_SUBSCRIPTION_ID="<dns-zone-subscription-id>"
export DNS_ZONE_RESOURCE_GROUP="<dns-zone-resource-group>"
export DNS_ZONE_ROOT_DOMAIN="<dns-zone-root-domain>"
export DEPLOYMENT_APP_ID="<deployment-app-client-id>"
export DATAPLANE_APP_ID="<dataplane-app-client-id>"

export AZURE_DIR="/Volumes/T9/tidbcloud/byoc-account-setup/azure"
EOF

source /tmp/tidbcloud-byoc-azure-test.env
cd "$AZURE_DIR"
```

Required Azure prerequisites:

- Azure CLI is logged in to the expected tenant.
- Azure CLI supports Deployment Stacks.
- `jq`, `shellcheck`, and Azure Bicep CLI are available.
- The public DNS zone exists before setup starts.
- The test operator has the roles documented in `README.md`.

## 1. Local Script And Template Validation

### 1.1 Help And Usage

```bash
set -euo pipefail
cd "$AZURE_DIR"

for script in \
  tidbcloud-byoc-setup.sh \
  tidbcloud-byoc-update.sh \
  tidbcloud-byoc-revoke-initial-deploy-access.sh \
  tidbcloud-byoc-revoke-app-access.sh \
  tidbcloud-byoc-reset.sh
do
  bash "$script" --help >/tmp/"$script".help
  test -s /tmp/"$script".help
done
```

Pass criteria:

- Every script exits successfully with `--help`.
- Help output lists the flags used by the README examples.

### 1.2 Required Argument Validation

```bash
set -euo pipefail
cd "$AZURE_DIR"

expect_fail() {
  if "$@" >/tmp/byoc-negative.out 2>/tmp/byoc-negative.err; then
    echo "Expected failure but command succeeded: $*" >&2
    exit 1
  fi
}

expect_fail bash tidbcloud-byoc-setup.sh
expect_fail bash tidbcloud-byoc-setup.sh --customer-id "$CUSTOMER_ID"
expect_fail bash tidbcloud-byoc-setup.sh --customer-id --location "$LOCATION"
expect_fail bash tidbcloud-byoc-setup.sh --unknown

expect_fail bash tidbcloud-byoc-update.sh
expect_fail bash tidbcloud-byoc-update.sh --customer-id "$CUSTOMER_ID" --subscription-id "$SUBSCRIPTION_ID" --stack bad

expect_fail bash tidbcloud-byoc-revoke-initial-deploy-access.sh --customer-id "$CUSTOMER_ID" --subscription-id "$SUBSCRIPTION_ID"
expect_fail bash tidbcloud-byoc-revoke-app-access.sh --customer-id "$CUSTOMER_ID" --subscription-id "$SUBSCRIPTION_ID"
expect_fail bash tidbcloud-byoc-reset.sh --customer-id "$CUSTOMER_ID" --subscription-id "$SUBSCRIPTION_ID"
```

Pass criteria:

- Invalid invocations fail before making Azure changes.
- Destructive scripts refuse to run without `--yes`.

### 1.3 Shell And Bicep Validation

```bash
set -euo pipefail
cd "$AZURE_DIR"

shellcheck ./*.sh

BUILD_DIR=/tmp/tidbcloud-byoc-bicep-build
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

for file in ./*.bicep ./modules/*.bicep; do
  output_name=${file#./}
  output_name=${output_name//\//_}
  az bicep build --file "$file" --outfile "$BUILD_DIR/${output_name%.bicep}.json" >/dev/null
done
```

Pass criteria:

- ShellCheck has no blocking findings.
- Every Bicep file compiles.
- No generated JSON files are written into the source tree.

## 2. First Setup

### 2.1 Run Setup

```bash
set -euo pipefail
source /tmp/tidbcloud-byoc-azure-test.env
cd "$AZURE_DIR"

bash tidbcloud-byoc-setup.sh \
  --customer-id "$CUSTOMER_ID" \
  --location "$LOCATION" \
  --tenant-id "$TENANT_ID" \
  --subscription-id "$SUBSCRIPTION_ID" \
  --dns-zone-subscription-id "$DNS_ZONE_SUBSCRIPTION_ID" \
  --dns-zone-resource-group "$DNS_ZONE_RESOURCE_GROUP" \
  --dns-zone-root-domain "$DNS_ZONE_ROOT_DOMAIN" \
  --deployment-app-id "$DEPLOYMENT_APP_ID" \
  --dataplane-app-id "$DATAPLANE_APP_ID" \
  | tee /tmp/tidbcloud-byoc-setup.out
```

Pass criteria:

- Script exits successfully.
- Output includes "Setup complete."
- Output includes `customerId`, `tenantId`, `subscriptionId`, and
  `onboardingStateStack` handoff values.

### 2.2 Capture State Outputs

```bash
set -euo pipefail
source /tmp/tidbcloud-byoc-azure-test.env

az account set --subscription "$SUBSCRIPTION_ID"

STATE_STACK_NAME="cust-${CUSTOMER_ID}-tidbcloud-byoc-setup-state"
STATE_DEPLOYMENT_ID=$(az stack sub show --name "$STATE_STACK_NAME" --query deploymentId -o tsv)
STATE_DEPLOYMENT_NAME=${STATE_DEPLOYMENT_ID##*/}

az deployment sub show \
  --name "$STATE_DEPLOYMENT_NAME" \
  --query properties.outputs.setupState.value \
  -o json | tee /tmp/tidbcloud-byoc-setup-state.json | jq .

az deployment sub show \
  --name "$STATE_DEPLOYMENT_NAME" \
  --query properties.outputs.customerOnboarding.value \
  -o json | tee /tmp/tidbcloud-byoc-customer-onboarding.json | jq .

jq -e \
  --arg dataplane_app_id "$(jq -r '.dataplaneAppId' /tmp/tidbcloud-byoc-setup-state.json)" \
  '.schema_version != null
    and .dataplane_app_id == $dataplane_app_id
    and (.customer_acr_resource_id | length > 0)
    and (.customer_acr_login_server | length > 0)
    and (.audit_log_storage_account_name | length > 0)
    and (.audit_log_bucket | length > 0)
    and (.aks_control_plane_identity_name | length > 0)
    and (.aks_kubelet_identity_name | length > 0)
    and (.tidb_cluster_dns_domain | length > 0)
    and (.tidb_cluster_dns_resource_group | length > 0)
    and (.o11y_resource_group_name | length > 0)
    and (has("multi_tenant_app_client_id") | not)' \
  /tmp/tidbcloud-byoc-customer-onboarding.json >/dev/null
```

Pass criteria:

- Both JSON documents parse with `jq`.
- `setupState.customerId`, `tenantId`, `subscriptionId`, and DNS fields match
  the expected setup contract.
- `customerOnboarding` contains ACR, audit log, AKS identity, DNS, and O11Y
  fields needed by auto-deploy.
- `customerOnboarding.schema_version` is present.
- `customerOnboarding.dataplane_app_id` matches `setupState.dataplaneAppId`.
- `customerOnboarding.multi_tenant_app_client_id` is absent.

## 3. Resource Verification

```bash
set -euo pipefail
source /tmp/tidbcloud-byoc-azure-test.env

az account set --subscription "$SUBSCRIPTION_ID"
STATE=/tmp/tidbcloud-byoc-setup-state.json

DEPLOY_STACK=$(jq -r '.deployStackName' "$STATE")
INITIAL_STACK=$(jq -r '.initialDeployAccessStackName' "$STATE")
DATAPLANE_STACK=$(jq -r '.dataplaneStackName' "$STATE")
O11Y_STACK=$(jq -r '.o11yStackName' "$STATE")
STATE_STACK=$(jq -r '.stateStackName' "$STATE")

for stack in "$DEPLOY_STACK" "$INITIAL_STACK" "$DATAPLANE_STACK" "$O11Y_STACK" "$STATE_STACK"; do
  az stack sub show --name "$stack" --query "{name:name,provisioningState:provisioningState}" -o table
done

ACR_RESOURCE_GROUP=$(jq -r '.acrResourceGroupName' "$STATE")
ACR_NAME=$(jq -r '.acrName' "$STATE")
STORAGE_RESOURCE_GROUP=$(jq -r '.storageResourceGroupName' "$STATE")
AUDIT_STORAGE=$(jq -r '.auditLogStorageAccountName' "$STATE")
AUDIT_CONTAINER=$(jq -r '.auditLogContainerName' "$STATE")
IDENTITIES_RESOURCE_GROUP=$(jq -r '.identitiesResourceGroupName' "$STATE")
O11Y_RESOURCE_GROUP=$(jq -r '.o11yResourceGroupName' "$STATE")

az acr show \
  --resource-group "$ACR_RESOURCE_GROUP" \
  --name "$ACR_NAME" \
  --query "{name:name,adminUserEnabled:adminUserEnabled,publicNetworkAccess:publicNetworkAccess,loginServer:loginServer}" \
  -o json | jq .

az storage account show \
  --resource-group "$STORAGE_RESOURCE_GROUP" \
  --name "$AUDIT_STORAGE" \
  --query "{name:name,allowBlobPublicAccess:allowBlobPublicAccess,minimumTlsVersion:minimumTlsVersion}" \
  -o json | jq .

for attempt in 1 2 3 4 5 6 7 8 9 10 11 12; do
  if az storage container show \
    --account-name "$AUDIT_STORAGE" \
    --name "$AUDIT_CONTAINER" \
    --auth-mode login \
    --query "{name:name,publicAccess:properties.publicAccess}" \
    -o json | jq .; then
    break
  fi
  if [[ "$attempt" = "12" ]]; then
    echo "Audit log storage container was not readable after retries" >&2
    exit 1
  fi
  sleep 10
done

for identity in \
  "$(jq -r '.aksControlPlaneIdentityName' "$STATE")" \
  "$(jq -r '.aksKubeletIdentityName' "$STATE")"
do
  az identity show --resource-group "$IDENTITIES_RESOURCE_GROUP" --name "$identity" --query "{name:name,principalId:principalId}" -o table
done

for identity in o11y-regional-server o11y-vmbackup o11y-loki o11y-velero; do
  az identity show --resource-group "$O11Y_RESOURCE_GROUP" --name "$identity" --query "{name:name,principalId:principalId}" -o table
done
```

Pass criteria:

- All five stacks exist and are provisioned.
- ACR exists with admin user disabled.
- Audit storage exists with private container and TLS 1.2 or newer.
- AKS and O11Y managed identities exist.

## 4. RBAC Verification

```bash
set -euo pipefail
source /tmp/tidbcloud-byoc-azure-test.env

STATE=/tmp/tidbcloud-byoc-setup-state.json
az account set --subscription "$SUBSCRIPTION_ID"

DEPLOYMENT_SP_OBJECT_ID=$(az ad sp show --id "$DEPLOYMENT_APP_ID" --query id -o tsv)
DATAPLANE_SP_OBJECT_ID=$(az ad sp show --id "$DATAPLANE_APP_ID" --query id -o tsv)
ACR_RESOURCE_ID=$(jq -r '.acrResourceId' "$STATE")
AKS_ADMIN_GROUP_OBJECT_ID=$(jq -r '.aksAdminGroupObjectId' "$STATE")
DNS_RESOURCE_GROUP_SCOPE="/subscriptions/${DNS_ZONE_SUBSCRIPTION_ID}/resourceGroups/${DNS_ZONE_RESOURCE_GROUP}"
DNS_SCOPE="${DNS_RESOURCE_GROUP_SCOPE}/providers/Microsoft.Network/dnsZones/${DNS_ZONE_ROOT_DOMAIN}"
INITIAL_DEPLOY_ROLE="Contributor"
DATAPLANE_ROLE="TiDB BYOC Dataplane Operator - ${CUSTOMER_ID}"
DATAPLANE_DNS_ROLE="TiDB BYOC Dataplane DNS Record Operator - ${CUSTOMER_ID}"
DATAPLANE_BLOB_LIST_ONLY_CONDITION="!(ActionMatches{'Microsoft.Storage/storageAccounts/blobServices/containers/blobs/read'} AND NOT SubOperationMatches{'Blob.List'})"

az role assignment list --assignee "$DEPLOYMENT_SP_OBJECT_ID" --scope "/subscriptions/${SUBSCRIPTION_ID}" -o table
az role assignment list --assignee "$DEPLOYMENT_SP_OBJECT_ID" --scope "/subscriptions/${SUBSCRIPTION_ID}" -o json \
  | jq --arg role "$INITIAL_DEPLOY_ROLE" --arg scope "/subscriptions/${SUBSCRIPTION_ID}" '[.[] | select(.roleDefinitionName == $role and .scope == $scope)][0]' \
  | tee /tmp/tidbcloud-byoc-initial-contributor-assignment.json | jq .
az role assignment list --assignee "$DEPLOYMENT_SP_OBJECT_ID" --scope "$ACR_RESOURCE_ID" -o table
az role assignment list --assignee "$DEPLOYMENT_SP_OBJECT_ID" --scope "$ACR_RESOURCE_ID" -o json \
  | jq --arg role "$INITIAL_DEPLOY_ROLE" --arg scope "$ACR_RESOURCE_ID" '[.[] | select(.roleDefinitionName == $role and .scope == $scope)][0]' \
  | tee /tmp/tidbcloud-byoc-acr-contributor-assignment.json | jq .
az role assignment list --assignee "$DATAPLANE_SP_OBJECT_ID" --scope "/subscriptions/${SUBSCRIPTION_ID}" -o table
az role assignment list --assignee "$DATAPLANE_SP_OBJECT_ID" --scope "/subscriptions/${SUBSCRIPTION_ID}" -o json \
  | jq --arg role "$DATAPLANE_ROLE" '[.[] | select(.roleDefinitionName == $role)][0]' \
  | tee /tmp/tidbcloud-byoc-dataplane-role-assignment.json | jq .

az account set --subscription "$DNS_ZONE_SUBSCRIPTION_ID"
az role assignment list --assignee "$DATAPLANE_SP_OBJECT_ID" --scope "$DNS_SCOPE" -o table
az role assignment list --assignee "$DATAPLANE_SP_OBJECT_ID" --scope "$DNS_SCOPE" -o json \
  | jq --arg role "$DATAPLANE_DNS_ROLE" '[.[] | select(.roleDefinitionName == $role)][0]' \
  | tee /tmp/tidbcloud-byoc-dataplane-dns-role-assignment.json | jq .

az role definition list --name "$DATAPLANE_DNS_ROLE" --scope "$DNS_RESOURCE_GROUP_SCOPE" -o json \
  | jq '.[0]' | tee /tmp/tidbcloud-byoc-dataplane-dns-role.json \
  | jq '.permissions[0]' | tee /tmp/tidbcloud-byoc-dataplane-dns-role-perms.json | jq .

az account set --subscription "$SUBSCRIPTION_ID"
az ad group member check \
  --group "$AKS_ADMIN_GROUP_OBJECT_ID" \
  --member-id "$DATAPLANE_SP_OBJECT_ID" \
  --query value -o tsv

az role definition list \
  --name "$DATAPLANE_ROLE" \
  --query "[0].permissions[0]" -o json | tee /tmp/tidbcloud-byoc-dataplane-role-perms.json | jq .

for file in /tmp/tidbcloud-byoc-dataplane-role-perms.json /tmp/tidbcloud-byoc-dataplane-dns-role-perms.json; do
  jq -e '
    def has_not_action($action): (.notActions // []) | index($action) != null;
    ((.actions // []) | index("Microsoft.Authorization/roleAssignments/write") == null)
    and ((.actions // []) | index("Microsoft.Authorization/roleAssignments/delete") == null)
    and (
      ((.actions // []) | index("Microsoft.Authorization/*") == null)
      or (
        has_not_action("Microsoft.Authorization/roleAssignments/write")
        and has_not_action("Microsoft.Authorization/roleAssignments/delete")
      )
    )
  ' "$file" >/dev/null
done

jq -e --arg role "$INITIAL_DEPLOY_ROLE" --arg scope "/subscriptions/${SUBSCRIPTION_ID}" '
  .roleDefinitionName == $role
  and .scope == $scope
' /tmp/tidbcloud-byoc-initial-contributor-assignment.json >/dev/null

jq -e --arg role "$INITIAL_DEPLOY_ROLE" --arg scope "$ACR_RESOURCE_ID" '
  .roleDefinitionName == $role
  and .scope == $scope
' /tmp/tidbcloud-byoc-acr-contributor-assignment.json >/dev/null

jq -e '
  def has_action($action): (.actions // []) | index($action) != null;
  def lacks_action($action): (.actions // []) | index($action) == null;
  def has_data_action($action): (.dataActions // []) | index($action) != null;
  has_action("Microsoft.Storage/storageAccounts/read")
  and has_action("Microsoft.Storage/storageAccounts/write")
  and has_action("Microsoft.Storage/storageAccounts/delete")
  and has_action("Microsoft.Storage/storageAccounts/blobServices/read")
  and has_action("Microsoft.Storage/storageAccounts/blobServices/containers/read")
  and has_action("Microsoft.Storage/storageAccounts/blobServices/containers/write")
  and has_action("Microsoft.Storage/storageAccounts/blobServices/containers/delete")
  and has_action("Microsoft.Storage/storageAccounts/managementPolicies/read")
  and has_action("Microsoft.Storage/storageAccounts/managementPolicies/write")
  and has_action("Microsoft.Storage/storageAccounts/managementPolicies/delete")
  and lacks_action("Microsoft.Storage/storageAccounts/*")
  and lacks_action("Microsoft.Storage/storageAccounts/blobServices/containers/*")
  and has_data_action("Microsoft.Storage/storageAccounts/blobServices/containers/blobs/read")
  and ((.notDataActions // []) | length == 0)
  and lacks_action("Microsoft.Network/dnsZones/*")
  and lacks_action("Microsoft.Network/dnsZones/read")
  and lacks_action("Microsoft.Network/dnsZones/A/read")
  and lacks_action("Microsoft.Network/dnsZones/A/write")
  and lacks_action("Microsoft.Network/dnsZones/A/delete")
  and lacks_action("Microsoft.Authorization/*/read")
  and lacks_action("Microsoft.Insights/alertRules/*")
  and lacks_action("Microsoft.ResourceHealth/availabilityStatuses/read")
  and lacks_action("Microsoft.Resources/deployments/*")
  and lacks_action("Microsoft.Support/*")
' /tmp/tidbcloud-byoc-dataplane-role-perms.json >/dev/null

jq -e --arg condition "$DATAPLANE_BLOB_LIST_ONLY_CONDITION" '
  .condition == $condition
  and .conditionVersion == "2.0"
' /tmp/tidbcloud-byoc-dataplane-role-assignment.json >/dev/null

jq -e '
  ((.actions // []) | sort) == ([
    "Microsoft.Network/dnsZones/read",
    "Microsoft.Network/dnsZones/A/read",
    "Microsoft.Network/dnsZones/A/write",
    "Microsoft.Network/dnsZones/A/delete"
  ] | sort)
  and ((.notActions // []) | length == 0)
  and ((.dataActions // []) | length == 0)
  and ((.notDataActions // []) | length == 0)
' /tmp/tidbcloud-byoc-dataplane-dns-role-perms.json >/dev/null

jq -e --arg scope "$DNS_RESOURCE_GROUP_SCOPE" '
  (.assignableScopes // []) == [$scope]
' /tmp/tidbcloud-byoc-dataplane-dns-role.json >/dev/null

jq -e --arg role "$DATAPLANE_DNS_ROLE" --arg scope "$DNS_SCOPE" '
  .roleDefinitionName == $role
  and .scope == $scope
' /tmp/tidbcloud-byoc-dataplane-dns-role-assignment.json >/dev/null
```

Pass criteria:

- Deployment app has temporary `Contributor` at BYOC subscription scope.
- Deployment app has persistent `Contributor` at ACR scope.
- Dataplane app has dataplane custom role at BYOC subscription scope.
- Dataplane app has DNS record custom role at the public DNS zone scope, in the public DNS zone subscription.
- Dataplane app is a member of the AKS admin group.
- Custom roles do not include role assignment write/delete.
- Dataplane custom role uses explicit storage account, container, and lifecycle management actions without storage wildcards.
- Dataplane custom role has blob read DataAction only with a subscription role-assignment condition that allows `Blob.List` and denies blob content reads.
- Dataplane custom role does not include public DNS zone actions or copied `DNS Zone Contributor` support actions.
- Dataplane DNS record custom role includes only DNS zone read and DNS A record read/write/delete actions.

## 5. Idempotency

```bash
set -euo pipefail
source /tmp/tidbcloud-byoc-azure-test.env
cd "$AZURE_DIR"

bash tidbcloud-byoc-setup.sh \
  --customer-id "$CUSTOMER_ID" \
  --location "$LOCATION" \
  --tenant-id "$TENANT_ID" \
  --subscription-id "$SUBSCRIPTION_ID" \
  --dns-zone-subscription-id "$DNS_ZONE_SUBSCRIPTION_ID" \
  --dns-zone-resource-group "$DNS_ZONE_RESOURCE_GROUP" \
  --dns-zone-root-domain "$DNS_ZONE_ROOT_DOMAIN" \
  --deployment-app-id "$DEPLOYMENT_APP_ID" \
  --dataplane-app-id "$DATAPLANE_APP_ID" \
  | tee /tmp/tidbcloud-byoc-setup-second-run.out
```

Pass criteria:

- Second setup run succeeds.
- No duplicate enterprise applications, group memberships, or role assignments
  are created.

## 6. Revoke Temporary Initial Deployment Access

```bash
set -euo pipefail
source /tmp/tidbcloud-byoc-azure-test.env
cd "$AZURE_DIR"

bash tidbcloud-byoc-revoke-initial-deploy-access.sh \
  --customer-id "$CUSTOMER_ID" \
  --subscription-id "$SUBSCRIPTION_ID" \
  --yes

az account set --subscription "$SUBSCRIPTION_ID"
if az stack sub show --name "cust-${CUSTOMER_ID}-tidbcloud-byoc-setup-initial-deploy-access" >/dev/null 2>&1; then
  echo "Initial deploy access stack still exists" >&2
  exit 1
fi

bash tidbcloud-byoc-revoke-initial-deploy-access.sh \
  --customer-id "$CUSTOMER_ID" \
  --subscription-id "$SUBSCRIPTION_ID" \
  --yes
```

Pass criteria:

- First revoke deletes the initial deployment access stack.
- Second revoke exits successfully and reports already revoked or missing.
- ACR and dataplane access remain.

## 7. Update Script

```bash
set -euo pipefail
source /tmp/tidbcloud-byoc-azure-test.env
cd "$AZURE_DIR"

for stack in deploy dataplane o11y state all; do
  bash tidbcloud-byoc-update.sh \
    --customer-id "$CUSTOMER_ID" \
    --subscription-id "$SUBSCRIPTION_ID" \
    --stack "$stack"
done

bash tidbcloud-byoc-update.sh \
  --customer-id "$CUSTOMER_ID" \
  --subscription-id "$SUBSCRIPTION_ID" \
  --stack initial-deploy-access
```

Pass criteria:

- `deploy`, `dataplane`, `o11y`, `state`, and `all` reconcile successfully.
- `all` does not recreate temporary initial deployment access.
- `initial-deploy-access` recreates temporary initial deployment access.

## 8. Revoke PingCAP App Access While Keeping Resources

Use this in an environment where it is acceptable to remove PingCAP app access.

```bash
set -euo pipefail
source /tmp/tidbcloud-byoc-azure-test.env
cd "$AZURE_DIR"

bash tidbcloud-byoc-revoke-app-access.sh \
  --customer-id "$CUSTOMER_ID" \
  --subscription-id "$SUBSCRIPTION_ID" \
  --keep-enterprise-apps \
  --yes
```

Verification:

```bash
set -euo pipefail
source /tmp/tidbcloud-byoc-azure-test.env
STATE=/tmp/tidbcloud-byoc-setup-state.json

az account set --subscription "$SUBSCRIPTION_ID"

DEPLOYMENT_SP_OBJECT_ID=$(az ad sp show --id "$DEPLOYMENT_APP_ID" --query id -o tsv)
DATAPLANE_SP_OBJECT_ID=$(az ad sp show --id "$DATAPLANE_APP_ID" --query id -o tsv)
ACR_RESOURCE_ID=$(jq -r '.acrResourceId' "$STATE")
ACR_RESOURCE_GROUP=$(jq -r '.acrResourceGroupName' "$STATE")
ACR_NAME=$(jq -r '.acrName' "$STATE")
AKS_ADMIN_GROUP_OBJECT_ID=$(jq -r '.aksAdminGroupObjectId' "$STATE")

test -z "$(az role assignment list --assignee "$DEPLOYMENT_SP_OBJECT_ID" --scope "/subscriptions/${SUBSCRIPTION_ID}" --query '[].id' -o tsv)"
test -z "$(az role assignment list --assignee "$DEPLOYMENT_SP_OBJECT_ID" --scope "$ACR_RESOURCE_ID" --query '[].id' -o tsv)"
test -z "$(az role assignment list --assignee "$DATAPLANE_SP_OBJECT_ID" --scope "/subscriptions/${SUBSCRIPTION_ID}" --query '[].id' -o tsv)"
test "$(az ad group member check --group "$AKS_ADMIN_GROUP_OBJECT_ID" --member-id "$DATAPLANE_SP_OBJECT_ID" --query value -o tsv)" = "false"

az acr show --resource-group "$ACR_RESOURCE_GROUP" --name "$ACR_NAME" --query name -o tsv
az stack sub show --name "cust-${CUSTOMER_ID}-tidbcloud-byoc-setup-state" --query name -o tsv
```

Pass criteria:

- PingCAP app RBAC and AKS admin group membership are removed.
- Deployment application temporary subscription access is removed.
- Enterprise applications remain because `--keep-enterprise-apps` was set.
- Customer resources and onboarding state remain.

Recover access for later tests:

```bash
set -euo pipefail
source /tmp/tidbcloud-byoc-azure-test.env
cd "$AZURE_DIR"

bash tidbcloud-byoc-setup.sh \
  --customer-id "$CUSTOMER_ID" \
  --location "$LOCATION" \
  --tenant-id "$TENANT_ID" \
  --subscription-id "$SUBSCRIPTION_ID" \
  --dns-zone-subscription-id "$DNS_ZONE_SUBSCRIPTION_ID" \
  --dns-zone-resource-group "$DNS_ZONE_RESOURCE_GROUP" \
  --dns-zone-root-domain "$DNS_ZONE_ROOT_DOMAIN" \
  --deployment-app-id "$DEPLOYMENT_APP_ID" \
  --dataplane-app-id "$DATAPLANE_APP_ID"
```

## 9. Reset Tests

Run reset tests only in isolated test environments.

### 9.1 Default Reset Keeps ACR And Enterprise Apps

```bash
set -euo pipefail
source /tmp/tidbcloud-byoc-azure-test.env
cd "$AZURE_DIR"

STATE=/tmp/tidbcloud-byoc-setup-state.json
ACR_RESOURCE_GROUP=$(jq -r '.acrResourceGroupName' "$STATE")
ACR_NAME=$(jq -r '.acrName' "$STATE")

bash tidbcloud-byoc-reset.sh \
  --customer-id "$CUSTOMER_ID" \
  --subscription-id "$SUBSCRIPTION_ID" \
  --yes

az acr show --resource-group "$ACR_RESOURCE_GROUP" --name "$ACR_NAME" --query name -o tsv
az ad sp show --id "$DEPLOYMENT_APP_ID" --query appId -o tsv
az ad sp show --id "$DATAPLANE_APP_ID" --query appId -o tsv
```

Pass criteria:

- Setup-created stacks and non-ACR resource groups are deleted.
- ACR remains.
- Enterprise applications remain.
- Customer-prepared DNS zone remains.

### 9.2 Full Reset Deletes ACR And Enterprise Apps

Re-run setup first, then run:

```bash
set -euo pipefail
source /tmp/tidbcloud-byoc-azure-test.env
cd "$AZURE_DIR"

bash tidbcloud-byoc-reset.sh \
  --customer-id "$CUSTOMER_ID" \
  --subscription-id "$SUBSCRIPTION_ID" \
  --delete-acr \
  --delete-enterprise-apps \
  --yes
```

Pass criteria:

- Setup stacks, setup resource groups, ACR, AKS admin group, and PingCAP
  enterprise applications are deleted.
- Customer-prepared public DNS zone remains.

## 10. Required Scenario Matrix

Run the full plan for at least these variants:

| Variant | Required? | Notes |
|---|---:|---|
| DNS zone in same BYOC subscription | Yes | Validates single-subscription assignable scope |
| DNS zone in separate subscription | Yes | Validates cross-subscription DNS RBAC |
| Default generated ACR names | Yes | Validates deterministic naming |
| Custom ACR resource group and name | Yes | Add `--acr-resource-group` and `--acr-name` to setup |
| Re-run setup after initial access revoke | Yes | Setup should recreate temporary access |
| Revoke app access with `--keep-enterprise-apps` | Yes | Shared enterprise app scenario |
| Revoke app access without `--keep-enterprise-apps` | Optional | Isolated tenant only |
| Full reset with `--delete-acr --delete-enterprise-apps` | Optional | Isolated tenant only |

## 11. Final Test Report Template

Record the result after each run:

```text
Customer ID:
Tenant ID:
BYOC subscription:
DNS subscription:
DNS zone:
Location:

Local validation:
Setup:
Resource verification:
RBAC verification:
Idempotency:
Revoke initial deploy access:
Update:
Revoke app access:
Reset:

Failures:
Manual cleanup required:
Residual risk:
```
