targetScope = 'resourceGroup'

param dnsZoneName string
param principalId string
param roleDefinitionId string
param roleAssignmentName string = ''

resource dnsZone 'Microsoft.Network/dnsZones@2018-05-01' existing = {
  name: dnsZoneName
}

resource dnsZoneRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: roleAssignmentName != '' ? roleAssignmentName : guid(dnsZone.id, principalId, roleDefinitionId)
  scope: dnsZone
  properties: {
    principalId: principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: roleDefinitionId
  }
}
