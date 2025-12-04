# Quick Start Guide

This guide will help you quickly get the SQL Job Runner up and running.

## Quick Test Locally (Runner Mode)

1. **Prerequisites**:
   - .NET 8 SDK installed
   - SQL Server accessible

2. **Set environment variables** (PowerShell):
   ```powershell
   $env:MODE="runner"
   $env:CONN_STR="Server=your-server;Database=your-db;User Id=user;Password=pass;Encrypt=true;"
   ```

3. **Run**:
   ```powershell
   cd SqlJobRunner
   dotnet run
   ```

## Quick Deploy to AKS

1. **Build and push Docker image**:
   ```powershell
   # Build
   .\build.ps1 -Registry "brucetandisplayr"
   
   # Push
   docker push brucetandisplayr/sql-job-runner:latest
   ```

2. **Update k8s-deployment.yaml**:
   - Line 8: Set your image name
   - Line 17: Set your SQL connection string

3. **Deploy**:
   ```bash
   kubectl apply -f k8s-deployment.yaml
   ```

4. **Monitor**:
   ```bash
   # Watch orchestrator logs
   kubectl logs -l app=sql-job-orchestrator -f
   
   # List created jobs
   kubectl get jobs -l app=sql-runner
   
   # View a job's logs
   kubectl logs job/<job-name>
   ```

## Testing Single Runner Job

1. **Update k8s-test-runner.yaml**:
   - Line 9: Set your SQL connection string
   - Line 28: Set your image name

2. **Deploy test job**:
   ```bash
   kubectl apply -f k8s-test-runner.yaml
   ```

3. **Check results**:
   ```bash
   kubectl logs job/sql-runner-test
   ```

## Architecture Summary

```
Orchestrator Pod (continuous)
    └─> Creates 50 Jobs every 60 seconds
            └─> Each Job runs for 60 seconds
                    └─> Executes 1 SQL query per second
```

## Expected Behavior

### Orchestrator Mode
- Runs indefinitely
- Creates batch of 50 jobs every 60 seconds
- Each batch has timestamp in job name
- Logs each job creation

### Runner Mode
- Runs for exactly 60 seconds
- Executes SQL query every 1 second (≈60 queries total)
- Logs each query result
- Exits after 60 seconds

## Common Commands

```bash
# Scale orchestrator
kubectl scale deployment sql-job-orchestrator --replicas=0

# Delete all jobs
kubectl delete jobs -l app=sql-runner

# View job statistics
kubectl get jobs -l app=sql-runner --show-labels

# Cleanup
kubectl delete -f k8s-deployment.yaml
```

## Troubleshooting

### Issue: "ERROR: CONN_STR environment variable is required"
**Solution**: Ensure the Secret is created and referenced correctly in the YAML

### Issue: "Image pull failed"
**Solution**: 
- Verify image name is correct
- Check AKS has access to your container registry
- Run: `kubectl describe pod <pod-name>` for details

### Issue: "Permission denied creating jobs"
**Solution**: Verify the ServiceAccount and RBAC are properly configured

### Issue: SQL connection timeout
**Solution**: 
- Check SQL Server firewall allows AKS outbound IPs
- Verify connection string is correct
- Test with Azure SQL: Enable "Allow Azure services" option

## Performance Notes

- **50 jobs/minute** = 3000 jobs/hour = 72,000 jobs/day
- Each job: **~60 SQL queries** = 180,000 queries/hour
- **Resource usage**: Plan for 50 concurrent pods minimum
- **Cleanup**: Jobs auto-delete after 5 minutes (ttlSecondsAfterFinished: 300)

## Next Steps

For detailed information, see [README.md](README.md)
