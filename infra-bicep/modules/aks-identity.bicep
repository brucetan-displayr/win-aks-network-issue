// =====================================================
// AKS Identity Module - User Assigned Identity for AKS
// =====================================================

@description('Location for resources')
param location string

@description('Name prefix for resources')
param namePrefix string

@description('AKS private DNS zone ID')
param aksPrivateDnsZoneId string

@description('Resource group ID')
param resourceGroupId string

@description('Resource tags')
param tags object

// =====================================================
// User Assigned Identity
// =====================================================

resource aksIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: '${namePrefix}-aks-identity'
  location: location
  tags: tags
}

// =====================================================
// Role Assignments
// =====================================================

// Private DNS Zone Contributor - for AKS to manage DNS records
resource aksIdentityPrivateDnsZoneContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(aksIdentity.id, aksPrivateDnsZoneId, 'PrivateDnsZoneContributor')
  scope: resourceGroup()
  properties: {
    principalId: aksIdentity.properties.principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b12aa53e-6015-4669-85d0-8515ebb3ae7f') // Private DNS Zone Contributor
    principalType: 'ServicePrincipal'
  }
}

// Network Contributor - for AKS to manage network resources in the resource group
resource aksIdentityNetworkContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(aksIdentity.id, resourceGroupId, 'NetworkContributor')
  scope: resourceGroup()
  properties: {
    principalId: aksIdentity.properties.principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4d97b98b-1d4f-4787-a291-c67834d212e7') // Network Contributor
    principalType: 'ServicePrincipal'
  }
}

// =====================================================
// Outputs
// =====================================================

output identityId string = aksIdentity.id
output identityPrincipalId string = aksIdentity.properties.principalId
output identityClientId string = aksIdentity.properties.clientId
