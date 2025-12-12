// =====================================================
// Role Assignments Module
// =====================================================

@description('AKS Cluster ID')
param aksClusterId string

@description('Kubelet identity object ID')
param aksKubeletIdentityObjectId string

@description('Shared Container Registry ID')
param sharedRegistryId string

@description('Connectivity Container Registry ID')
param connRegistryId string

@description('Platform Engineers Group ID')
param platformEngineersGroupId string

// =====================================================
// Role Assignments for Kubelet Identity
// =====================================================

// ACR Pull for Shared Registry
resource kubeletAcrPullShared 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(aksKubeletIdentityObjectId, sharedRegistryId, 'AcrPull')
  scope: resourceGroup()
  properties: {
    principalId: aksKubeletIdentityObjectId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d') // AcrPull
    principalType: 'ServicePrincipal'
  }
}

// ACR Pull for Connectivity Registry
resource kubeletAcrPullConn 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(aksKubeletIdentityObjectId, connRegistryId, 'AcrPull')
  scope: resourceGroup()
  properties: {
    principalId: aksKubeletIdentityObjectId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d') // AcrPull
    principalType: 'ServicePrincipal'
  }
}

// =====================================================
// Role Assignments for Platform Engineers
// =====================================================

// Cluster User Role for Platform Engineers
resource platformEngineersClusterUser 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(platformEngineersGroupId, aksClusterId, 'ClusterUser')
  scope: resourceGroup()
  properties: {
    principalId: platformEngineersGroupId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4abbcc35-e782-43d8-92c5-2d3f1bd2253f') // Azure Kubernetes Service Cluster User Role
    principalType: 'Group'
  }
}

// =====================================================
// Outputs
// =====================================================

output kubeletAcrPullSharedAssignmentId string = kubeletAcrPullShared.id
output kubeletAcrPullConnAssignmentId string = kubeletAcrPullConn.id
output platformEngineersClusterUserAssignmentId string = platformEngineersClusterUser.id
