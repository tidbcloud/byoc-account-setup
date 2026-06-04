targetScope = 'subscription'

param roleName string
param principalId string
param assignmentGuidSeed string
param roleGuidSeed string

resource agicRole 'Microsoft.Authorization/roleDefinitions@2022-04-01' = {
  name: guid(roleGuidSeed, roleName)
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
          'Microsoft.Network/applicationGatewayWebApplicationFirewallPolicies/join/action'
          'Microsoft.Network/virtualNetworks/read'
          'Microsoft.Network/virtualNetworks/subnets/read'
          'Microsoft.Network/virtualNetworks/subnets/join/action'
          'Microsoft.Network/publicIPAddresses/read'
          'Microsoft.Network/networkInterfaces/read'
          'Microsoft.Network/loadBalancers/read'
          'Microsoft.Network/routeTables/read'
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
      subscription().id
    ]
  }
}

resource agicRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, assignmentGuidSeed, agicRole.id)
  properties: {
    principalId: principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: agicRole.id
  }
}
