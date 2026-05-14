param location string
param aksControlPlaneIdentityName string
param aksKubeletIdentityName string

resource controlPlaneIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: aksControlPlaneIdentityName
  location: location
}

resource kubeletIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: aksKubeletIdentityName
  location: location
}

output controlPlaneIdentityId string = controlPlaneIdentity.id
output controlPlanePrincipalId string = controlPlaneIdentity.properties.principalId
output kubeletIdentityId string = kubeletIdentity.id
output kubeletPrincipalId string = kubeletIdentity.properties.principalId
