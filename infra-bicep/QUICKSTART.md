# Windows AKS Bicep Template - Quick Start

## Overview

This is a comprehensive Azure Bicep template that recreates the Windows AKS cluster setup from `windows-aks-resource.ts`, including all networking components.

## What's Included

### Infrastructure Components

- ✅ Virtual WAN (Standard tier)
- ✅ Virtual Hub with route tables
- ✅ Shared Service VNet (10.0.0.0/16)
- ✅ Spoke VNet with AKS and ILB subnets
- ✅ Hub-Spoke network connections
- ✅ Private DNS zones (AKS, Key Vault, Storage, ACR)
- ✅ User Assigned Identity for AKS
- ✅ Container Registry (Premium, zone redundant)
- ✅ Windows AKS Cluster with Azure CNI Overlay
- ✅ Multiple agent pools (1 System Linux, 1 User Linux, 2 User Windows)
- ✅ Service Mesh (Istio with external ingress)
- ✅ Workload Identity and OIDC
- ✅ Azure Key Vault Secrets Provider
- ✅ Azure Policy add-on
- ✅ App Configuration Provider
- ✅ KEDA (Kubernetes Event-Driven Autoscaling)
- ✅ RBAC role assignments
- ✅ Azure Monitor metric alerts

### Agent Pools Created

1. **System Pool (Linux)**: systeme4v5 - 2-6 nodes, Standard_E4ads_v5
2. **User Pool (Linux)**: userlinux - 2-10 nodes, Standard_D4ads_v5
3. **User Pool (Windows)**: win01 - 2-10 nodes, Standard_D8ads_v5
4. **User Pool (Windows)**: win02 - 1-5 nodes, Standard_D4ads_v5

## File Structure

```
windows-aks-bicep/
├── main.bicep                      # Main template (subscription scope)
├── main.parameters.json            # Parameter values
├── deploy.sh                       # Deployment script
├── README.md                       # Detailed documentation
├── DIFFERENCES.md                  # Pulumi vs Bicep comparison
├── QUICKSTART.md                   # This file
└── modules/
    ├── connectivity.bicep          # vWAN, Hub, Shared VNet
    ├── spoke-networking.bicep      # Spoke VNet, NSGs, subnets
    ├── dns-zones.bicep             # Private DNS zones
    ├── aks-identity.bicep          # User assigned identity
    ├── container-registry.bicep    # Azure Container Registry
    ├── windows-aks.bicep           # AKS cluster and agent pools
    ├── role-assignments.bicep      # RBAC assignments
    └── monitoring.bicep            # Metric alerts
```

## Prerequisites

1. Azure subscription
2. Azure CLI installed (`az --version`)
3. Logged in to Azure (`az login`)
4. Platform Engineers AD Group created
5. SSH key pair generated

## Quick Deployment

### Step 1: Update Parameters

Edit `main.parameters.json`:

```json
{
  "platformEngineersGroupId": { "value": "YOUR_GROUP_OBJECT_ID" },
  "sshPublicKey": { "value": "ssh-rsa AAAAB3... your-key" },
  "environment": { "value": "dev" },
  "regionAbbreviation": { "value": "eus" },
  "spokeId": { "value": "999" }
}
```

### Step 2: Deploy (Using Script)

```bash
cd /home/bruce/code/dip/windows-aks-bicep
./deploy.sh
```

Or manually:

```bash
az deployment sub create \
  --location eastus \
  --template-file main.bicep \
  --parameters main.parameters.json
```

### Step 3: Access Cluster

```bash
az aks get-credentials \
  --resource-group $RG_NAME \
  --name $CLUSTER_NAME

kubectl get nodes
kubectl get pods -A
```

## Key Configuration Options

### Environment

- `dev`, `lab`, `rc`: Free tier AKS
- `prod`: Standard tier AKS with SLA

### Agent Pool Customization

Edit `modules/windows-aks.bicep` to add/modify pools:

- Change VM sizes
- Adjust min/max node counts
- Add node labels and taints
- Configure OS disk size

### Network Customization

Edit `main.bicep` to change:

- Spoke VNet CIDR
- AKS subnet size
- Service CIDR
- DNS service IP

### Monitoring

Metric alerts are created for:

- CPU usage > 80% for 15 minutes
- Memory usage > 90% for 15 minutes

Configure Action Group ID to receive alerts.

## Costs

Estimated monthly costs (East US, dev environment):

- AKS Control Plane: Free tier = $0
- VMs (assuming 5 nodes avg): ~$300-500/month
- Virtual WAN Hub: ~$250/month
- Storage/Networking: ~$50/month
- Container Registry: ~$5/month

**Total: ~$600-800/month** (dev/test)
**Prod costs higher** due to Standard tier AKS and more nodes

## Common Commands

```bash
# View deployment history
az deployment sub list --output table

# Check deployment status
az deployment sub show --name <deployment-name>

# List resource groups
az group list --output table

# View AKS details
az aks show --resource-group <rg> --name <cluster> --output yaml

# Scale node pool
az aks nodepool scale \
  --resource-group <rg> \
  --cluster-name <cluster> \
  --name win01 \
  --node-count 5

# Upgrade Kubernetes version
az aks upgrade \
  --resource-group <rg> \
  --name <cluster> \
  --kubernetes-version 1.33.3
```

## Troubleshooting

### Deployment Fails

```bash
# View deployment errors
az deployment sub show --name <deployment-name> --query properties.error

# Validate template
az deployment sub validate \
  --location eastus \
  --template-file main.bicep \
  --parameters main.parameters.json
```

### Cannot Access Cluster

```bash
# Verify private cluster connectivity
# You need VPN connection or private endpoint access

# Check API server accessibility
az aks show \
  --resource-group <rg> \
  --name <cluster> \
  --query apiServerAccessProfile
```

### Node Pool Issues

```bash
# View node pool details
az aks nodepool list \
  --resource-group <rg> \
  --cluster-name <cluster> \
  --output table

# Check node pool status
az aks nodepool show \
  --resource-group <rg> \
  --cluster-name <cluster> \
  --name win01
```

## Next Steps

1. **Configure CI/CD**: Integrate with Azure DevOps or GitHub Actions
2. **Deploy Workloads**: Apply Kubernetes manifests for applications
3. **Set Up Monitoring**: Configure Azure Monitor and Log Analytics
4. **Implement Network Policies**: Use Calico for pod-level security
5. **Configure Ingress**: Set up Istio ingress gateway for external traffic
6. **Enable GitOps**: Use Flux or ArgoCD for continuous deployment

## Support

For issues or questions:

1. Check `README.md` for detailed documentation
2. Review `DIFFERENCES.md` for Pulumi comparison
3. Validate parameters and prerequisites
4. Check Azure deployment logs

## References

- [Azure AKS Documentation](https://learn.microsoft.com/en-us/azure/aks/)
- [Bicep Documentation](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/)
- [Azure CNI Overlay](https://learn.microsoft.com/en-us/azure/aks/azure-cni-overlay)
- [Windows Containers in AKS](https://learn.microsoft.com/en-us/azure/aks/windows-aks-intro)
