param location string

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
