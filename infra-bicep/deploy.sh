#!/bin/bash

# =====================================================
# Windows AKS Deployment Script
# =====================================================
# This script deploys the Windows AKS cluster with all networking components

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check prerequisites
check_prerequisites() {
    print_info "Checking prerequisites..."
    
    if ! command -v az &> /dev/null; then
        print_error "Azure CLI is not installed. Please install it first."
        exit 1
    fi
    
    if ! az account show &> /dev/null; then
        print_error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    print_info "Prerequisites check passed!"
}

# Function to validate parameters file
validate_parameters() {
    print_info "Validating parameters file..."
    
    if [ ! -f "main.parameters.json" ]; then
        print_error "Parameters file 'main.parameters.json' not found!"
        exit 1
    fi
    
    # Check if required parameters are set
    if grep -q "YOUR_PLATFORM_ENGINEERS_GROUP_OBJECT_ID" main.parameters.json; then
        print_error "Please update platformEngineersGroupId in main.parameters.json"
        exit 1
    fi
    
    if grep -q "YOUR_SSH_PUBLIC_KEY" main.parameters.json; then
        print_error "Please provide SSH public key in main.parameters.json"
        exit 1
    fi
    
    print_info "Parameters validation passed!"
}

# Function to perform what-if deployment
perform_whatif() {
    print_info "Performing what-if analysis..."
    
    az deployment sub what-if \
        --location eastus \
        --template-file main.bicep \
        --parameters main.parameters.json \
        --no-pretty-print
}

# Function to deploy the template
deploy_template() {
    local deployment_name="windows-aks-deployment-$(date +%Y%m%d-%H%M%S)"
    
    print_info "Starting deployment: $deployment_name"
    
    az deployment sub create \
        --name "$deployment_name" \
        --location eastus \
        --template-file main.bicep \
        --parameters main.parameters.json
    
    if [ $? -eq 0 ]; then
        print_info "Deployment completed successfully!"
        return 0
    else
        print_error "Deployment failed!"
        return 1
    fi
}

# Function to get deployment outputs
get_outputs() {
    print_info "Retrieving deployment outputs..."
    
    local latest_deployment=$(az deployment sub list --query "[?properties.provisioningState=='Succeeded'] | sort_by(@, &properties.timestamp) | [-1].name" -o tsv)
    
    if [ -z "$latest_deployment" ]; then
        print_warning "No successful deployments found"
        return
    fi
    
    print_info "Latest successful deployment: $latest_deployment"
    az deployment sub show --name "$latest_deployment" --query properties.outputs -o json
}

# Function to configure kubectl access
configure_kubectl() {
    print_info "Configuring kubectl access..."
    
    local rg_name=$1
    local cluster_name=$2
    
    if [ -z "$rg_name" ] || [ -z "$cluster_name" ]; then
        print_warning "Resource group or cluster name not provided. Skipping kubectl configuration."
        return
    fi
    
    az aks get-credentials \
        --resource-group "$rg_name" \
        --name "$cluster_name" \
        --overwrite-existing
    
    if [ $? -eq 0 ]; then
        print_info "kubectl configured successfully!"
        kubectl get nodes
    else
        print_error "Failed to configure kubectl"
    fi
}

# Main deployment workflow
main() {
    echo "======================================"
    echo "Windows AKS Deployment Script"
    echo "======================================"
    echo ""
    
    # Parse command line arguments
    SKIP_WHATIF=false
    RG_NAME=""
    CLUSTER_NAME=""
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --skip-whatif)
                SKIP_WHATIF=true
                shift
                ;;
            --rg-name)
                RG_NAME="$2"
                shift 2
                ;;
            --cluster-name)
                CLUSTER_NAME="$2"
                shift 2
                ;;
            --help)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --skip-whatif              Skip what-if analysis"
                echo "  --rg-name NAME            Resource group name"
                echo "  --cluster-name NAME       Cluster name"
                echo "  --help                    Show this help message"
                echo ""
                echo "Examples:"
                echo "  $0 --rg-name my-rg --cluster-name my-cluster"
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done
    
    # Check prerequisites
    check_prerequisites
    
    # Validate parameters
    validate_parameters
    
    # Warn about first deployment
    if [ "$FIRST_DEPLOYMENT" = true ]; then
        print_warning "First deployment mode enabled. Ensure isFirstDeployment=true in parameters file."
        echo ""
    fi
    
    # Perform what-if analysis
    if [ "$SKIP_WHATIF" = false ]; then
        read -p "Perform what-if analysis? (y/n) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            perform_whatif
            echo ""
        fi
    fi
    
    # Confirm deployment
    read -p "Proceed with deployment? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "Deployment cancelled."
        exit 0
    fi
    
    # Deploy template
    if deploy_template; then
        echo ""
        get_outputs
        echo ""
        
        
        # Configure kubectl if cluster info provided
        if [ -n "$RG_NAME" ] && [ -n "$CLUSTER_NAME" ]; then
            echo ""
            read -p "Configure kubectl access? (y/n) " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                configure_kubectl "$RG_NAME" "$CLUSTER_NAME"
            fi
        fi
        
        echo ""
        print_info "Deployment workflow completed!"
        
        if [ "$FIRST_DEPLOYMENT" = true ]; then
            echo ""
            print_warning "IMPORTANT: This was a first deployment."
            print_warning "Next steps:"
            print_warning "1. Delete the temporary system pool: tempsystem"
            print_warning "2. Set isFirstDeployment=false in parameters file"
            print_warning "3. Redeploy to ensure configuration is correct"
        fi
    else
        print_error "Deployment workflow failed!"
        exit 1
    fi
}

# Run main function
main "$@"
