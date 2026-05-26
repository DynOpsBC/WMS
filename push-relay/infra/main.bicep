param location string = resourceGroup().location
param appName string

resource storage 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: toLower('${appName}st')
  location: location
  sku: { name: 'Standard_LRS' }
  kind: 'StorageV2'
}

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: '${appName}-appi'
  location: location
  kind: 'web'
  properties: { Application_Type: 'web' }
}

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: '${appName}-kv'
  location: location
  properties: {
    tenantId: tenant().tenantId
    sku: {
      family: 'A'
      name: 'standard'
    }
    enableRbacAuthorization: true
  }
}

resource signalr 'Microsoft.SignalRService/webPubSub@2023-02-01' = {
  name: '${appName}-wps'
  location: location
  sku: {
    name: 'Standard_S1'
    capacity: 1
  }
  properties: {
    disableAadAuth: false
    disableLocalAuth: false
  }
}

resource plan 'Microsoft.Web/serverfarms@2023-01-01' = {
  name: '${appName}-premium-plan'
  location: location
  sku: {
    name: 'EP1'
    tier: 'ElasticPremium'
    capacity: 1
  }
}

resource functionApp 'Microsoft.Web/sites@2023-01-01' = {
  name: appName
  location: location
  kind: 'functionapp,linux'
  properties: {
    serverFarmId: plan.id
    siteConfig: {
      linuxFxVersion: 'Node|20'
      appSettings: [
        { name: 'FUNCTIONS_EXTENSION_VERSION'; value: '~4' }
        { name: 'FUNCTIONS_WORKER_RUNTIME'; value: 'node' }
        { name: 'AzureWebJobsStorage'; value: 'DefaultEndpointsProtocol=https;AccountName=${storage.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storage.listKeys().keys[0].value}' }
        { name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'; value: appInsights.properties.ConnectionString }
        { name: 'AzureSignalRConnectionString'; value: signalr.listKeys().primaryConnectionString }
        { name: 'TENANT_CONFIG_JSON'; value: '@Microsoft.KeyVault(SecretUri=${keyVault.properties.vaultUri}secrets/tenant-config/)' }
      ]
    }
    httpsOnly: true
  }
}

output functionAppName string = functionApp.name
output signalRName string = signalr.name
output keyVaultName string = keyVault.name
