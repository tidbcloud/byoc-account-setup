targetScope = 'resourceGroup'
param identityName string
param principalId string
param principalType string = 'ServicePrincipal'
param roleDefinitionId string
param assignmentGuidSeed string
resource identity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = { name: identityName }
resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(identity.id, assignmentGuidSeed, roleDefinitionId)
  scope: identity
  properties: {
    principalId: principalId
    principalType: principalType
    roleDefinitionId: roleDefinitionId
  }
}
