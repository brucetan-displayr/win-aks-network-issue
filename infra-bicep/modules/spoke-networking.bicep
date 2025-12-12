// =====================================================
// Spoke Networking Module - VNet, Subnets, NSGs
// =====================================================

@description('Location for resources')
param location string

@description('Name prefix for resources')
param namePrefix string

@description('Resource name prefix for resources')
param resourceNamePrefix string

@description('Spoke VNet address space')
param spokeAddressSpace string

@description('AKS subnet CIDR')
param aksSubnetCidr string

@description('Internal load balancer subnet CIDR')
param ilbSubnetCidr string

@description('Overlay pod CIDR')
param overlayPodCidr string

@description('AKS service CIDR')
param aksServiceCidr string

@description('Virtual WAN ID')
param virtualWanId string

@description('Virtual Hub ID')
param virtualHubId string

@description('Route Table ID')
param routeTableId string

@description('Resource tags')
param tags object

@description('Environment')
param environment string

// =====================================================
// Network Security Groups
// =====================================================

resource aksNsg 'Microsoft.Network/networkSecurityGroups@2023-11-01' = {
  name: '${namePrefix}-aks-nsg'
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
      {
        name: 'AllowDNSInBound'
        properties: {
          access: 'Allow'
          description: 'Allow inbound traffic for DNS'
          destinationAddressPrefix: 'VirtualNetwork'
          destinationPortRange: '53'
          direction: 'Inbound'
          priority: 211
          protocol: 'Udp'
          sourceAddressPrefix: 'VirtualNetwork'
          sourcePortRange: '*'
        }
      }
      {
        name: 'AllowInboundILBHealthCheck'
        properties: {
          access: 'Allow'
          description: 'Allow Gateway Health checks from ILB subnet'
          destinationAddressPrefix: aksSubnetCidr
          destinationPortRange: '15021'
          direction: 'Inbound'
          priority: 260
          protocol: '*'
          sourceAddressPrefix: ilbSubnetCidr
          sourcePortRange: '*'
        }
      }
      {
        name: 'AllowInboundK8sServices'
        properties: {
          access: 'Allow'
          description: 'Allow inbound traffic to K8s services'
          destinationAddressPrefix: aksServiceCidr
          destinationPortRange: '*'
          direction: 'Inbound'
          priority: 301
          protocol: 'Tcp'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
        }
      }
      {
        name: 'AllowNodePort'
        properties: {
          access: 'Allow'
          description: 'Allow accessing K8s NodePort ranges'
          destinationAddressPrefix: aksSubnetCidr
          destinationPortRange: '30000-32767'
          direction: 'Inbound'
          priority: 311
          protocol: '*'
          sourceAddressPrefix: 'VirtualNetwork'
          sourcePortRange: '*'
        }
      }
      {
        name: 'AllowPodToPodInbound'
        properties: {
          access: 'Allow'
          description: 'Allow pod to pod communication'
          destinationAddressPrefix: overlayPodCidr
          destinationPortRange: '*'
          direction: 'Inbound'
          priority: 401
          protocol: '*'
          sourceAddressPrefix: overlayPodCidr
          sourcePortRange: '*'
        }
      }
      {
        name: 'AllowNodeToNodeInbound'
        properties: {
          access: 'Allow'
          description: 'Allow node to node communication'
          destinationAddressPrefix: aksSubnetCidr
          destinationPortRange: '*'
          direction: 'Inbound'
          priority: 402
          protocol: '*'
          sourceAddressPrefix: aksSubnetCidr
          sourcePortRange: '*'
        }
      }
      {
        name: 'AllowNodeToPodInbound'
        properties: {
          access: 'Allow'
          description: 'Allow node to pod communication'
          destinationAddressPrefix: overlayPodCidr
          destinationPortRange: '*'
          direction: 'Inbound'
          priority: 403
          protocol: '*'
          sourceAddressPrefix: aksSubnetCidr
          sourcePortRange: '*'
        }
      }
    ]
  }
}

resource ilbNsg 'Microsoft.Network/networkSecurityGroups@2023-11-01' = {
  name: '${namePrefix}-ilb-nsg'
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
          priority: 100
          protocol: 'Tcp'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
        }
      }
      {
        name: 'AllowHTTP'
        properties: {
          access: 'Allow'
          description: 'Allow inbound HTTP'
          destinationAddressPrefix: '*'
          destinationPortRange: '80'
          direction: 'Inbound'
          priority: 101
          protocol: 'Tcp'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
        }
      }
    ]
  }
}

// =====================================================
// Virtual Network
// =====================================================

resource spokeVnet 'Microsoft.Network/virtualNetworks@2023-11-01' = {
  name: '${resourceNamePrefix}-vnet'
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        spokeAddressSpace
      ]
    }
    subnets: [
      {
        name: 'aks-subnet'
        properties: {
          addressPrefix: aksSubnetCidr
          networkSecurityGroup: {
            id: aksNsg.id
          }
          privateEndpointNetworkPolicies: 'Disabled'
        }
      }
      {
        name: 'ilb-subnet'
        properties: {
          addressPrefix: ilbSubnetCidr
          networkSecurityGroup: {
            id: ilbNsg.id
          }
        }
      }
    ]
  }
}

// =====================================================
// Hub Connection
// =====================================================

resource hubConnection 'Microsoft.Network/virtualHubs/hubVirtualNetworkConnections@2023-11-01' = {
  name: '${split(virtualHubId, '/')[8]}/spoke-${resourceNamePrefix}-connection'
  properties: {
    remoteVirtualNetwork: {
      id: spokeVnet.id
    }
    allowHubToRemoteVnetTransit: true
    allowRemoteVnetToUseHubVnetGateways: true
    enableInternetSecurity: true
    routingConfiguration: {
      associatedRouteTable: {
        id: routeTableId
      }
      propagatedRouteTables: {
        labels: [
          environment
        ]
        ids: [
          {
            id: routeTableId
          }
        ]
      }
    }
  }
}

// =====================================================
// Outputs
// =====================================================

output vnetId string = spokeVnet.id
output aksSubnetId string = '${spokeVnet.id}/subnets/aks-subnet'
output ilbSubnetId string = '${spokeVnet.id}/subnets/ilb-subnet'
output vnetName string = spokeVnet.name
