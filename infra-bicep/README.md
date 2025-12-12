# Windows AKS Cluster with Hub-Spoke Networking - Bicep Template

This Bicep template recreates the Windows AKS cluster setup from the `windows-aks-resource.ts` Pulumi code, including all networking components (Virtual WAN, Hub, Spoke VNet, Private DNS zones, etc.).

## Architecture Overview

This template deploys:

### Networking Components

- **Virtual WAN**: Standard tier with branch-to-branch traffic enabled
- **Virtual Hub**: Basic SKU with configurable address prefix
- **Shared Service VNet**: For connectivity services (10.0.0.0/16)
  - Internal Load Balancer subnet
  - Pipeline subnet for CI/CD
- **Spoke VNet**: For application workloads
  - AKS subnet (configurable CIDR)
  - Internal Load Balancer subnet
  - Network Security Groups with appropriate rules
- **Hub-Spoke Connections**: Connecting VNets to Virtual Hub with routing

### DNS Components

- **AKS Private DNS Zone**: `{env}.privatelink.{region}.azmk8s.io`
- **Private Endpoint DNS Zones**:
  - Key Vault: `privatelink.vaultcore.azure.net`
  - Storage Blob: `privatelink.blob.core.windows.net`
  - Container Registry: `privatelink.azurecr.io`
- VNet links to both Shared Service and Spoke VNets

### AKS Cluster

- **Private AKS Cluster** with Azure CNI Overlay networking
- **Network Plugin**: Azure CNI with Overlay mode
- **Network Policy**: Calico
- **Network Dataplane**: Azure
- **Service Mesh**: Istio with external ingress gateway
- **Workload Identity**: Enabled with OIDC issuer
- **Azure AD Integration**: With RBAC enabled
- **Add-ons**:
  - Azure Key Vault Secrets Provider (with secret rotation)
  - Azure Policy
  - App Configuration Kubernetes Provider
- **Workload Autoscaler**: KEDA enabled

### Agent Pools

1. **System Pool** (Linux): `systeme4v5`

   - Standard_E4ads_v5 VMs
   - 2-6 nodes with autoscaling
   - Ephemeral OS disks
   - System workloads only

2. **User Pool - Linux**: `userlinux`

   - Standard_D4ads_v5 VMs
   - 2-10 nodes with autoscaling
   - General workloads

3. **User Pool - Windows**: `win01`

   - Standard_D8ads_v5 VMs
   - 2-10 nodes with autoscaling
   - Windows workloads

4. **User Pool - Windows (Second)**: `win02`
   - Standard_D4ads_v5 VMs
   - 1-5 nodes with autoscaling
   - Windows batch workloads

### Security & Identity

- **User Assigned Identity** for AKS with appropriate permissions
- **Role Assignments**:
  - Private DNS Zone Contributor
  - Network Contributor
  - ACR Pull for Container Registries
  - Cluster User for Platform Engineers

### Monitoring

- CPU usage alert (threshold: 80%)
- Memory usage alert (threshold: 90%)
- Integrated with Action Groups for notifications

### Container Registry

- Azure Container Registry (Premium SKU)
- Zone redundancy enabled
- Public network access (can be disabled after private endpoint setup)

## Parameters

### Required Parameters

| Parameter                  | Type         | Description                               | Example                                |
| -------------------------- | ------------ | ----------------------------------------- | -------------------------------------- |
| `environment`              | string       | Environment name                          | `dev`, `lab`, `rc`, `prod`             |
| `regionAbbreviation`       | string       | Azure region abbreviation                 | `eus`, `aue`, `cnc`, `sea`, `weu`      |
| `spokeId`                  | string       | Spoke identifier                          | `999`, `101`, `102`                    |
| `platformEngineersGroupId` | string       | AD Group Object ID for platform engineers | GUID                                   |
| `tenantId`                 | string       | Azure AD Tenant ID                        | GUID (defaults to subscription tenant) |
| `sshPublicKey`             | securestring | SSH public key for Linux nodes            | SSH public key string                  |

### Optional Parameters

| Parameter             | Type   | Default  | Description                         |
| --------------------- | ------ | -------- | ----------------------------------- |
| `kubernetesVersion`   | string | `1.33.3` | Kubernetes version                  |
| `isFirstDeployment`   | bool   | `false`  | Enable for initial cluster creation |
| `actionGroupId`       | string | `''`     | Action Group ID for alerts          |
| `adminGroupObjectIds` | array  | `[]`     | Additional admin group object IDs   |

## Deployment Instructions

### Prerequisites

1. Azure subscription with appropriate permissions
2. Azure CLI installed
3. SSH key pair generated
4. Platform Engineers AD Group created
5. (Optional) Action Group for monitoring alerts

### Step 1: Prepare Parameters

Edit `main.parameters.json` with your values:

```json
{
  "environment": { "value": "dev" },
  "regionAbbreviation": { "value": "eus" },
  "spokeId": { "value": "999" },
  "platformEngineersGroupId": { "value": "YOUR_GROUP_ID" },
  "sshPublicKey": { "value": "YOUR_SSH_PUBLIC_KEY" },
  "isFirstDeployment": { "value": true }
}
```

### Step 2: First Deployment (Two-Step Process)

**Important**: AKS cluster deployment requires a two-step process due to system pool requirements.

#### Step 2.1: Initial Deployment with Temporary System Pool

Set `isFirstDeployment: true` in parameters file.

```bash
az deployment sub create \
  --location eastus \
  --template-file main.bicep \
  --parameters main.parameters.json
```

This creates a temporary system pool that can be deleted later.

#### Step 2.2: Remove Temporary Pool

After successful deployment:

1. Delete the temporary system pool (`tempsystem`):

```bash
az aks nodepool delete \
  --resource-group <spoke-rg-name> \
  --cluster-name <cluster-name> \
  --name tempsystem
```

2. Update parameters: Set `isFirstDeployment: false`

3. Redeploy to ensure configuration is correct:

```bash
az deployment sub create \
  --location eastus \
  --template-file main.bicep \
  --parameters main.parameters.json
```

### Step 3: Verify Deployment

```bash
# Get cluster credentials
az aks get-credentials \
  --resource-group <spoke-rg-name> \
  --name <cluster-name>

# Verify nodes
kubectl get nodes

# Verify system components
kubectl get pods -A
```

## Customization

### Adding More Agent Pools

Edit `modules/windows-aks.bicep` and add additional agent pool resources:

```bicep
resource userPoolWindows3 'Microsoft.ContainerService/managedClusters/agentPools@2024-09-02-preview' = {
  parent: aksCluster
  name: 'win03'
  properties: {
    count: 2
    minCount: 2
    maxCount: 8
    enableAutoScaling: true
    vmSize: 'Standard_D8ads_v5'
    osType: 'Windows'
    // ... other properties
  }
}
```

### Modifying Network Configuration

Edit subnet CIDRs in `main.bicep`:

```bicep
var addressId = int(spokeId) + 5
var spokeAddressSpace = '10.${addressId}.0.0/16'
var aksSubnetCidr = '10.${addressId}.128.0/17'
```

### Changing Kubernetes Version

Update the `kubernetesVersion` parameter:

```bash
az aks get-versions --location eastus --output table
```

## Maintenance

### Node OS Upgrades

Automatic maintenance windows are configured:

- **Dev/Lab/RC**: Monday 01:00 UTC+10
- **Prod**: Wednesday 10:00 UTC+10

### Scaling Agent Pools

```bash
# Manual scaling
az aks nodepool scale \
  --resource-group <rg-name> \
  --cluster-name <cluster-name> \
  --name win01 \
  --node-count 5

# Autoscaling is enabled by default
```

## Networking Details

### Address Spaces

- **Hub**: `10.201.0.0/23` (default)
- **Shared Service VNet**: `10.0.0.0/16`
- **Spoke VNet**: `10.{spokeId+5}.0.0/16`
- **AKS Service CIDR**: `10.0.192.0/18`
- **Pod CIDR (Overlay)**: `10.244.0.0/16`

### Network Security

- **NSG Rules**: Pre-configured for AKS requirements
- **Calico Network Policy**: Enabled for pod-level security
- **Private Cluster**: API server not accessible from internet
- **Service Mesh**: Istio for advanced traffic management

## Monitoring

Metric alerts are configured for:

- **CPU Usage**: Alert when > 80% for 15 minutes
- **Memory Usage**: Alert when > 90% for 15 minutes

View alerts in Azure Portal or configure Action Groups for notifications.

## Cost Optimization

- **Free Tier**: Available for dev/lab/rc environments
- **Standard Tier**: Required for prod (SLA-backed)
- **Spot Instances**: Can be configured for non-critical workloads
- **Autoscaling**: Automatically scales down during low usage

## Troubleshooting

### Common Issues

1. **Deployment fails with "system pool required"**

   - Ensure `isFirstDeployment: true` for first deployment
   - Follow two-step deployment process

2. **Private cluster connectivity**

   - Verify VNet peering/connection to Virtual Hub
   - Check DNS resolution for private endpoint
   - Ensure you're connected via VPN or have private connectivity

3. **Node pool creation fails**

   - Verify subnet has sufficient IP addresses
   - Check VM SKU availability in region
   - Ensure NSG rules don't block required traffic

4. **Windows node pool issues**
   - Windows node pool names limited to 6 characters
   - Ensure sufficient OS disk size (256GB minimum recommended)
   - Verify Windows container image compatibility

### Useful Commands

```bash
# View cluster details
az aks show --resource-group <rg> --name <cluster>

# Get node resource group
az aks show --resource-group <rg> --name <cluster> --query nodeResourceGroup -o tsv

# View node pools
az aks nodepool list --resource-group <rg> --cluster-name <cluster> -o table

# Check AKS diagnostics
az aks check-acr --resource-group <rg> --name <cluster> --acr <acr-name>
```

## References

- [Azure AKS Documentation](https://learn.microsoft.com/en-us/azure/aks/)
- [Azure CNI Overlay](https://learn.microsoft.com/en-us/azure/aks/azure-cni-overlay)
- [Windows containers in AKS](https://learn.microsoft.com/en-us/azure/aks/windows-aks-intro)
- [AKS Baseline Architecture](https://learn.microsoft.com/en-us/azure/architecture/reference-architectures/containers/aks/baseline-aks)
- [Virtual WAN Documentation](https://learn.microsoft.com/en-us/azure/virtual-wan/)

## License

This template is provided as-is for deployment of Azure infrastructure.
