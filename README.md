# win-aks-network-issue

A C# .NET 8 application designed to run on Windows containers in Azure Kubernetes Service (AKS). This solution helps test SQL Server connectivity and network performance in Windows-based Kubernetes environments.

## Overview

This application operates in two modes:

1. **Orchestrator Mode**: Creates 50 Kubernetes jobs every minute, each running in runner mode
2. **Runner Mode**: Executes `SELECT GETDATE()` SQL query every second for 1 minute, then exits

## Architecture

```
┌─────────────────────────────────┐
│   Orchestrator Pod              │
│   (MODE=orchestrator)           │
│                                  │
│   - Runs continuously           │
│   - Creates 50 jobs/minute      │
│   - Uses Kubernetes API         │
└────────────┬────────────────────┘
             │
             │ Creates jobs every 60s
             │
             ▼
┌────────────────────────────────┐
│   Runner Jobs (x50)            │
│   (MODE=runner)                │
│                                 │
│   - Run for 60 seconds         │
│   - Execute SQL queries/sec    │
│   - Auto-cleanup after 5min    │
└────────────────────────────────┘
```

## Prerequisites

- .NET 8 SDK
- Docker Desktop with Windows containers enabled
- Azure Kubernetes Service (AKS) cluster with Windows node pools
- SQL Server database (Azure SQL Database or SQL Server)
- Container registry (Azure Container Registry, Docker Hub, etc.)

## Configuration

The application uses environment variables for configuration:

| Variable | Mode | Required | Description |
|----------|------|----------|-------------|
| `MODE` | Both | Yes | `orchestrator` or `runner` |
| `CONN_STR` | Both | Yes | SQL Server connection string |
| `IMAGE_NAME` | Orchestrator | Yes | Full container image name with tag |
| `NAMESPACE` | Orchestrator | No | Kubernetes namespace (default: `default`) |

## Building the Application

### Build Locally

```bash
cd SqlJobRunner
dotnet restore
dotnet build
dotnet publish -c Release
```

### Build Docker Image

```bash
# Build for Windows containers
docker build -t sql-job-runner:latest .

# Tag for your registry
docker tag sql-job-runner:latest your-registry.azurecr.io/sql-job-runner:latest

# Push to registry
docker push your-registry.azurecr.io/sql-job-runner:latest
```

## Running Locally

### Runner Mode (SQL Query Execution)

```bash
$env:MODE="runner"
$env:CONN_STR="Server=your-server.database.windows.net;Database=your-db;User Id=user;Password=pass;Encrypt=true;"
dotnet run --project SqlJobRunner
```

### Orchestrator Mode (Requires Kubernetes)

```bash
$env:MODE="orchestrator"
$env:CONN_STR="Server=your-server.database.windows.net;Database=your-db;User Id=user;Password=pass;Encrypt=true;"
$env:IMAGE_NAME="your-registry.azurecr.io/sql-job-runner:latest"
$env:NAMESPACE="default"
dotnet run --project SqlJobRunner
```

## Deploying to AKS

### 1. Update Configuration

Edit `k8s-deployment.yaml` and update:
- Container image name in ConfigMap
- SQL connection string in Secret
- Container image reference in Deployment

### 2. Apply Kubernetes Manifests

```bash
kubectl apply -f k8s-deployment.yaml
```

### 3. Verify Deployment

```bash
# Check orchestrator pod
kubectl get pods -l app=sql-job-orchestrator

# Check created jobs
kubectl get jobs -l app=sql-runner

# View orchestrator logs
kubectl logs -l app=sql-job-orchestrator -f

# View runner job logs
kubectl logs job/sql-runner-<timestamp>-<number>
```

### 4. Monitor Jobs

```bash
# List all jobs created by orchestrator
kubectl get jobs -l app=sql-runner

# View successful jobs
kubectl get jobs -l app=sql-runner --field-selector status.successful=1

# View failed jobs
kubectl get jobs -l app=sql-runner --field-selector status.failed=1

# Clean up completed jobs (done automatically after 5 minutes)
kubectl delete jobs -l app=sql-runner
```

## Security Considerations

- Store SQL connection strings in Kubernetes Secrets
- Use Azure Key Vault for sensitive data with CSI driver
- Enable Pod Security Standards
- Use managed identities when possible
- Restrict RBAC permissions to minimum required

## Troubleshooting

### Orchestrator Pod Issues

```bash
# Check pod status
kubectl describe pod -l app=sql-job-orchestrator

# View logs
kubectl logs -l app=sql-job-orchestrator --tail=100

# Check service account permissions
kubectl auth can-i create jobs --as=system:serviceaccount:default:sql-job-orchestrator
```

### Runner Job Issues

```bash
# List all runner jobs
kubectl get jobs -l app=sql-runner

# Check specific job
kubectl describe job sql-runner-<timestamp>-<number>

# View pod logs
kubectl logs job/sql-runner-<timestamp>-<number>

# Check SQL connectivity from pod
kubectl exec -it <runner-pod-name> -- dotnet SqlJobRunner.dll
```

### Common Issues

1. **Image Pull Errors**: Ensure your AKS cluster has access to your container registry
2. **SQL Connection Failures**: Verify connection string and firewall rules
3. **Permission Denied**: Check RBAC Role and RoleBinding configuration
4. **Windows Node Selection**: Verify `nodeSelector` is set to `kubernetes.io/os: windows`

## Dependencies

- **Microsoft.Data.SqlClient**: 6.1.3 - SQL Server connectivity
- **KubernetesClient**: 18.0.13 - Kubernetes API integration

## License

This project is provided as-is for testing and diagnostic purposes.
