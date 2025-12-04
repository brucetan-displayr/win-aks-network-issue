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
docker push $imageName
Write-Host "Image pushed to $Registry as $imageName" -ForegroundColor Green
