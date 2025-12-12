// =====================================================
// Container Registry Module
// =====================================================

@description('Location for resources')
param location string

@description('Name prefix for resources')
param namePrefix string

@description('Resource name prefix for resources')
param resourceNamePrefix string

@description('Resource tags')
param tags object

// =====================================================
// Container Registry
// =====================================================

// Generate a valid ACR name (alphanumeric only, no hyphens)
var acrName = replace(replace('${resourceNamePrefix}acr', '-', ''), '_', '')

resource containerRegistry 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: acrName
  location: location
  tags: tags
  sku: {
    name: 'Premium' // Premium required for private endpoints and geo-replication
  }
  properties: {
    adminUserEnabled: false
    publicNetworkAccess: 'Enabled' // Can be changed to 'Disabled' after private endpoint setup
    networkRuleBypassOptions: 'AzureServices'
    zoneRedundancy: 'Enabled'
  }
}

// =====================================================
// Outputs
// =====================================================

output registryId string = containerRegistry.id
output registryName string = containerRegistry.name
output loginServer string = containerRegistry.properties.loginServer
