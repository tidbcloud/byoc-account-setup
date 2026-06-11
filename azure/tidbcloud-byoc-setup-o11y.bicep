targetScope = 'subscription'

param deployName string
param location string
param o11yResourceGroupName string = 'rg-tidbcloud-${deployName}-o11y'
param acrSubscriptionId string
param acrResourceGroupName string
param acrName string
param o11yAksControlPlaneIdentityName string = 'tidbcloud-${deployName}-o11y-aks-control-plane'
param o11yAksKubeletIdentityName string = 'tidbcloud-${deployName}-o11y-aks-kubelet'
param o11yAgicRoleName string = 'TiDB BYOC O11Y AGIC Operator - ${deployName}'

var o11yInfraResourceGroupName = '${o11yResourceGroupName}-infra'
var o11yStorageResourceGroupName = '${o11yResourceGroupName}-storage'
var regionalServerIdentityResourceId = resourceId(subscription().subscriptionId, o11yResourceGroupName, 'Microsoft.ManagedIdentity/userAssignedIdentities', 'o11y-regional-server')
var vmbackupIdentityResourceId = resourceId(subscription().subscriptionId, o11yResourceGroupName, 'Microsoft.ManagedIdentity/userAssignedIdentities', 'o11y-vmbackup')
var lokiIdentityResourceId = resourceId(subscription().subscriptionId, o11yResourceGroupName, 'Microsoft.ManagedIdentity/userAssignedIdentities', 'o11y-loki')
var veleroIdentityResourceId = resourceId(subscription().subscriptionId, o11yResourceGroupName, 'Microsoft.ManagedIdentity/userAssignedIdentities', 'o11y-velero')
var agicIdentityResourceId = resourceId(subscription().subscriptionId, o11yResourceGroupName, 'Microsoft.ManagedIdentity/userAssignedIdentities', 'o11y-agic')
var o11yAksControlPlaneIdentityResourceId = resourceId(subscription().subscriptionId, o11yResourceGroupName, 'Microsoft.ManagedIdentity/userAssignedIdentities', o11yAksControlPlaneIdentityName)
var o11yAksKubeletIdentityResourceId = resourceId(subscription().subscriptionId, o11yResourceGroupName, 'Microsoft.ManagedIdentity/userAssignedIdentities', o11yAksKubeletIdentityName)

// Azure built-in role definition IDs.
var ownerRoleId = '8e3af657-a8ff-443c-a75c-2fe8c4bcb635'
var networkContributorRoleId = '4d97b98b-1d4f-4787-a291-c67834d212e7'
var managedIdentityOperatorRoleId = 'f1a07417-d97a-45cb-824c-7a7467783830'
var acrPullRoleId = '7f951dda-4ed3-4680-a7ca-43fe172d538d'
var storageBlobDataOwnerRoleId = 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b'
var storageBlobDataContributorRoleId = 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
var storageAccountKeyOperatorServiceRoleId = '81a9662b-bebf-436f-a333-f67b29880f12'
var readerRoleId = 'acdd72a7-3385-48ef-bd42-f606fba81ae7'

var ownerRoleDefinitionId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', ownerRoleId)
var networkContributorRoleDefinitionId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', networkContributorRoleId)
var managedIdentityOperatorRoleDefinitionId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', managedIdentityOperatorRoleId)
var acrPullRoleDefinitionId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', acrPullRoleId)
var storageBlobDataOwnerRoleDefinitionId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageBlobDataOwnerRoleId)
var storageBlobDataContributorRoleDefinitionId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageBlobDataContributorRoleId)
var storageAccountKeyOperatorServiceRoleDefinitionId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageAccountKeyOperatorServiceRoleId)
var readerRoleDefinitionId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', readerRoleId)

resource o11yResourceGroup 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: o11yResourceGroupName
  location: location
}

resource o11yInfraResourceGroup 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: o11yInfraResourceGroupName
  location: location
}

resource o11yStorageResourceGroup 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: o11yStorageResourceGroupName
  location: location
}

module o11yIdentities './modules/o11y-identity-resources.bicep' = {
  name: 'o11y-identity-resources'
  scope: o11yResourceGroup
  params: {
    location: location
    o11yAksControlPlaneIdentityName: o11yAksControlPlaneIdentityName
    o11yAksKubeletIdentityName: o11yAksKubeletIdentityName
  }
}

module o11yAgicRoleAssignment './modules/o11y-agic-role-assignment.bicep' = {
  name: 'o11y-agic-role-${uniqueString(subscription().id, deployName)}'
  params: {
    roleName: o11yAgicRoleName
    principalId: o11yIdentities.outputs.o11yAgicPrincipalId
    assignmentGuidSeed: agicIdentityResourceId
    roleGuidSeed: '/subscriptions/${subscription().subscriptionId}/resourceGroups/${o11yInfraResourceGroupName}'
  }
}

module regionalServerInfraOwnerAssignment './modules/resource-group-role-assignment.bicep' = {
  name: 'o11y-regional-server-infra-owner'
  scope: o11yInfraResourceGroup
  params: {
    principalId: o11yIdentities.outputs.regionalServerPrincipalId
    roleDefinitionId: ownerRoleDefinitionId
    assignmentGuidSeed: regionalServerIdentityResourceId
  }
}

module regionalServerStorageOwnerAssignment './modules/resource-group-role-assignment.bicep' = {
  name: 'o11y-regional-server-storage-owner'
  scope: o11yStorageResourceGroup
  params: {
    principalId: o11yIdentities.outputs.regionalServerPrincipalId
    roleDefinitionId: ownerRoleDefinitionId
    assignmentGuidSeed: regionalServerIdentityResourceId
  }
}

module regionalServerInfraNetworkContributorAssignment './modules/resource-group-role-assignment.bicep' = {
  name: 'o11y-regional-server-infra-network-contributor'
  scope: o11yInfraResourceGroup
  params: {
    principalId: o11yIdentities.outputs.regionalServerPrincipalId
    roleDefinitionId: networkContributorRoleDefinitionId
    assignmentGuidSeed: regionalServerIdentityResourceId
  }
}

module regionalServerStorageBlobDataOwnerAssignment './modules/resource-group-role-assignment.bicep' = {
  name: 'o11y-regional-server-storage-blob-owner'
  scope: o11yStorageResourceGroup
  params: {
    principalId: o11yIdentities.outputs.regionalServerPrincipalId
    roleDefinitionId: storageBlobDataOwnerRoleDefinitionId
    assignmentGuidSeed: regionalServerIdentityResourceId
  }
}

module vmbackupStorageBlobDataContributorAssignment './modules/resource-group-role-assignment.bicep' = {
  name: 'o11y-vmbackup-storage-blob-contributor'
  scope: o11yStorageResourceGroup
  params: {
    principalId: o11yIdentities.outputs.vmbackupPrincipalId
    roleDefinitionId: storageBlobDataContributorRoleDefinitionId
    assignmentGuidSeed: vmbackupIdentityResourceId
  }
}

module lokiStorageBlobDataContributorAssignment './modules/resource-group-role-assignment.bicep' = {
  name: 'o11y-loki-storage-blob-contributor'
  scope: o11yStorageResourceGroup
  params: {
    principalId: o11yIdentities.outputs.lokiPrincipalId
    roleDefinitionId: storageBlobDataContributorRoleDefinitionId
    assignmentGuidSeed: lokiIdentityResourceId
  }
}

module veleroStorageBlobDataContributorAssignment './modules/resource-group-role-assignment.bicep' = {
  name: 'o11y-velero-storage-blob-contributor'
  scope: o11yStorageResourceGroup
  params: {
    principalId: o11yIdentities.outputs.veleroPrincipalId
    roleDefinitionId: storageBlobDataContributorRoleDefinitionId
    assignmentGuidSeed: veleroIdentityResourceId
  }
}

module veleroStorageAccountKeyOperatorAssignment './modules/resource-group-role-assignment.bicep' = {
  name: 'o11y-velero-storage-key-operator'
  scope: o11yStorageResourceGroup
  params: {
    principalId: o11yIdentities.outputs.veleroPrincipalId
    roleDefinitionId: storageAccountKeyOperatorServiceRoleDefinitionId
    assignmentGuidSeed: veleroIdentityResourceId
  }
}

module veleroStorageReaderAssignment './modules/resource-group-role-assignment.bicep' = {
  name: 'o11y-velero-storage-reader'
  scope: o11yStorageResourceGroup
  params: {
    principalId: o11yIdentities.outputs.veleroPrincipalId
    roleDefinitionId: readerRoleDefinitionId
    assignmentGuidSeed: veleroIdentityResourceId
  }
}

resource o11yAksControlPlaneNetworkRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, o11yAksControlPlaneIdentityResourceId, networkContributorRoleDefinitionId)
  properties: {
    principalId: o11yIdentities.outputs.o11yAksControlPlanePrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: networkContributorRoleDefinitionId
  }
}

module o11yAksManagedIdentityOperatorAssignment './modules/identity-role-assignment.bicep' = {
  name: 'o11y-aks-managed-identity-operator-assignment'
  scope: o11yResourceGroup
  params: {
    identityName: o11yAksKubeletIdentityName
    principalId: o11yIdentities.outputs.o11yAksControlPlanePrincipalId
    roleDefinitionId: managedIdentityOperatorRoleDefinitionId
    assignmentGuidSeed: o11yAksControlPlaneIdentityResourceId
  }
}

module o11yAksAcrPullAssignment './modules/acr-role-assignment.bicep' = {
  name: 'o11y-aks-kubelet-acr-pull-assignment'
  scope: resourceGroup(acrSubscriptionId, acrResourceGroupName)
  params: {
    acrName: acrName
    principalId: o11yIdentities.outputs.o11yAksKubeletPrincipalId
    roleDefinitionId: acrPullRoleDefinitionId
    assignmentGuidSeed: o11yAksKubeletIdentityResourceId
  }
}

module regionalServerAcrPullAssignment './modules/acr-role-assignment.bicep' = {
  name: 'o11y-regional-server-acr-pull-assignment'
  scope: resourceGroup(acrSubscriptionId, acrResourceGroupName)
  params: {
    acrName: acrName
    principalId: o11yIdentities.outputs.regionalServerPrincipalId
    roleDefinitionId: acrPullRoleDefinitionId
    assignmentGuidSeed: regionalServerIdentityResourceId
  }
}

output o11yResourceGroupName string = o11yResourceGroup.name
output o11yInfraResourceGroupName string = o11yInfraResourceGroup.name
output o11yStorageResourceGroupName string = o11yStorageResourceGroup.name
output o11yIdentityNames object = {
  regionalServer: o11yIdentities.outputs.regionalServerIdentityName
  vmbackup: o11yIdentities.outputs.vmbackupIdentityName
  loki: o11yIdentities.outputs.lokiIdentityName
  velero: o11yIdentities.outputs.veleroIdentityName
  aksControlPlane: o11yIdentities.outputs.o11yAksControlPlaneIdentityName
  aksKubelet: o11yIdentities.outputs.o11yAksKubeletIdentityName
  agic: o11yIdentities.outputs.o11yAgicIdentityName
}
