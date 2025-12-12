// =====================================================
// DNS Zones Module - Private DNS Zones for AKS and Private Endpoints
// =====================================================

@description('Location for DNS zones (global)')
param location string

@description('Environment')
param environment string

@description('Azure region full name')
param region string

@description('Region abbreviation')
param regionAbbreviation string

@description('Shared service VNet ID')
param sharedServiceVnetId string

@description('Spoke VNet ID')
param spokeVnetId string

@description('Resource tags')
param tags object

// =====================================================
// AKS Private DNS Zone
// =====================================================

resource aksPrivateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: '${environment}.privatelink.${region}.azmk8s.io'
  location: location
  tags: tags
}

// Link to Shared Service VNet (for connectivity/pipeline access)
resource aksPrivateDnsZoneSharedLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: aksPrivateDnsZone
  name: 'shared-service-vnet-link-${environment}-${regionAbbreviation}'
  location: location
  tags: tags
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: sharedServiceVnetId
    }
  }
}

// Link to Spoke VNet
resource aksPrivateDnsZoneSpokeLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: aksPrivateDnsZone
  name: 'spoke-vnet-link-${environment}-${regionAbbreviation}'
  location: location
  tags: tags
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: spokeVnetId
    }
  }
}

// =====================================================
// Private Endpoint DNS Zones (Common Azure Services)
// =====================================================

// Key Vault DNS Zone
resource keyVaultPrivateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.vaultcore.azure.net'
  location: location
  tags: tags
}

resource keyVaultPrivateDnsZoneSharedLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: keyVaultPrivateDnsZone
  name: 'shared-service-vnet-link'
  location: location
  tags: tags
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: sharedServiceVnetId
    }
  }
}

resource keyVaultPrivateDnsZoneSpokeLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: keyVaultPrivateDnsZone
  name: 'spoke-vnet-link'
  location: location
  tags: tags
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: spokeVnetId
    }
  }
}

// Storage Blob DNS Zone
resource storageBlobPrivateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.blob.${az.environment().suffixes.storage}'
  location: location
  tags: tags
}

resource storageBlobPrivateDnsZoneSharedLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: storageBlobPrivateDnsZone
  name: 'shared-service-vnet-link'
  location: location
  tags: tags
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: sharedServiceVnetId
    }
  }
}

resource storageBlobPrivateDnsZoneSpokeLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: storageBlobPrivateDnsZone
  name: 'spoke-vnet-link'
  location: location
  tags: tags
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: spokeVnetId
    }
  }
}

// Container Registry DNS Zone
resource acrPrivateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.azurecr.io'
  location: location
  tags: tags
}

resource acrPrivateDnsZoneSharedLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: acrPrivateDnsZone
  name: 'shared-service-vnet-link'
  location: location
  tags: tags
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: sharedServiceVnetId
    }
  }
}

resource acrPrivateDnsZoneSpokeLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: acrPrivateDnsZone
  name: 'spoke-vnet-link'
  location: location
  tags: tags
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: spokeVnetId
    }
  }
}

// =====================================================
// Outputs
// =====================================================

output aksPrivateDnsZoneId string = aksPrivateDnsZone.id
output keyVaultPrivateDnsZoneId string = keyVaultPrivateDnsZone.id
output storageBlobPrivateDnsZoneId string = storageBlobPrivateDnsZone.id
output acrPrivateDnsZoneId string = acrPrivateDnsZone.id
