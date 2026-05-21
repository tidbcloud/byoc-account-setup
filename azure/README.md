# TiDB Cloud BYOC Azure Account Setup

This guide explains what you need to prepare in your Azure environment before TiDB Cloud deploys BYOC components.

After you complete this guide, TiDB Cloud can:

- deploy BYOC infrastructure into the Azure subscription you provide;
- manage TiDB dataplane resources in that subscription;
- manage observability components required by TiDB Cloud;
- create DNS records for TiDB cluster endpoints in the DNS zone you provide.

## What you need to do

1. Prepare one Azure subscription for TiDB Cloud BYOC workloads.
2. Prepare one public DNS zone for TiDB cluster DNS records.
3. Obtain your TiDB Cloud BYOC deploy name and two TiDB Cloud multi-tenant application IDs from PingCAP.
4. Run the setup scripts provided by PingCAP.
5. Share the onboarding state stack coordinates with PingCAP.

## Before you start

### Information from PingCAP

Contact PingCAP and provide the Azure region where you want to deploy BYOC. PingCAP will provide:

- `deployName`: the TiDB Cloud BYOC deploy name used to name deployment-specific Azure resources;
- two multi-tenant application IDs;

| Application | Purpose |
|---|---|
| Deployment application | Deploys BYOC infrastructure |
| Dataplane management application | Manages TiDB dataplane resources after deployment |

### Permissions required for the person running setup

The Azure operator who runs the setup needs these roles:

| Scope | Required role | Purpose |
|---|---|---|
| BYOC subscription | `Contributor` | Create Azure resources required during setup |
| BYOC subscription | `User Access Administrator` | Create Azure custom roles and role assignments required during setup |
| Public DNS zone subscription | `User Access Administrator` | Required only when the DNS zone is outside the BYOC subscription; allows setup to create the DNS record custom role and grant access on the DNS zone |
| Microsoft Entra tenant | `Cloud Application Administrator` | Create enterprise applications from the PingCAP multi-tenant applications |
| Microsoft Entra tenant | `Groups Administrator` | Create the Microsoft Entra ID group and manage its members |

`Owner` at the subscription also satisfies the `Contributor` and `User Access Administrator` requirements.

The operator needs Azure CLI with Deployment Stack support on the machine that runs the setup script. The update, reset, and app-access revoke scripts also require `jq` to read the onboarding state stack output.

## Step 1: Prepare customer-owned resources

You create these resources manually before running the setup scripts.

### 1. Azure subscription

Create or choose a subscription dedicated to TiDB Cloud BYOC workloads. TiDB Cloud will provision cloud resources and run TiDB workloads in this subscription.

Provide these values to the setup script:

| Value | Description |
|---|---|
| `tenantId` | Your Microsoft Entra tenant ID |
| `subscriptionId` | The Azure subscription ID used for TiDB Cloud BYOC |

### 2. Public DNS zone

Create or choose a public Azure DNS zone for TiDB cluster endpoints. The DNS zone may be in the same subscription or another subscription under the same tenant.

TiDB Cloud will create and delete DNS records in this zone when TiDB clusters are created or deleted. Your applications use these records to connect to TiDB clusters.

Provide these values to the setup script:

| Value | Description |
|---|---|
| `subscriptionIdOfDNSZone` | Subscription ID that contains the DNS zone |
| `resourceGroupOfDNSZone` | Resource group that contains the DNS zone |
| `rootDomainOfDNSZone` | Root domain of the DNS zone, for example `tidb.example.com` |

A TiDB cluster endpoint will look similar to `xxxx.tidb.example.com`.

## Step 2: Run the setup scripts

The setup scripts create the Azure resources and access bindings required for TiDB Cloud BYOC.

### Resources created by the scripts

The public DNS zone itself is customer-provided. Custom roles and role assignments are covered in [Privileges granted during setup](#privileges-granted-during-setup). The scripts create or reconcile these resources:

| Category | Resource created or reconciled | Why it is needed |
|---|---|---|
| Deployment orchestration | Deployment stack `cust-<deployName>-tidbcloud-byoc-setup-deploy` | Manages deployment resource group, ACR resource group, and ACR |
| Deployment orchestration | Deployment stack `cust-<deployName>-tidbcloud-byoc-setup-initial-deploy-access` | Manages temporary initial deployment access resources |
| Deployment orchestration | Deployment stack `cust-<deployName>-tidbcloud-byoc-setup-dataplane` | Manages dataplane resource groups, identities, and audit storage |
| Deployment orchestration | Deployment stack `cust-<deployName>-tidbcloud-byoc-setup-o11y` | Manages O11Y resource groups and identities |
| Deployment orchestration | Deployment stack `cust-<deployName>-tidbcloud-byoc-setup-state` | Stores durable setup state and auto-deploy handoff outputs |
| Microsoft Entra ID | Enterprise application for the deployment application ID | Allows the TiDB Cloud deployment application to authenticate into the tenant |
| Microsoft Entra ID | Enterprise application for the dataplane management application ID | Allows the TiDB Cloud dataplane management application to authenticate into the tenant |
| Microsoft Entra ID | Group `tidbcloud-<deployName>-aks-admins` | Grants dataplane management AKS administrator access |
| Microsoft Entra ID | Dataplane management application membership in `tidbcloud-<deployName>-aks-admins` | Allows the dataplane management application to administer BYOC AKS clusters |
| Resource groups | Deployment resource group `rg-tidbcloud-<deployName>-deploy` | Holds deployment-related customer resources reserved for setup and operations |
| Resource groups | ACR resource group `rg-tidbcloud-<deployName>-acr` | Holds the customer Azure Container Registry |
| Resource groups | Dataplane storage resource group `rg-tidbcloud-<deployName>-storage` | Holds setup-created dataplane storage resources |
| Resource groups | Dataplane identities resource group `rg-tidbcloud-<deployName>-identities` | Holds dataplane user-assigned managed identities |
| Container registry | Azure Container Registry `tidbcloud<alphanumeric-deployName>acr`, or the provided ACR name | Stores container images used by TiDB Cloud components |
| Dataplane storage | Audit log storage account `st<last-12-alphanumeric-characters-of-deployName>auditlog` | Stores audit logs for TiDB Cloud control-plane operations on the dataplane |
| Dataplane storage | Default blob service on the audit log storage account | Enables blob container management on the audit log storage account |
| Dataplane storage | Audit log blob container `audit-log` | Stores audit log objects with public access disabled |
| Dataplane identities | User-assigned managed identity `tidbcloud-<deployName>-aks-control-plane` | Allows AKS to manage required Azure network resources |
| Dataplane identities | User-assigned managed identity `tidbcloud-<deployName>-aks-kubelet` | Allows AKS workloads to pull images and access blob storage |
| O11Y resource groups | O11Y identity/base resource group `rg-tidbcloud-<deployName>-o11y` | Holds O11Y workload managed identities |
| O11Y resource groups | O11Y AKS and network resource group `rg-tidbcloud-<deployName>-o11y-infra` | Holds O11Y AKS and network resources managed after setup |
| O11Y resource groups | O11Y storage resource group `rg-tidbcloud-<deployName>-o11y-storage` | Holds O11Y storage resources managed after setup |
| O11Y managed identities | User-assigned managed identity `o11y-regional-server` | Allows O11Y regional server workloads to manage O11Y infrastructure and storage |
| O11Y managed identities | User-assigned managed identity `o11y-vmbackup` | Allows VM backup workloads to access O11Y storage |
| O11Y managed identities | User-assigned managed identity `o11y-loki` | Allows Loki workloads to access O11Y storage |
| O11Y managed identities | User-assigned managed identity `o11y-velero` | Allows Velero workloads to manage backup and restore resources |

### Privileges granted during setup

This section describes the access created by the setup process. TiDB Cloud receives only the access needed to deploy and operate BYOC resources.

#### Access granted to TiDB Cloud applications

Each TiDB Cloud application receives only the access required for its responsibility.

| TiDB Cloud application | Azure role | Assigned scopes | Purpose |
|---|---|---|---|
| Deployment application | Built-in `Contributor` | BYOC subscription | Temporary access to create initial BYOC infrastructure and read onboarding state. This access can be revoked after the first deployment completes |
| Deployment application | Built-in `Contributor` | Customer ACR only | Query and push container images during daily management and upgrade workflows |
| Dataplane management application | Custom `TiDB BYOC Dataplane Operator - <deployName>` | BYOC subscription | Manage TiDB dataplane resources after deployment |
| Dataplane management application | Custom `TiDB BYOC Dataplane DNS Record Operator - <deployName>` | Public DNS zone | Create, update, read, and delete TiDB A records in the public DNS zone |

##### Deployment application temporary subscription access

The deployment application receives built-in `Contributor` at the BYOC subscription scope during setup.

This temporary grant is intentionally broad because the initial BYOC deployment creates resource groups and infrastructure across the subscription. Azure `Contributor` does not include Azure RBAC role-assignment permissions, so the setup still requires the Azure operator to have `User Access Administrator` for role assignments created during onboarding.

The setup keeps this subscription-scoped `Contributor` assignment in a separate deployment stack so it can be deleted after the first BYOC deployment without deleting customer resources. After it is revoked, the deployment application no longer has BYOC subscription access to read the onboarding state stack.

##### Deployment application ACR access

The deployment application also receives built-in `Contributor` on the customer ACR only.

This ACR-scoped grant is intentionally kept after initial deployment. TiDB Cloud uses it to query existing ACR images and push required images before upgrade or maintenance workflows.

`Contributor` on an ACR is broader than image push. It can manage that ACR resource, but only at the ACR scope; it does not grant access to the rest of the subscription.

##### `TiDB BYOC Dataplane Operator - <deployName>`

This custom role should contain only the Azure permissions required for dataplane management:

| Resource area | Required management-plane access |
|---|---|
| Resource groups | `Microsoft.Resources/subscriptions/resourceGroups/*` |
| AKS clusters and node pools | `Microsoft.ContainerService/managedClusters/*`, `Microsoft.ContainerService/managedClusters/agentPools/*` |
| AKS cluster credentials | Managed-cluster credential retrieval actions, such as `managedClusters/listCluster*Credential/action` |
| Networking | `Microsoft.Network/virtualNetworks/*`, `Microsoft.Network/natGateways/*`, `Microsoft.Network/publicIPAddresses/*`, `Microsoft.Network/privateLinkServices/*`, `Microsoft.Network/privateEndpoints/*`, `Microsoft.Network/privateDnsZones/*`, `Microsoft.Network/loadBalancers/read` |
| Storage account management | `Microsoft.Storage/storageAccounts/read`, `Microsoft.Storage/storageAccounts/write`, `Microsoft.Storage/storageAccounts/delete` |
| Storage container management | `Microsoft.Storage/storageAccounts/blobServices/read`, `Microsoft.Storage/storageAccounts/blobServices/containers/read`, `Microsoft.Storage/storageAccounts/blobServices/containers/write`, `Microsoft.Storage/storageAccounts/blobServices/containers/delete` |
| Storage lifecycle management | `Microsoft.Storage/storageAccounts/managementPolicies/read`, `Microsoft.Storage/storageAccounts/managementPolicies/write`, `Microsoft.Storage/storageAccounts/managementPolicies/delete` |
| Blob data listing | Data action `Microsoft.Storage/storageAccounts/blobServices/containers/blobs/read`, with a subscription role-assignment condition that permits only the `Blob.List` suboperation and denies blob content reads |

Assign this role at the BYOC subscription because dataplane management needs to create and manage Azure resource groups.

The BYOC subscription role assignment uses Azure RBAC condition version `2.0` to restrict blob data access to container listing only: `!(ActionMatches{'Microsoft.Storage/storageAccounts/blobServices/containers/blobs/read'} AND NOT SubOperationMatches{'Blob.List'})`. The custom role therefore can list blobs in a container but cannot read blob object content.

This runtime role should not include Azure role-assignment permissions such as `Microsoft.Authorization/roleAssignments/write`.

##### `TiDB BYOC Dataplane DNS Record Operator - <deployName>`

This custom role should contain only the Azure permissions required for TiDB Cloud DNS A record management:

| Resource area | Required management-plane access |
|---|---|
| Public DNS zone read | `Microsoft.Network/dnsZones/read` |
| Public DNS A records | `Microsoft.Network/dnsZones/A/read`, `Microsoft.Network/dnsZones/A/write`, `Microsoft.Network/dnsZones/A/delete` |

The setup creates this role in the resource group that contains the public DNS zone, using `subscriptionIdOfDNSZone` and `resourceGroupOfDNSZone`. The setup assigns it at the exact public DNS zone scope, so the DNS zone subscription can differ from the BYOC subscription.

#### Access granted to customer-owned managed identities during setup

The setup process grants the required managed-identity roles before runtime operation, so the dataplane management application does not need role-assignment privileges such as `User Access Administrator`.

##### Dataplane managed identities

| Identity | Scope | Azure role | Purpose |
|---|---|---|---|
| Dataplane AKS kubelet identity | ACR | `AcrPull` | Allow AKS workloads to pull container images |
| Dataplane AKS kubelet identity | BYOC subscription | `Storage Blob Data Owner` | Allow dataplane workloads to access Azure Blob Storage |
| Dataplane AKS control-plane identity | Required network scope | `Network Contributor` | Allow AKS to manage required network resources |
| Dataplane AKS control-plane identity | Kubelet identity | `Managed Identity Operator` | Required by Azure AKS when using a pre-created kubelet identity |

##### O11Y workload managed identities

The setup creates these fixed-name customer-owned managed identities in the O11Y resource group:

- `o11y-regional-server`
- `o11y-vmbackup`
- `o11y-loki`
- `o11y-velero`

No separate O11Y resource group input is required. The setup derives O11Y resource group names from `deployName`:

| O11Y resource group | Name |
|---|---|
| Identity/base resource group | `rg-tidbcloud-<deployName>-o11y` |
| AKS and network resource group | `rg-tidbcloud-<deployName>-o11y-infra` |
| Storage resource group | `rg-tidbcloud-<deployName>-o11y-storage` |

The setup grants these RBAC roles:

| Identity | Scope | Azure role | Purpose |
|---|---|---|---|
| `o11y-regional-server` | O11Y AKS/network resource group | `Owner` | Manage O11Y AKS and infrastructure resources |
| `o11y-regional-server` | O11Y AKS/network resource group | `Network Contributor` | Manage O11Y network resources |
| `o11y-regional-server` | O11Y storage resource group | `Owner` | Manage O11Y storage resources |
| `o11y-regional-server` | O11Y storage resource group | `Storage Blob Data Owner` | Manage O11Y blob data |
| `o11y-vmbackup` | O11Y storage resource group | `Storage Blob Data Contributor` | Read and write VM backup blob data |
| `o11y-loki` | O11Y storage resource group | `Storage Blob Data Contributor` | Read and write Loki blob data |
| `o11y-velero` | BYOC subscription | `Contributor` | Manage backup and restore resources |

### Script inputs

Prepare the following values before running the scripts:

| Input | Description |
|---|---|
| `deployName` | TiDB Cloud BYOC deploy name provided by PingCAP. The setup uses it to name deployment-specific Azure resources. |
| `tenantId` | Your Microsoft Entra tenant ID |
| `subscriptionId` | Subscription ID for TiDB Cloud BYOC workloads |
| `subscriptionIdOfDNSZone` | Subscription ID that contains the public DNS zone |
| `resourceGroupOfDNSZone` | Resource group that contains the public DNS zone |
| `rootDomainOfDNSZone` | Root domain of the public DNS zone |
| Deployment application ID | Multi-tenant application ID provided by PingCAP |
| Dataplane management application ID | Multi-tenant application ID provided by PingCAP |

If optional resource names are not provided, the setup script uses deterministic names based on `deployName`. The ACR is created in a separate resource group, `rg-tidbcloud-<deployName>-acr`. For the audit log storage account, the script uses `st<last-12-alphanumeric-characters-of-deployName>auditlog` to stay within Azure's 24-character storage account name limit.

### Run the scripts

Run the setup script once to create or reconcile the Azure resources, enterprise applications, groups, and role assignments:

```bash
bash tidbcloud-byoc-setup.sh \
  --deploy-name <deployName> \
  --location <azureRegion> \
  --tenant-id <tenantId> \
  --subscription-id <subscriptionId> \
  --dns-zone-subscription-id <subscriptionIdOfDNSZone> \
  --dns-zone-resource-group <resourceGroupOfDNSZone> \
  --dns-zone-root-domain <rootDomainOfDNSZone> \
  --deployment-app-id <deploymentApplicationId> \
  --dataplane-app-id <dataplaneManagementApplicationId>
```

The script is idempotent for the initial onboarding flow. Running it again reconciles the full setup, including temporary initial deployment access. If you already revoked that temporary access after the first deployment, re-running setup will recreate it. Revoke it again after the deployment or recovery operation completes.

### Script output

After the scripts finish, the canonical handoff is stored in the onboarding state deployment stack inside the customer subscription. While temporary initial deployment access is still present, the deployment application can retrieve the `customerOnboarding` output directly.

## Step 3: Provide setup handoff to PingCAP

After the scripts finish, provide these values to PingCAP:

- `deployName`;
- `tenantId`;
- `subscriptionId`;
- onboarding state stack name, `cust-<deployName>-tidbcloud-byoc-setup-state`.

TiDB Cloud uses the deployment application to read the onboarding state stack and retrieve the `customerOnboarding` output before temporary initial deployment access is revoked.

## FAQ

### How do I revoke temporary initial deployment access?

After the first BYOC deployment completes, revoke the temporary initial deployment access:

```bash
bash tidbcloud-byoc-revoke-initial-deploy-access.sh \
  --deploy-name <deployName> \
  --subscription-id <subscriptionId> \
  --yes
```

This deletes only the temporary initial deployment access stack. It does not delete the ACR, BYOC resource groups, dataplane resources, O11Y resources, or onboarding state. The deployment application keeps only ACR-scoped access for image query and image push during upgrades.

### How do I update setup-managed resources after a template change?

Use the update script to reconcile one setup-managed deployment stack:

```bash
bash tidbcloud-byoc-update.sh --deploy-name <deployName> --subscription-id <subscriptionId> --stack deploy
bash tidbcloud-byoc-update.sh --deploy-name <deployName> --subscription-id <subscriptionId> --stack dataplane
bash tidbcloud-byoc-update.sh --deploy-name <deployName> --subscription-id <subscriptionId> --stack o11y
```

Use `--stack all` to update all long-lived stacks. The update script reads the durable onboarding state from the customer subscription, not from local files.

Run `--stack initial-deploy-access` only when PingCAP needs to re-enable temporary initial deployment access, for example to recover or repeat the initial BYOC deployment flow:

```bash
bash tidbcloud-byoc-update.sh \
  --deploy-name <deployName> \
  --subscription-id <subscriptionId> \
  --stack initial-deploy-access
```

After that operation completes, run the revoke command again.

### What access remains for upgrades?

After the first BYOC deployment, normal upgrade operations should not require the temporary initial deployment access.

For upgrades, TiDB Cloud keeps:

| Access | Why it remains |
|---|---|
| Deployment application `Contributor` on the customer ACR | Query existing images to avoid duplicate synchronization and push images required by the upgrade |
| Dataplane management application `TiDB BYOC Dataplane Operator - <deployName>` | Manage TiDB dataplane resources during runtime operations |
| Dataplane management application `TiDB BYOC Dataplane DNS Record Operator - <deployName>` | Manage TiDB A records in the public DNS zone |
| Customer-owned managed identity assignments | Allow AKS and O11Y workloads to access customer-owned Azure resources |

### How do I reset a test setup?

For a non-production retest, you can remove the Azure resources created by the setup scripts and then run setup again.

Run this command with an Azure operator that has the same subscription and Microsoft Entra permissions used for setup.

Destroy any BYOC deployments created after setup before running this command. The reset script deletes setup-created resource groups; if later resources were placed inside those resource groups, Azure resource-group deletion will delete them too.

```bash
bash tidbcloud-byoc-reset.sh \
  --deploy-name <deployName> \
  --subscription-id <subscriptionId> \
  --yes
```

This deletes setup-managed deployment stacks, resource groups, role assignments, custom roles, managed identities, audit storage, O11Y setup resources, and the setup-created AKS admin group. By default, it keeps the ACR resource group and ACR.

It does not delete:

- the ACR resource group and ACR, unless you add `--delete-acr`;
- the customer-prepared public DNS zone;
- PingCAP enterprise applications, unless you add `--delete-enterprise-apps`.

To also delete the ACR during test reset, add `--delete-acr`:

```bash
bash tidbcloud-byoc-reset.sh \
  --deploy-name <deployName> \
  --subscription-id <subscriptionId> \
  --delete-acr \
  --yes
```

For a full reset in an isolated test tenant, run:

```bash
bash tidbcloud-byoc-reset.sh \
  --deploy-name <deployName> \
  --subscription-id <subscriptionId> \
  --delete-acr \
  --delete-enterprise-apps \
  --yes
```

Only use `--delete-enterprise-apps` when the PingCAP BYOC enterprise applications are not shared by another BYOC setup in the same Microsoft Entra tenant.

### How do I stop using TiDB Cloud BYOC but keep Azure resources?

If you no longer want PingCAP to access the BYOC environment, but want to keep the customer Azure resources for review or manual cleanup, revoke only the PingCAP multi-tenant application access.

Run this command with an Azure operator that can delete role assignments, update Microsoft Entra group membership, and delete enterprise applications:

```bash
bash tidbcloud-byoc-revoke-app-access.sh \
  --deploy-name <deployName> \
  --subscription-id <subscriptionId> \
  --yes
```

This removes:

- temporary initial deployment access;
- Deployment application role assignments, including ACR-scoped `Contributor`;
- Dataplane management application role assignments;
- Dataplane management application membership in the AKS admin group;
- PingCAP enterprise applications in the customer tenant.

It keeps:

- setup-created resource groups and resources;
- customer-owned managed identities;
- customer-owned managed identity role assignments;
- onboarding state stack and its outputs.

If the PingCAP enterprise applications are shared by another BYOC setup in the same Microsoft Entra tenant, add `--keep-enterprise-apps` and remove only this environment's role assignments.
