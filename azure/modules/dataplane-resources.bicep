param location string
param auditLogStorageAccountName string
param auditLogContainerName string

resource auditStorage 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: auditLogStorageAccountName
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    minimumTlsVersion: 'TLS1_2'
  }
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: auditStorage
  name: 'default'
}

resource auditContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobService
  name: auditLogContainerName
  properties: {
    publicAccess: 'None'
  }
}
