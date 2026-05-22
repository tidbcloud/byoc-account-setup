targetScope = 'subscription'

param deployName string
param location string
param deploymentPrincipalObjectId string
param deploymentResourceGroupName string = 'rg-tidbcloud-${deployName}-deploy'
param acrResourceGroupName string = 'rg-tidbcloud-${deployName}-acr'
param acrName string
param createAcr bool = true

var contributorRoleDefinitionId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b24988ac-6180-42a0-ab88-20f7382dd24c')
var acrId = resourceId(subscription().subscriptionId, acrResourceGroupName, 'Microsoft.ContainerRegistry/registries', acrName)

resource deploymentResourceGroup 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: deploymentResourceGroupName
  location: location
}

resource acrResourceGroup 'Microsoft.Resources/resourceGroups@2024-03-01' = if (createAcr) {
  name: acrResourceGroupName
  location: location
}

module deployResources './modules/deploy-resources.bicep' = if (createAcr) {
  name: 'deploy-resources'
  scope: resourceGroup(acrResourceGroupName)
  params: {
    location: location
    acrName: acrName
  }
  dependsOn: [
    acrResourceGroup
  ]
}

module deploymentCreatedAcrContributorAssignment './modules/acr-role-assignment.bicep' = if (createAcr) {
  name: 'deployment-created-acr-contributor-assignment'
  scope: resourceGroup(acrResourceGroupName)
  params: {
    acrName: acrName
    principalId: deploymentPrincipalObjectId
    roleDefinitionId: contributorRoleDefinitionId
    assignmentGuidSeed: '${deploymentPrincipalObjectId}-acr-contributor'
  }
  dependsOn: [
    deployResources
  ]
}

module deploymentExistingAcrContributorAssignment './modules/acr-role-assignment.bicep' = if (!createAcr) {
  name: 'deployment-existing-acr-contributor-assignment'
  scope: resourceGroup(acrResourceGroupName)
  params: {
    acrName: acrName
    principalId: deploymentPrincipalObjectId
    roleDefinitionId: contributorRoleDefinitionId
    assignmentGuidSeed: '${deploymentPrincipalObjectId}-acr-contributor'
  }
}

output deploymentResourceGroupName string = deploymentResourceGroup.name
output acrResourceGroupName string = acrResourceGroupName
output acrId string = acrId
