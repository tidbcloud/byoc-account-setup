targetScope = 'resourceGroup'
param principalId string
param principalType string = 'ServicePrincipal'
param roleDefinitionId string
param assignmentGuidSeed string
resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, assignmentGuidSeed, roleDefinitionId)
  properties: {
    principalId: principalId
    principalType: principalType
    roleDefinitionId: roleDefinitionId
  }
}
