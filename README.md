# win-aks-network-issue

A C# .NET 8 application designed to run on Windows containers in Azure Kubernetes Service (AKS). 

This solution helps test SQL Server connectivity and network performance in Windows-based Kubernetes environments.

## Overview

This application operates in two modes:

1. **Orchestrator Mode**: Creates 50 Kubernetes jobs every minute, each running in runner mode
2. **Runner Mode**: Executes `SELECT GETDATE()` SQL query every 10 second for 1 minute, then exits

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
│   - Execute 1 SQL query/sec    │
│   - Auto-cleanup after 5min    │
└────────────────────────────────┘
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
```

### 4. Monitor Jobs

```bash
# List all jobs created by orchestrator
kubectl get jobs -l app=sql-runner
```
