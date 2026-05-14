targetScope = 'resourceGroup'
param acrName string
param principalId string
param principalType string = 'ServicePrincipal'
param roleDefinitionId string
param assignmentGuidSeed string
resource acr 'Microsoft.ContainerRegistry/registries@2023-07-01' existing = { name: acrName }
resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(acr.id, assignmentGuidSeed, roleDefinitionId)
  scope: acr
  properties: {
    principalId: principalId
    principalType: principalType
    roleDefinitionId: roleDefinitionId
  }
}
