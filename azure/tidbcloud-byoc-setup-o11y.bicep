targetScope = 'subscription'

param customerId string
param location string
param o11yResourceGroupName string = 'rg-tidbcloud-${customerId}-o11y'

var o11yInfraResourceGroupName = '${o11yResourceGroupName}-infra'
var o11yStorageResourceGroupName = '${o11yResourceGroupName}-storage'
var regionalServerIdentityResourceId = resourceId(subscription().subscriptionId, o11yResourceGroupName, 'Microsoft.ManagedIdentity/userAssignedIdentities', 'o11y-regional-server')
var vmbackupIdentityResourceId = resourceId(subscription().subscriptionId, o11yResourceGroupName, 'Microsoft.ManagedIdentity/userAssignedIdentities', 'o11y-vmbackup')
var lokiIdentityResourceId = resourceId(subscription().subscriptionId, o11yResourceGroupName, 'Microsoft.ManagedIdentity/userAssignedIdentities', 'o11y-loki')
var veleroIdentityResourceId = resourceId(subscription().subscriptionId, o11yResourceGroupName, 'Microsoft.ManagedIdentity/userAssignedIdentities', 'o11y-velero')

// Azure built-in role definition IDs.
var ownerRoleId = '8e3af657-a8ff-443c-a75c-2fe8c4bcb635'
var networkContributorRoleId = '4d97b98b-1d4f-4787-a291-c67834d212e7'
var storageBlobDataOwnerRoleId = 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b'
var storageBlobDataContributorRoleId = 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
var contributorRoleId = 'b24988ac-6180-42a0-ab88-20f7382dd24c'

var ownerRoleDefinitionId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', ownerRoleId)
var networkContributorRoleDefinitionId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', networkContributorRoleId)
var storageBlobDataOwnerRoleDefinitionId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageBlobDataOwnerRoleId)
var storageBlobDataContributorRoleDefinitionId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageBlobDataContributorRoleId)
var contributorRoleDefinitionId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', contributorRoleId)

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

resource veleroContributorAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, veleroIdentityResourceId, contributorRoleDefinitionId)
  properties: {
    principalId: o11yIdentities.outputs.veleroPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: contributorRoleDefinitionId
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
}
