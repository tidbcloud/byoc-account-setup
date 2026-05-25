param location string
param o11yAksControlPlaneIdentityName string
param o11yAksKubeletIdentityName string

resource regionalServerIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: 'o11y-regional-server'
  location: location
}

resource vmbackupIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: 'o11y-vmbackup'
  location: location
}

resource lokiIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: 'o11y-loki'
  location: location
}

resource veleroIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: 'o11y-velero'
  location: location
}

resource o11yAksControlPlaneIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: o11yAksControlPlaneIdentityName
  location: location
}

resource o11yAksKubeletIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: o11yAksKubeletIdentityName
  location: location
}

resource o11yAgicIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: 'o11y-agic'
  location: location
}

output regionalServerIdentityName string = regionalServerIdentity.name
output regionalServerIdentityId string = regionalServerIdentity.id
output regionalServerPrincipalId string = regionalServerIdentity.properties.principalId
output regionalServerClientId string = regionalServerIdentity.properties.clientId

output vmbackupIdentityName string = vmbackupIdentity.name
output vmbackupIdentityId string = vmbackupIdentity.id
output vmbackupPrincipalId string = vmbackupIdentity.properties.principalId
output vmbackupClientId string = vmbackupIdentity.properties.clientId

output lokiIdentityName string = lokiIdentity.name
output lokiIdentityId string = lokiIdentity.id
output lokiPrincipalId string = lokiIdentity.properties.principalId
output lokiClientId string = lokiIdentity.properties.clientId

output veleroIdentityName string = veleroIdentity.name
output veleroIdentityId string = veleroIdentity.id
output veleroPrincipalId string = veleroIdentity.properties.principalId
output veleroClientId string = veleroIdentity.properties.clientId

output o11yAksControlPlaneIdentityName string = o11yAksControlPlaneIdentity.name
output o11yAksControlPlaneIdentityId string = o11yAksControlPlaneIdentity.id
output o11yAksControlPlanePrincipalId string = o11yAksControlPlaneIdentity.properties.principalId
output o11yAksControlPlaneClientId string = o11yAksControlPlaneIdentity.properties.clientId

output o11yAksKubeletIdentityName string = o11yAksKubeletIdentity.name
output o11yAksKubeletIdentityId string = o11yAksKubeletIdentity.id
output o11yAksKubeletPrincipalId string = o11yAksKubeletIdentity.properties.principalId
output o11yAksKubeletClientId string = o11yAksKubeletIdentity.properties.clientId

output o11yAgicIdentityName string = o11yAgicIdentity.name
output o11yAgicIdentityId string = o11yAgicIdentity.id
output o11yAgicPrincipalId string = o11yAgicIdentity.properties.principalId
output o11yAgicClientId string = o11yAgicIdentity.properties.clientId
