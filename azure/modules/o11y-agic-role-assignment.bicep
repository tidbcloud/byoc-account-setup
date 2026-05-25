targetScope = 'resourceGroup'

param roleName string
param principalId string
param assignmentGuidSeed string

resource agicRole 'Microsoft.Authorization/roleDefinitions@2022-04-01' = {
  name: guid(resourceGroup().id, roleName)
  properties: {
    roleName: roleName
    description: 'Least-privilege role for TiDB Cloud BYOC O11Y Application Gateway Ingress Controller.'
    type: 'CustomRole'
    permissions: [
      {
        actions: [
          'Microsoft.Resources/subscriptions/resourceGroups/read'
          'Microsoft.Network/applicationGateways/*'
          'Microsoft.Network/applicationGatewayWebApplicationFirewallPolicies/read'
          'Microsoft.Network/virtualNetworks/read'
          'Microsoft.Network/virtualNetworks/subnets/read'
          'Microsoft.Network/publicIPAddresses/read'
          'Microsoft.Network/networkInterfaces/read'
          'Microsoft.Network/loadBalancers/read'
        ]
        notActions: [
          'Microsoft.Authorization/roleAssignments/write'
          'Microsoft.Authorization/roleAssignments/delete'
        ]
        dataActions: []
        notDataActions: []
      }
    ]
    assignableScopes: [
      resourceGroup().id
    ]
  }
}

resource agicRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, assignmentGuidSeed, agicRole.id)
  properties: {
    principalId: principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: agicRole.id
  }
}
