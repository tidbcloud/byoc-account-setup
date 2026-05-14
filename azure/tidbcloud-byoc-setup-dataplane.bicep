targetScope = 'subscription'

param customerId string
param location string
param dataplanePrincipalObjectId string
param dnsZoneSubscriptionId string
param dnsZoneResourceGroupName string
param dnsZoneName string
param acrSubscriptionId string
param acrResourceGroupName string
param acrName string
param storageResourceGroupName string = 'rg-tidbcloud-${customerId}-storage'
param identitiesResourceGroupName string = 'rg-tidbcloud-${customerId}-identities'
param auditLogStorageAccountName string
param auditLogContainerName string = 'audit-log'
param aksControlPlaneIdentityName string = 'tidbcloud-${customerId}-aks-control-plane'
param aksKubeletIdentityName string = 'tidbcloud-${customerId}-aks-kubelet'
param dataplaneRoleName string = 'TiDB BYOC Dataplane Operator - ${customerId}'
param dataplaneDnsRoleName string = 'TiDB BYOC Dataplane DNS Record Operator - ${customerId}'

var dataplaneBlobListOnlyCondition = '''!(ActionMatches{'Microsoft.Storage/storageAccounts/blobServices/containers/blobs/read'} AND NOT SubOperationMatches{'Blob.List'})'''

resource storageResourceGroup 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: storageResourceGroupName
  location: location
}

resource identitiesResourceGroup 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: identitiesResourceGroupName
  location: location
}

module dataplaneStorage './modules/dataplane-resources.bicep' = {
  name: 'dataplane-resources'
  scope: storageResourceGroup
  params: {
    location: location
    auditLogStorageAccountName: auditLogStorageAccountName
    auditLogContainerName: auditLogContainerName
  }
}

module dataplaneIdentities './modules/identity-resources.bicep' = {
  name: 'identity-resources'
  scope: identitiesResourceGroup
  params: {
    location: location
    aksControlPlaneIdentityName: aksControlPlaneIdentityName
    aksKubeletIdentityName: aksKubeletIdentityName
  }
}

resource dataplaneRole 'Microsoft.Authorization/roleDefinitions@2022-04-01' = {
  name: guid(subscription().id, dataplaneRoleName)
  properties: {
    roleName: dataplaneRoleName
    description: 'Least-privilege runtime role for TiDB Cloud BYOC dataplane management.'
    type: 'CustomRole'
    permissions: [
      {
        actions: [
          'Microsoft.Resources/subscriptions/resourceGroups/*'
          'Microsoft.ContainerService/managedClusters/*'
          'Microsoft.ContainerService/managedClusters/agentPools/*'
          'Microsoft.Network/virtualNetworks/*'
          'Microsoft.Network/natGateways/*'
          'Microsoft.Network/publicIPAddresses/*'
          'Microsoft.Network/privateLinkServices/*'
          'Microsoft.Network/privateEndpoints/*'
          'Microsoft.Network/privateDnsZones/*'
          'Microsoft.Network/loadBalancers/read'
          'Microsoft.Storage/storageAccounts/read'
          'Microsoft.Storage/storageAccounts/write'
          'Microsoft.Storage/storageAccounts/delete'
          'Microsoft.Storage/storageAccounts/blobServices/read'
          'Microsoft.Storage/storageAccounts/blobServices/containers/read'
          'Microsoft.Storage/storageAccounts/blobServices/containers/write'
          'Microsoft.Storage/storageAccounts/blobServices/containers/delete'
          'Microsoft.Storage/storageAccounts/managementPolicies/read'
          'Microsoft.Storage/storageAccounts/managementPolicies/write'
          'Microsoft.Storage/storageAccounts/managementPolicies/delete'
        ]
        notActions: [
          'Microsoft.Authorization/roleAssignments/write'
          'Microsoft.Authorization/roleAssignments/delete'
        ]
        dataActions: [
          'Microsoft.Storage/storageAccounts/blobServices/containers/blobs/read'
        ]
        notDataActions: []
      }
    ]
    assignableScopes: [
      subscription().id
    ]
  }
}

resource dataplaneRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, dataplanePrincipalObjectId, dataplaneRole.id)
  properties: {
    principalId: dataplanePrincipalObjectId
    principalType: 'ServicePrincipal'
    roleDefinitionId: dataplaneRole.id
    condition: dataplaneBlobListOnlyCondition
    conditionVersion: '2.0'
  }
}

// Azure built-in role definition IDs.
var networkContributorRoleId = '4d97b98b-1d4f-4787-a291-c67834d212e7'
var managedIdentityOperatorRoleId = 'f1a07417-d97a-45cb-824c-7a7467783830'
var acrPullRoleId = '7f951dda-4ed3-4680-a7ca-43fe172d538d'
var storageBlobDataOwnerRoleId = 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b'

module dnsRoleAssignment './modules/dns-role-assignment.bicep' = {
  name: 'dataplane-dns-role-assignment'
  scope: resourceGroup(dnsZoneSubscriptionId, dnsZoneResourceGroupName)
  params: {
    dnsZoneName: dnsZoneName
    dnsRoleName: dataplaneDnsRoleName
    principalId: dataplanePrincipalObjectId
  }
}

var controlPlaneIdentityResourceId = resourceId(subscription().subscriptionId, identitiesResourceGroupName, 'Microsoft.ManagedIdentity/userAssignedIdentities', aksControlPlaneIdentityName)
var kubeletIdentityResourceId = resourceId(subscription().subscriptionId, identitiesResourceGroupName, 'Microsoft.ManagedIdentity/userAssignedIdentities', aksKubeletIdentityName)
var networkContributorRoleDefinitionId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', networkContributorRoleId)
resource controlPlaneNetworkRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, controlPlaneIdentityResourceId, networkContributorRoleDefinitionId)
  properties: {
    principalId: dataplaneIdentities.outputs.controlPlanePrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: networkContributorRoleDefinitionId
  }
}


var managedIdentityOperatorRoleDefinitionId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', managedIdentityOperatorRoleId)
module managedIdentityOperatorAssignment './modules/identity-role-assignment.bicep' = {
  name: 'managed-identity-operator-assignment'
  scope: identitiesResourceGroup
  params: {
    identityName: aksKubeletIdentityName
    principalId: dataplaneIdentities.outputs.controlPlanePrincipalId
    roleDefinitionId: managedIdentityOperatorRoleDefinitionId
    assignmentGuidSeed: controlPlaneIdentityResourceId
  }
}


var acrPullRoleDefinitionId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', acrPullRoleId)
module acrPullAssignment './modules/acr-role-assignment.bicep' = {
  name: 'kubelet-acr-pull-assignment'
  scope: resourceGroup(acrSubscriptionId, acrResourceGroupName)
  params: {
    acrName: acrName
    principalId: dataplaneIdentities.outputs.kubeletPrincipalId
    roleDefinitionId: acrPullRoleDefinitionId
    assignmentGuidSeed: kubeletIdentityResourceId
  }
}


var storageBlobDataOwnerRoleDefinitionId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageBlobDataOwnerRoleId)
resource storageBlobDataOwnerAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, kubeletIdentityResourceId, storageBlobDataOwnerRoleDefinitionId)
  properties: {
    principalId: dataplaneIdentities.outputs.kubeletPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: storageBlobDataOwnerRoleDefinitionId
  }
}


output storageResourceGroupName string = storageResourceGroup.name
output identitiesResourceGroupName string = identitiesResourceGroup.name
output auditLogStorageAccountName string = auditLogStorageAccountName
output aksControlPlaneIdentityId string = dataplaneIdentities.outputs.controlPlaneIdentityId
output aksKubeletIdentityId string = dataplaneIdentities.outputs.kubeletIdentityId
output dataplaneRoleDefinitionId string = dataplaneRole.id
