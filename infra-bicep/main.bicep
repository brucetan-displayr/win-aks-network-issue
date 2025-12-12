// =====================================================
// Azure Windows AKS Cluster with Hub-Spoke Networking
// =====================================================
// This Bicep template recreates the Windows AKS cluster setup from windows-aks-resource.ts
// including all networking components (vWAN, Hub, Spoke VNet, DNS zones, etc.)

targetScope = 'subscription'

// =====================================================
// Parameters
// =====================================================

@description('Environment name (dev, lab, rc, prod)')
@allowed(['dev', 'lab', 'rc', 'prod'])
param environment string = 'dev'

@description('Primary Azure region abbreviation')
@allowed(['eus', 'aue', 'cnc', 'sea', 'weu'])
param regionAbbreviation string = 'eus'

@description('Spoke ID (e.g., 101, 102, etc.)')
param spokeId string = '999'

@description('Platform Engineers AD Group Object ID')
param platformEngineersGroupId string

@description('Tenant ID for Azure AD authentication')
param tenantId string = subscription().tenantId

@description('SSH Public Key for AKS Linux nodes')
@secure()
param sshPublicKey string

@description('Kubernetes version')
param kubernetesVersion string = '1.33.3'

// =====================================================
// Variables
// =====================================================

var platformNamePrefix = 'dip'
var regionMapping = {
  eus: 'eastus'
  aue: 'australiaeast'
  cnc: 'canadacentral'
  sea: 'southeastasia'
  weu: 'westeurope'
}
var primaryLocation = regionMapping[regionAbbreviation]

// Naming conventions
var connectivityNamePrefix = '${platformNamePrefix}-connectivity'
var spokeNamePrefix = '${platformNamePrefix}-${regionAbbreviation}-${spokeId}'
var spokeResourceNamePrefix = '${platformNamePrefix}-${environment}-${regionAbbreviation}-${spokeId}'

// Resource Group Names
var connectivityRgName = '${connectivityNamePrefix}-rg'
var spokeRgName = '${spokeResourceNamePrefix}-rg'

// Hub Configuration
var hubId = '201' // Base hub ID, adjust based on region index if needed
var hubAddressPrefix = '10.${hubId}.0.0/23'

// Spoke VNet Configuration
var addressId = int(spokeId) + 5 // TransitVNetCidrOffset = 5
var spokeAddressSpace = '10.${addressId}.0.0/16'
var aksSubnetCidr = '10.${addressId}.128.0/17'
var ilbSubnetCidr = '10.${addressId}.3.0/24'
var ilbSubnetIp = '10.${addressId}.3.10'

// AKS Configuration
var aksServiceCidr = '10.0.192.0/18'
var aksDnsServiceIP = '10.0.192.10'
var overlayPodCidr = '10.244.0.0/16'

// Istio Configuration
var istioRevisions = ['asm-1-26']
var istioRevisionIndex = 0

// Tags
var defaultTags = {
  Environment: environment
  ManagedBy: 'Bicep'
  Service: '${platformNamePrefix}-spoke'
  Dip: 'spoke'
  Spoke: spokeId
  Location: primaryLocation
}

// =====================================================
// Resource Groups
// =====================================================

resource connectivityRg 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: connectivityRgName
  location: primaryLocation
  tags: defaultTags
}

resource spokeRg 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: spokeRgName
  location: primaryLocation
  tags: defaultTags
}

// =====================================================
// Connectivity Resources (Hub-Spoke Networking)
// =====================================================

module connectivityResources './modules/connectivity.bicep' = {
  name: 'connectivity-deployment'
  scope: connectivityRg
  params: {
    location: primaryLocation
    namePrefix: connectivityNamePrefix
    hubId: hubId
    hubAddressPrefix: hubAddressPrefix
    tags: defaultTags
  }
}

// =====================================================
// Spoke Networking Resources
// =====================================================

module spokeNetworking './modules/spoke-networking.bicep' = {
  name: 'spoke-networking-deployment'
  scope: spokeRg
  params: {
    location: primaryLocation
    namePrefix: spokeNamePrefix
    resourceNamePrefix: spokeResourceNamePrefix
    spokeAddressSpace: spokeAddressSpace
    aksSubnetCidr: aksSubnetCidr
    ilbSubnetCidr: ilbSubnetCidr
    overlayPodCidr: overlayPodCidr
    aksServiceCidr: aksServiceCidr
    virtualWanId: connectivityResources.outputs.virtualWanId
    virtualHubId: connectivityResources.outputs.virtualHubId
    routeTableId: connectivityResources.outputs.routeTableId
    tags: defaultTags
    environment: environment
  }
}

// =====================================================
// Private DNS Zones
// =====================================================

module dnsZones './modules/dns-zones.bicep' = {
  name: 'dns-zones-deployment'
  scope: connectivityRg
  params: {
    location: 'global'
    environment: environment
    region: primaryLocation
    regionAbbreviation: regionAbbreviation
    sharedServiceVnetId: connectivityResources.outputs.sharedServiceVnetId
    spokeVnetId: spokeNetworking.outputs.vnetId
    tags: defaultTags
  }
}

// =====================================================
// User Assigned Identity for AKS
// =====================================================

module aksIdentity './modules/aks-identity.bicep' = {
  name: 'aks-identity-deployment'
  scope: spokeRg
  params: {
    location: primaryLocation
    namePrefix: spokeNamePrefix
    aksPrivateDnsZoneId: dnsZones.outputs.aksPrivateDnsZoneId
    resourceGroupId: spokeRg.id
    tags: defaultTags
  }
}

// =====================================================
// Container Registries
// =====================================================

module containerRegistry './modules/container-registry.bicep' = {
  name: 'container-registry-deployment'
  scope: spokeRg
  params: {
    location: primaryLocation
    namePrefix: spokeNamePrefix
    resourceNamePrefix: spokeResourceNamePrefix
    tags: defaultTags
  }
}

// =====================================================
// Windows AKS Cluster
// =====================================================

module windowsAks './modules/windows-aks.bicep' = {
  name: 'windows-aks-deployment'
  scope: spokeRg
  params: {
    location: primaryLocation
    namePrefix: spokeNamePrefix
    resourceNamePrefix: spokeResourceNamePrefix
    subnetId: spokeNetworking.outputs.aksSubnetId
    identityId: aksIdentity.outputs.identityId
    privateDnsZoneId: dnsZones.outputs.aksPrivateDnsZoneId
    serviceCidr: aksServiceCidr
    dnsServiceIP: aksDnsServiceIP
    kubernetesVersion: kubernetesVersion
    sshPublicKey: sshPublicKey
    tenantId: tenantId
    platformEngineersGroupId: platformEngineersGroupId
    istioRevisions: istioRevisions
    tags: defaultTags
    environment: environment
  }
}

// =====================================================
// Role Assignments
// =====================================================

module roleAssignments './modules/role-assignments.bicep' = {
  name: 'role-assignments-deployment'
  scope: spokeRg
  params: {
    aksClusterId: windowsAks.outputs.clusterId
    aksKubeletIdentityObjectId: windowsAks.outputs.kubeletIdentityObjectId
    sharedRegistryId: containerRegistry.outputs.registryId
    connRegistryId: containerRegistry.outputs.registryId // In this template, using same registry
    platformEngineersGroupId: platformEngineersGroupId
  }
}

// =====================================================
// Outputs
// =====================================================

output spokeResourceGroupName string = spokeRg.name
output connectivityResourceGroupName string = connectivityRg.name

output virtualWanId string = connectivityResources.outputs.virtualWanId
output virtualHubId string = connectivityResources.outputs.virtualHubId
output spokeVnetId string = spokeNetworking.outputs.vnetId
output aksSubnetId string = spokeNetworking.outputs.aksSubnetId

output aksClusterId string = windowsAks.outputs.clusterId
output aksClusterName string = windowsAks.outputs.clusterName
output aksIdentityId string = aksIdentity.outputs.identityId
output aksPrivateDnsZoneId string = dnsZones.outputs.aksPrivateDnsZoneId

output containerRegistryId string = containerRegistry.outputs.registryId
output containerRegistryLoginServer string = containerRegistry.outputs.loginServer
