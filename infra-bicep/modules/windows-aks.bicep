// =====================================================
// Windows AKS Cluster Module
// =====================================================

@description('Location for resources')
param location string

@description('Name prefix for resources')
param namePrefix string

@description('Resource name prefix for resources')
param resourceNamePrefix string

@description('AKS subnet ID')
param subnetId string

@description('User assigned identity ID for AKS')
param identityId string

@description('Private DNS zone ID for AKS')
param privateDnsZoneId string

@description('Kubernetes service CIDR')
param serviceCidr string

@description('Kubernetes DNS service IP')
param dnsServiceIP string

@description('Kubernetes version')
param kubernetesVersion string

@description('SSH public key for Linux nodes')
@secure()
param sshPublicKey string

@description('Tenant ID')
param tenantId string

@description('Platform Engineers Group ID')
param platformEngineersGroupId string

@description('Istio revisions')
param istioRevisions array

@description('Resource tags')
param tags object

@description('Environment')
param environment string

// =====================================================
// Variables
// =====================================================

var clusterName = '${resourceNamePrefix}-win-aks'
var nodeResourceGroupName = '${resourceNamePrefix}-win-aks-resource-rg'
var defaultMaxSurge = '2'

// =====================================================
// AKS Cluster
// =====================================================

resource aksCluster 'Microsoft.ContainerService/managedClusters@2024-09-02-preview' = {
  name: clusterName
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${identityId}': {}
    }
  }
  sku: {
    name: 'Base'
    tier: environment == 'prod' ? 'Standard' : 'Free'
  }
  properties: {
    kubernetesVersion: kubernetesVersion
    dnsPrefix: '${namePrefix}-win-aks-dns'
    enableRBAC: true
    disableLocalAccounts: true
    
    // Azure AD Integration
    aadProfile: {
      enableAzureRBAC: true
      managed: true
      adminGroupObjectIDs: [platformEngineersGroupId]
      tenantID: tenantId
    }
    
    // API Server Access Profile (Private Cluster)
    apiServerAccessProfile: {
      enablePrivateCluster: true
      privateDNSZone: privateDnsZoneId
      enablePrivateClusterPublicFQDN: false
    }
    
    // Network Profile - Azure CNI Overlay
    networkProfile: {
      networkPlugin: 'azure'
      networkPluginMode: 'overlay'
      networkPolicy: 'calico'
      networkDataplane: 'azure'
      loadBalancerSku: 'standard'
      outboundType: 'loadBalancer'
      serviceCidr: serviceCidr
      dnsServiceIP: dnsServiceIP
      loadBalancerProfile: {
        managedOutboundIPs: {
          count: 1
        }
      }
    }
    
    // Linux Profile (even for Windows cluster, need for system pools)
    linuxProfile: {
      adminUsername: 'dip-user'
      ssh: {
        publicKeys: [
          {
            keyData: sshPublicKey
          }
        ]
      }
    }
    
    // Node Resource Group
    nodeResourceGroup: nodeResourceGroupName
    
    // OIDC Issuer
    oidcIssuerProfile: {
      enabled: true
    }
    
    // Workload Identity
    securityProfile: {
      workloadIdentity: {
        enabled: true
      }
    }
    
    // Service Mesh (Istio)
    serviceMeshProfile: {
      mode: 'Istio'
      istio: {
        components: {
          ingressGateways: [
            {
              enabled: true
              mode: 'External'
            }
          ]
        }
        revisions: istioRevisions
      }
    }
    
    // Workload Autoscaler (KEDA)
    workloadAutoScalerProfile: {
      keda: {
        enabled: true
      }
    }
    
    // Autoscaler Profile
    autoScalerProfile: {
      'max-graceful-termination-sec': '1800'
      'daemonset-eviction-for-empty-nodes': true
      'daemonset-eviction-for-occupied-nodes': true
    }
    
    // Auto Upgrade Profile
    autoUpgradeProfile: {
      nodeOSUpgradeChannel: 'NodeImage'
      upgradeChannel: 'none'
    }
    
    // Add-on Profiles
    addonProfiles: {
      azureKeyvaultSecretsProvider: {
        enabled: true
        config: {
          enableSecretRotation: 'true'
        }
      }
      azurepolicy: {
        enabled: true
        config: {
          version: 'v2'
        }
      }
    }
    
    // Agent Pool Profiles - Only if first deployment
    agentPoolProfiles: [
      {
        name: 'tempsystem'
        count: 1
        minCount: 1
        maxCount: 1
        enableAutoScaling: true
        vmSize: 'Standard_E4ads_v5'
        osType: 'Linux'
        osDiskType: 'Ephemeral'
        osDiskSizeGB: 150
        type: 'VirtualMachineScaleSets'
        mode: 'System'
        maxPods: 250
        vnetSubnetID: subnetId
        availabilityZones: ['1', '2', '3']
        orchestratorVersion: kubernetesVersion
        nodeTaints: ['CriticalAddonsOnly=true:NoSchedule']
        upgradeSettings: {
          maxSurge: defaultMaxSurge
        }
      }
    ]
  }
}

// =====================================================
// Agent Pools
// =====================================================

// User Pool - Linux (Example)
resource userPoolLinux 'Microsoft.ContainerService/managedClusters/agentPools@2024-09-02-preview' = {
  parent: aksCluster
  name: 'userlinux'
  properties: {
    count: 2
    minCount: 2
    maxCount: 10
    enableAutoScaling: true
    vmSize: 'Standard_D4ads_v5'
    osType: 'Linux'
    osDiskType: 'Ephemeral'
    osDiskSizeGB: 150
    type: 'VirtualMachineScaleSets'
    mode: 'User'
    maxPods: 250
    vnetSubnetID: subnetId
    availabilityZones: ['1', '2', '3']
    orchestratorVersion: kubernetesVersion
    upgradeSettings: {
      maxSurge: defaultMaxSurge
    }
    nodeLabels: {
      'workload-type': 'general'
    }
  }
}

// User Pool - Windows (Example)
resource userPoolWindows 'Microsoft.ContainerService/managedClusters/agentPools@2024-09-02-preview' = {
  parent: aksCluster
  name: 'win01'
  properties: {
    count: 2
    minCount: 2
    maxCount: 10
    enableAutoScaling: true
    vmSize: 'Standard_D8ads_v5'
    osType: 'Windows'
    osDiskType: 'Ephemeral'
    osDiskSizeGB: 256
    type: 'VirtualMachineScaleSets'
    mode: 'User'
    maxPods: 30 // Windows pods typically need more resources
    vnetSubnetID: subnetId
    availabilityZones: ['1', '2', '3']
    orchestratorVersion: kubernetesVersion
    upgradeSettings: {
      maxSurge: defaultMaxSurge
    }
    nodeLabels: {
      'workload-type': 'windows'
      'kubernetes.io/os': 'windows'
    }
  }
}

// Additional Windows Pool (Second example as requested)
resource userPoolWindows2 'Microsoft.ContainerService/managedClusters/agentPools@2024-09-02-preview' = {
  parent: aksCluster
  name: 'win02'
  properties: {
    count: 1
    minCount: 1
    maxCount: 5
    enableAutoScaling: true
    vmSize: 'Standard_D4ads_v5'
    osType: 'Windows'
    osDiskType: 'Ephemeral'
    osDiskSizeGB: 256
    type: 'VirtualMachineScaleSets'
    mode: 'User'
    maxPods: 30
    vnetSubnetID: subnetId
    availabilityZones: ['1', '2', '3']
    orchestratorVersion: kubernetesVersion
    upgradeSettings: {
      maxSurge: defaultMaxSurge
    }
    nodeLabels: {
      'workload-type': 'windows-batch'
      'kubernetes.io/os': 'windows'
    }
  }
}

// =====================================================
// Maintenance Configuration
// =====================================================

resource maintenanceConfig 'Microsoft.ContainerService/managedClusters/maintenanceConfigurations@2024-09-02-preview' = {
  parent: aksCluster
  name: 'aksManagedNodeOSUpgradeSchedule'
  properties: {
    maintenanceWindow: {
      schedule: {
        weekly: {
          dayOfWeek: environment == 'prod' ? 'Wednesday' : 'Monday'
          intervalWeeks: 1
        }
      }
      durationHours: 6
      startTime: environment == 'prod' ? '10:00' : '01:00'
      utcOffset: '+10:00'
    }
  }
}

// =====================================================
// AKS Extensions
// =====================================================

// App Configuration Kubernetes Provider Extension
resource appConfigExtension 'Microsoft.KubernetesConfiguration/extensions@2023-05-01' = {
  name: 'appconfigurationkubernetesprovider'
  scope: aksCluster
  properties: {
    extensionType: 'Microsoft.AppConfiguration'
    autoUpgradeMinorVersion: true
    releaseTrain: 'stable'
    scope: {
      cluster: {
        releaseNamespace: 'azappconfig-system'
      }
    }
  }
}

// =====================================================
// Outputs
// =====================================================

output clusterId string = aksCluster.id
output clusterName string = aksCluster.name
output kubeletIdentityObjectId string = aksCluster.properties.identityProfile.kubeletidentity.objectId
output oidcIssuerUrl string = aksCluster.properties.oidcIssuerProfile.issuerURL
output nodeResourceGroupName string = nodeResourceGroupName
