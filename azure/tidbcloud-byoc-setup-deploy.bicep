targetScope = 'subscription'

param deployName string
param location string
param deploymentPrincipalObjectId string
param deploymentResourceGroupName string = 'rg-tidbcloud-${deployName}-deploy'
param acrResourceGroupName string = 'rg-tidbcloud-${deployName}-acr'
param acrName string
param createAcr bool = true

var acrPushRoleDefinitionId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '8311e382-0749-4cb8-b61a-304f252e45ec')
var readerRoleDefinitionId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'acdd72a7-3385-48ef-bd42-f606fba81ae7')
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

module deploymentCreatedAcrPushAssignment './modules/acr-role-assignment.bicep' = if (createAcr) {
  name: 'deployment-created-acr-push-assignment'
  scope: resourceGroup(acrResourceGroupName)
  params: {
    acrName: acrName
    principalId: deploymentPrincipalObjectId
    roleDefinitionId: acrPushRoleDefinitionId
    assignmentGuidSeed: '${deploymentPrincipalObjectId}-acr-push'
  }
  dependsOn: [
    deployResources
  ]
}

module deploymentCreatedAcrReaderAssignment './modules/acr-role-assignment.bicep' = if (createAcr) {
  name: 'deployment-created-acr-reader-assignment'
  scope: resourceGroup(acrResourceGroupName)
  params: {
    acrName: acrName
    principalId: deploymentPrincipalObjectId
    roleDefinitionId: readerRoleDefinitionId
    assignmentGuidSeed: '${deploymentPrincipalObjectId}-acr-reader'
  }
  dependsOn: [
    deployResources
  ]
}

module deploymentExistingAcrPushAssignment './modules/acr-role-assignment.bicep' = if (!createAcr) {
  name: 'deployment-existing-acr-push-assignment'
  scope: resourceGroup(acrResourceGroupName)
  params: {
    acrName: acrName
    principalId: deploymentPrincipalObjectId
    roleDefinitionId: acrPushRoleDefinitionId
    assignmentGuidSeed: '${deploymentPrincipalObjectId}-acr-push'
  }
}

module deploymentExistingAcrReaderAssignment './modules/acr-role-assignment.bicep' = if (!createAcr) {
  name: 'deployment-existing-acr-reader-assignment'
  scope: resourceGroup(acrResourceGroupName)
  params: {
    acrName: acrName
    principalId: deploymentPrincipalObjectId
    roleDefinitionId: readerRoleDefinitionId
    assignmentGuidSeed: '${deploymentPrincipalObjectId}-acr-reader'
  }
}

output deploymentResourceGroupName string = deploymentResourceGroup.name
output acrResourceGroupName string = acrResourceGroupName
output acrId string = acrId
