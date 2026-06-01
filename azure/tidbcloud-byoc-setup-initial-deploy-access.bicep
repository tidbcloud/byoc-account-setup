targetScope = 'subscription'

param deploymentPrincipalObjectId string
param o11yDnsZoneSubscriptionId string
param o11yDnsZoneResourceGroupName string
param o11yDnsZoneName string

// Azure built-in Contributor role. This is temporary and is revoked by
// deleting the initial deploy access stack after the first BYOC deployment.
var contributorRoleDefinitionId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b24988ac-6180-42a0-ab88-20f7382dd24c')
// Azure built-in DNS Zone Contributor role. This is temporary O11Y DNS access
// and is revoked with the initial deploy access stack.
var dnsZoneContributorRoleDefinitionId = subscriptionResourceId(o11yDnsZoneSubscriptionId, 'Microsoft.Authorization/roleDefinitions', 'befefa01-2a29-4197-83a8-272ff33ce314')

resource initialDeploymentContributorAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, deploymentPrincipalObjectId, contributorRoleDefinitionId)
  properties: {
    principalId: deploymentPrincipalObjectId
    roleDefinitionId: contributorRoleDefinitionId
    principalType: 'ServicePrincipal'
  }
}

module o11yDnsZoneContributorAssignment './modules/dns-zone-role-assignment.bicep' = {
  name: 'o11y-dns-zone-contributor-assignment'
  scope: resourceGroup(o11yDnsZoneSubscriptionId, o11yDnsZoneResourceGroupName)
  params: {
    dnsZoneName: o11yDnsZoneName
    principalId: deploymentPrincipalObjectId
    roleDefinitionId: dnsZoneContributorRoleDefinitionId
  }
}

output initialDeploymentRoleName string = 'Contributor'
output initialDeploymentRoleDefinitionId string = contributorRoleDefinitionId
output o11yDnsRoleName string = 'DNS Zone Contributor'
output o11yDnsRoleDefinitionId string = dnsZoneContributorRoleDefinitionId
