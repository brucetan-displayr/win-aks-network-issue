# AKS Infrastructure with Pulumi

This directory contains Pulumi TypeScript code to deploy an Azure Kubernetes Service (AKS) cluster with advanced networking, security, and service mesh configurations.

## Prerequisites

1. **Install Pulumi CLI**
   ```bash
   curl -fsSL https://get.pulumi.com | sh
   ```

2. **Install Node.js and npm**
   - Node.js 18+ recommended
   - npm comes bundled with Node.js

3. **Azure CLI**
   ```bash
   # Install Azure CLI
   curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
   
   # Login to Azure
   az login
   ```

4. **Install dependencies**
   ```bash
   cd infra
   npm install
   ```

## Configuration

### 1. Initialize Pulumi Stack

```bash
# Login to Pulumi (use local backend or Pulumi Cloud)
pulumi login

# Create a new stack (e.g., dev, staging, prod)
pulumi stack init dev
```

### 2. Set Required Configuration

```bash
# Set Azure location
pulumi config set azure-native:location eastus

# Set environment
pulumi config set env dev

# Set SSH public key (required for AKS node access)
pulumi config set --secret sshPublicKey "$(cat ~/.ssh/id_rsa.pub)"

# Optional: Set admin username (defaults to 'dip-user')
pulumi config set adminUser myuser
```

### 3. Create Resource Group

The Pulumi program expects a resource group to exist with the same name as your stack:

```bash
# Create resource group matching your stack name
az group create --name dev --location eastus
```

## Deployment

### Deploy the infrastructure

```bash
pulumi up
```

Review the preview and confirm to deploy. This will create:
- User-assigned managed identity
- Network Security Group with comprehensive rules
- Virtual Network with AKS subnet
- AKS cluster with:
  - Azure CNI Overlay networking
  - Calico network policy
  - Istio service mesh
  - KEDA autoscaling
  - Azure Key Vault secrets provider
  - Azure Policy addon
  - Workload identity support
- App Configuration Kubernetes extension

### View outputs

```bash
pulumi stack output
```

Key outputs:
- `clusterName`: Name of the AKS cluster
- `clusterId`: Resource ID of the cluster
- `kubeConfig`: Kubernetes config (encrypted secret)
- `vnetId`: Virtual network resource ID
- `nsgId`: Network security group resource ID

### Get kubeconfig

```bash
# Export kubeconfig to file
pulumi stack output kubeConfig --show-secrets > ~/.kube/aks-config

# Or set KUBECONFIG environment variable
export KUBECONFIG=$(pulumi stack output kubeConfig --show-secrets)

# Verify connection
kubectl get nodes
```

Alternatively, use Azure CLI:
```bash
az aks get-credentials --resource-group dev --name dip-pipeline-win-aks
```

## Configuration Options

All configuration is managed through Pulumi config:

| Key | Required | Default | Description |
|-----|----------|---------|-------------|
| `env` | Yes | - | Environment name (dev, staging, prod) |
| `sshPublicKey` | Yes | - | SSH public key for node access |
| `location` | No | eastus | Azure region |
| `adminUser` | No | dip-user | Admin username for Linux nodes |

Set additional configuration:
```bash
pulumi config set <key> <value>
pulumi config set --secret <key> <value>  # For sensitive values
```

## Network Architecture

- **VNet CIDR**: 10.240.0.0/16
- **AKS Subnet**: 10.240.0.0/20
- **Overlay Pod CIDR**: 10.0.192.0/18
- **Network Plugin**: Azure CNI with Overlay mode
- **Network Policy**: Calico

### Security Rules

The NSG includes rules for:
- Kubernetes API server (6443)
- Kubelet API (10250)
- DNS (53)
- HTTPS ingress (80, 443)
- Istio service mesh ports
- Workload identity webhook (9443)
- Gateway API and cert-manager webhooks
- Metrics server (4443)
- Internal applications (5000, 8080, 30000-32767)
- Pod-to-pod and node-to-pod communication

## AKS Cluster Features

- **Kubernetes Version**: 1.33
- **Node Pool**: 
  - Name: tempsystem
  - VM Size: Standard_E4ads_v5
  - Auto-scaling: 1-1 nodes
  - Ephemeral OS disk (150GB)
  - Max pods per node: 250
- **Add-ons**:
  - Azure Key Vault Secrets Provider
  - Azure Policy
  - KEDA (Kubernetes Event-Driven Autoscaling)
  - Istio service mesh (asm-1-26)
  - App Configuration extension
- **Security**:
  - Azure AD integration with RBAC
  - Workload identity enabled
  - OIDC issuer enabled
  - Local accounts disabled

## Updating the Infrastructure

```bash
# Make changes to index.ts or configuration
pulumi config set <key> <value>

# Preview changes
pulumi preview

# Apply changes
pulumi up
```

## Destroying Resources

```bash
# Preview deletion
pulumi destroy

# Confirm and delete all resources
pulumi destroy --yes

# Remove stack
pulumi stack rm dev
```

## Troubleshooting

### Authentication Issues
```bash
# Re-login to Azure
az login

# Verify subscription
az account show
```

### Resource Group Not Found
Ensure the resource group exists and matches your stack name:
```bash
az group create --name $(pulumi stack --show-name) --location eastus
```

### View Pulumi Logs
```bash
pulumi logs
```

### Export Stack Configuration
```bash
pulumi stack export > stack-backup.json
```

## Additional Resources

- [Pulumi Azure Native Provider](https://www.pulumi.com/registry/packages/azure-native/)
- [AKS Documentation](https://docs.microsoft.com/azure/aks/)
- [Pulumi Documentation](https://www.pulumi.com/docs/)

## Security Considerations

- The `sshPublicKey` is stored as an encrypted secret in Pulumi state
- The `kubeConfig` output is marked as secret
- Consider using Azure Key Vault for additional secrets management
- Review and customize NSG rules based on your security requirements
- Enable private cluster mode for production environments by setting `enablePrivateCluster: true`

---

## Original Bicep Deployment (for reference)

```bash
az deployment group create \
  --resource-group bruce-aks-repro \
  --template-file template.bicep \
  --parameters @parameters.json
```
