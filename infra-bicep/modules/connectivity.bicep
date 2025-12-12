// =====================================================
// Connectivity Module - Virtual WAN, Hub, and Shared Services VNet
// =====================================================

@description('Location for resources')
param location string

@description('Name prefix for resources')
param namePrefix string

@description('Hub ID for addressing')
param hubId string

@description('Hub address prefix')
param hubAddressPrefix string

@description('Resource tags')
param tags object

// =====================================================
// Virtual WAN
// =====================================================

resource virtualWan 'Microsoft.Network/virtualWans@2023-11-01' = {
  name: '${namePrefix}-wan'
  location: location
  tags: tags
  properties: {
    type: 'Standard'
    allowBranchToBranchTraffic: true
  }
}

// =====================================================
// Virtual Hub
// =====================================================

resource virtualHub 'Microsoft.Network/virtualHubs@2023-11-01' = {
  name: '${namePrefix}-${location}-hub'
  location: location
  tags: tags
  properties: {
    addressPrefix: hubAddressPrefix
    virtualWan: {
      id: virtualWan.id
    }
    sku: 'Basic'
    allowBranchToBranchTraffic: true
  }
}

// =====================================================
// Hub Route Table
// =====================================================

resource hubRouteTable 'Microsoft.Network/virtualHubs/hubRouteTables@2023-11-01' = {
  parent: virtualHub
  name: 'defaultRouteTable'
  properties: {
    labels: [
      'default'
    ]
    routes: []
  }
}

// =====================================================
// Shared Services Virtual Network
// =====================================================

var sharedServiceVnetCidr = '10.0.0.0/16'
var ilbSubnetCidr = '10.0.0.0/24'
var pipelineSubnetCidr = '10.0.2.0/23'
var dnsForwarderIp = '10.0.0.4'

resource ilbNsg 'Microsoft.Network/networkSecurityGroups@2023-11-01' = {
  name: '${namePrefix}-internal-load-balancer-nsg'
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'AllInboundToDNS'
        properties: {
          access: 'Allow'
          description: 'Allow inbound traffic to DNS'
          destinationAddressPrefix: '*'
          destinationPortRange: '53'
          direction: 'Inbound'
          priority: 100
          protocol: 'Udp'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
        }
      }
      {
        name: 'AllInboundToHTTPS'
        properties: {
          access: 'Allow'
          description: 'Allow inbound traffic to HTTPS'
          destinationAddressPrefix: '*'
          destinationPortRange: '443'
          direction: 'Inbound'
          priority: 101
          protocol: 'Tcp'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
        }
      }
      {
        name: 'DenyInboundToAllPorts'
        properties: {
          access: 'Deny'
          description: 'Deny inbound traffic to all ports'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
          direction: 'Inbound'
          priority: 3072
          protocol: '*'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
        }
      }
    ]
  }
}

resource pipelineNsg 'Microsoft.Network/networkSecurityGroups@2023-11-01' = {
  name: '${namePrefix}-pipeline-nsg'
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'AllowHTTPS'
        properties: {
          access: 'Allow'
          description: 'Allow inbound HTTPS'
          destinationAddressPrefix: '*'
          destinationPortRange: '443'
          direction: 'Inbound'
          priority: 201
          protocol: '*'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
        }
      }
    ]
  }
}

resource sharedServiceVnet 'Microsoft.Network/virtualNetworks@2023-11-01' = {
  name: '${namePrefix}-shared-vnet'
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        sharedServiceVnetCidr
      ]
    }
    subnets: [
      {
        name: 'ilb-subnet'
        properties: {
          addressPrefix: ilbSubnetCidr
          networkSecurityGroup: {
            id: ilbNsg.id
          }
        }
      }
      {
        name: 'pipeline-subnet'
        properties: {
          addressPrefix: pipelineSubnetCidr
          networkSecurityGroup: {
            id: pipelineNsg.id
          }
        }
      }
    ]
  }
}

// =====================================================
// Hub-VNet Connection
// =====================================================

resource sharedServiceHubConnection 'Microsoft.Network/virtualHubs/hubVirtualNetworkConnections@2023-11-01' = {
  parent: virtualHub
  name: '${namePrefix}-shared-vnet-connection'
  properties: {
    remoteVirtualNetwork: {
      id: sharedServiceVnet.id
    }
    allowHubToRemoteVnetTransit: true
    allowRemoteVnetToUseHubVnetGateways: true
    enableInternetSecurity: true
  }
}

// =====================================================
// Outputs
// =====================================================

output virtualWanId string = virtualWan.id
output virtualHubId string = virtualHub.id
output routeTableId string = hubRouteTable.id
output sharedServiceVnetId string = sharedServiceVnet.id
output dnsForwarderIp string = dnsForwarderIp
