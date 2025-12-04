# win-aks-network-issue

We discovered there are intermittent network failures affecting SQL Connection that affect roughly 1.6% of the network requests. This issue is genuine and has significant business impact on the customer workload as it slows down the application network performance, increase SQL latencies in the event of retries and significantly impact our testing/workload. 

The code in this repository reproduce this issues on windows aks. We also cross verified in linux aks and unable to reproduce it. 

## Overview

This application operates in two modes:

1. **Orchestrator Mode**: Creates 50 Kubernetes jobs every minute, each running in runner mode
2. **Runner Mode**: Executes `SELECT GETDATE()` SQL query every 10 second for 1 minute, then exits

## Architecture

```
┌─────────────────────────────────┐
│   Orchestrator Pod              │
│   (MODE=orchestrator)           │
│                                 │
│   - Runs continuously           │
│   - Creates 50 jobs every x sec |
│   - Uses Kubernetes API         │
└────────────┬────────────────────┘
             │
             │ Creates jobs every 60s
             │
             ▼
┌────────────────────────────────┐
│   Runner Jobs (x50)            │
│   (MODE=runner)                │
│                                │
│   - Run for 60 seconds         │
│   - Execute 1 SQL query/ 10 sec│
│   - Auto-cleanup after 5min    │
└────────────────────────────────┘
```

## Reproduce Network issues on windows AKS

### 1. Update Configuration

Edit `k8s-deployment-windows.yaml` and update:
- SQL connection string in Secret
```
# Replace with your actual SQL Server connection string
  CONN_STR: "Server=your-server.database.windows.net;Database=your-database;User Id=your-user;Password=your-password;Encrypt=true;TrustServerCertificate=false;"
```

### 2. Apply Kubernetes Manifests

```bash
kubectl apply -f k8s-deployment-windows.yaml
```

### 3. Monitor Logs after 1 min

After 1 min once all the sql-runner jobs are completed, we can observe that network error generally start to appear 

```bash
kubectl logs -l app=sql-runner | grep -i error 
ERROR executing query: A transport-level error has occurred when receiving results from the server. (provider: TCP Provider, error: 0 - A connection attempt failed because the connected party did not properly respond after a period of time, or established connection failed because connected host has failed to respond.)
ERROR executing query: A transport-level error has occurred when receiving results from the server. (provider: TCP Provider, error: 0 - A connection attempt failed because the connected party did not properly respond after a period of time, or established connection failed because connected host has failed to respond.)
ERROR executing query: A connection was successfully established with the server, but then an error occurred during the login process. (provider: SSL Provider, error: 0 - An existing connection was forcibly closed by the remote host.)
```

## This Network issues can't be reproduced on linux aks

Our aks setup is a hybrid of windows and linux nodes, if we update the deployment to target linux nodes, this issues disappear. 

```bash
kubectl apply -f k8s-deployment-linux.yaml
```

Running the below command returns no errors

```
kubectl logs -l app=sql-runner | grep -i error
```
