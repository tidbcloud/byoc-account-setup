targetScope = 'resourceGroup'

param dnsZoneName string
param dnsRoleName string
param principalId string

resource dnsRecordRole 'Microsoft.Authorization/roleDefinitions@2022-04-01' = {
  name: guid(resourceGroup().id, dnsRoleName)
  properties: {
    roleName: dnsRoleName
    description: 'Least-privilege role for TiDB Cloud BYOC dataplane DNS A record management.'
    type: 'CustomRole'
    permissions: [
      {
        actions: [
          'Microsoft.Network/dnsZones/read'
          'Microsoft.Network/dnsZones/A/read'
          'Microsoft.Network/dnsZones/A/write'
          'Microsoft.Network/dnsZones/A/delete'
        ]
        notActions: []
        dataActions: []
        notDataActions: []
      }
    ]
    assignableScopes: [
      resourceGroup().id
    ]
  }
}

resource dnsZone 'Microsoft.Network/dnsZones@2018-05-01' existing = {
  name: dnsZoneName
}

resource dnsRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(dnsZone.id, principalId, dnsRecordRole.id)
  scope: dnsZone
  properties: {
    principalId: principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: dnsRecordRole.id
  }
}
