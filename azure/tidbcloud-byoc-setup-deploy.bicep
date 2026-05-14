targetScope = 'subscription'

param customerId string
param location string
param deploymentPrincipalObjectId string
param deploymentResourceGroupName string = 'rg-tidbcloud-${customerId}-deploy'
param acrResourceGroupName string = 'rg-tidbcloud-${customerId}-acr'
param acrName string

var contributorRoleDefinitionId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b24988ac-6180-42a0-ab88-20f7382dd24c')

resource deploymentResourceGroup 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: deploymentResourceGroupName
  location: location
}

resource acrResourceGroup 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: acrResourceGroupName
  location: location
}

module deployResources './modules/deploy-resources.bicep' = {
  name: 'deploy-resources'
  scope: acrResourceGroup
  params: {
    location: location
    acrName: acrName
  }
}

module deploymentAcrContributorAssignment './modules/acr-role-assignment.bicep' = {
  name: 'deployment-acr-contributor-assignment'
  scope: acrResourceGroup
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

output deploymentResourceGroupName string = deploymentResourceGroup.name
output acrResourceGroupName string = acrResourceGroup.name
output acrId string = deployResources.outputs.acrId
