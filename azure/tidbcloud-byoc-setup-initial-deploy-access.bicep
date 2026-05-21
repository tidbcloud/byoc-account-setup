targetScope = 'subscription'

param deploymentPrincipalObjectId string

// Azure built-in Contributor role. This is temporary and is revoked by
// deleting the initial deploy access stack after the first BYOC deployment.
var contributorRoleDefinitionId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b24988ac-6180-42a0-ab88-20f7382dd24c')

resource initialDeploymentContributorAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, deploymentPrincipalObjectId, contributorRoleDefinitionId)
  properties: {
    principalId: deploymentPrincipalObjectId
    roleDefinitionId: contributorRoleDefinitionId
    principalType: 'ServicePrincipal'
  }
}

output initialDeploymentRoleName string = 'Contributor'
output initialDeploymentRoleDefinitionId string = contributorRoleDefinitionId
