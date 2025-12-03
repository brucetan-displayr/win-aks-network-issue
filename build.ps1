# PowerShell script to build and publish the Docker image

param(
    [Parameter(Mandatory=$true)]
    [string]$Registry,
    
    [Parameter(Mandatory=$false)]
    [string]$Tag = "latest"
)

$imageName = "$Registry/sql-job-runner:$Tag"

Write-Host "Building Docker image: $imageName" -ForegroundColor Green

# Build the Docker image
docker build -t $imageName .

if ($LASTEXITCODE -ne 0) {
    Write-Host "Docker build failed!" -ForegroundColor Red
    exit 1
}

Write-Host "Docker build successful!" -ForegroundColor Green
Write-Host ""
Write-Host "To push the image to your registry, run:" -ForegroundColor Yellow
Write-Host "  docker push $imageName" -ForegroundColor Cyan
Write-Host ""
Write-Host "To update Kubernetes deployment, edit k8s-deployment.yaml and set:" -ForegroundColor Yellow
Write-Host "  IMAGE_NAME: $imageName" -ForegroundColor Cyan
