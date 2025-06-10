#!/bin/bash

# Variables
CLUSTER_NAME="housing-ml-cluster1"
REGION="us-west-2"
NODE_GROUP_NAME="housing-workers"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}Setting up EKS cluster for Housing Price Prediction ML Pipeline${NC}"

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to install kubectl
install_kubectl() {
    echo -e "${YELLOW}Installing kubectl...${NC}"
    
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        # Linux installation
        echo "Installing kubectl for Linux..."
        curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
        chmod +x kubectl
        sudo mv kubectl /usr/local/bin/
        echo -e "${GREEN}kubectl installed successfully${NC}"
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS installation
        echo "Installing kubectl for macOS..."
        if command_exists brew; then
            brew install kubectl
        else
            curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/darwin/amd64/kubectl"
            chmod +x kubectl
            sudo mv kubectl /usr/local/bin/
        fi
        echo -e "${GREEN}kubectl installed successfully${NC}"
    elif [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "cygwin" ]]; then
        # Windows installation
        echo "Installing kubectl for Windows..."
        curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/windows/amd64/kubectl.exe"
        # Note: You may need to move this to a directory in your PATH manually
        echo -e "${YELLOW}Please move kubectl.exe to a directory in your PATH${NC}"
    else
        echo -e "${RED}Unsupported OS for automatic kubectl installation${NC}"
        echo "Please install kubectl manually: https://kubernetes.io/docs/tasks/tools/"
        return 1
    fi
}

# Function to install eksctl
install_eksctl() {
    echo -e "${YELLOW}Installing eksctl...${NC}"
    
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        echo "Installing eksctl for Linux..."
        curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
        sudo mv /tmp/eksctl /usr/local/bin
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        echo "Installing eksctl for macOS..."
        if command_exists brew; then
            brew tap weaveworks/tap
            brew install weaveworks/tap/eksctl
        else
            curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
            sudo mv /tmp/eksctl /usr/local/bin
        fi
    else
        echo -e "${RED}Unsupported OS. Please install eksctl manually:${NC}"
        echo "https://docs.aws.amazon.com/eks/latest/userguide/eksctl.html"
        return 1
    fi
    echo -e "${GREEN}eksctl installed successfully${NC}"
}

# Check prerequisites
echo -e "${YELLOW}Checking prerequisites...${NC}"

# Check AWS CLI
if ! command_exists aws; then
    echo -e "${RED}Error: AWS CLI is not installed${NC}"
    echo "Please install AWS CLI: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
    exit 1
else
    echo -e "${GREEN}✓ AWS CLI found${NC}"
fi

# Check and install eksctl if needed
if ! command_exists eksctl; then
    echo -e "${YELLOW}eksctl not found. Installing...${NC}"
    install_eksctl
    if [ $? -ne 0 ]; then
        exit 1
    fi
else
    echo -e "${GREEN}✓ eksctl found${NC}"
fi

# Check and install kubectl if needed
if ! command_exists kubectl; then
    echo -e "${YELLOW}kubectl not found. Installing...${NC}"
    install_kubectl
    if [ $? -ne 0 ]; then
        exit 1
    fi
else
    echo -e "${GREEN}✓ kubectl found${NC}"
fi

# Verify AWS credentials
echo -e "${YELLOW}Checking AWS credentials...${NC}"
if ! aws sts get-caller-identity >/dev/null 2>&1; then
    echo -e "${RED}Error: AWS credentials not configured${NC}"
    echo "Please run: aws configure"
    exit 1
else
    echo -e "${GREEN}✓ AWS credentials configured${NC}"
fi

# Check if cluster already exists
echo -e "${YELLOW}Checking if cluster exists...${NC}"
if eksctl get cluster --name $CLUSTER_NAME --region $REGION >/dev/null 2>&1; then
    echo -e "${GREEN}✓ Cluster $CLUSTER_NAME already exists${NC}"
    
    # Update kubeconfig for existing cluster
    echo -e "${YELLOW}Updating kubeconfig for existing cluster...${NC}"
    aws eks update-kubeconfig --region $REGION --name $CLUSTER_NAME
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Kubeconfig updated successfully${NC}"
        
        # Test kubectl connection
        echo -e "${YELLOW}Testing kubectl connection...${NC}"
        if kubectl get nodes >/dev/null 2>&1; then
            echo -e "${GREEN}✓ kubectl is working correctly${NC}"
            echo -e "${YELLOW}Current nodes in cluster:${NC}"
            kubectl get nodes
        else
            echo -e "${RED}✗ kubectl connection failed${NC}"
            echo "Please check your cluster status and try again"
            exit 1
        fi
        
        echo -e "${GREEN}Setup completed! Your existing cluster is ready to use.${NC}"
        echo -e "${YELLOW}Cluster Name: $CLUSTER_NAME${NC}"
        echo -e "${YELLOW}Region: $REGION${NC}"
        
        # Display cluster info
        echo -e "${YELLOW}Cluster Information:${NC}"
        eksctl get cluster --name $CLUSTER_NAME --region $REGION
        
    else
        echo -e "${RED}Failed to update kubeconfig${NC}"
        exit 1
    fi
    
    exit 0
fi

# If cluster doesn't exist, create it
echo -e "${GREEN}Creating new EKS cluster...${NC}"
echo -e "${YELLOW}This will take approximately 15-20 minutes...${NC}"

# Create EKS cluster
eksctl create cluster \
  --name $CLUSTER_NAME \
  --region $REGION \
  --nodegroup-name $NODE_GROUP_NAME \
  --node-type m5.large \
  --nodes 3 \
  --nodes-min 1 \
  --nodes-max 4 \
  --managed \
  --with-oidc \
  --full-ecr-access

# Check if cluster creation was successful
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ EKS cluster created successfully!${NC}"
    
    # Update kubeconfig
    echo -e "${YELLOW}Updating kubeconfig...${NC}"
    aws eks update-kubeconfig --region $REGION --name $CLUSTER_NAME
    
    # Verify cluster access
    echo -e "${YELLOW}Verifying cluster access...${NC}"
    kubectl get nodes
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ kubectl is working correctly${NC}"
        echo -e "${GREEN}EKS setup completed successfully!${NC}"
        echo -e "${YELLOW}Cluster Name: $CLUSTER_NAME${NC}"
        echo -e "${YELLOW}Region: $REGION${NC}"
        echo -e "${YELLOW}Node Group: $NODE_GROUP_NAME${NC}"
        
        # Display cluster info
        echo -e "${YELLOW}Cluster Information:${NC}"
        eksctl get cluster --name $CLUSTER_NAME --region $REGION
    else
        echo -e "${RED}kubectl verification failed${NC}"
        exit 1
    fi
else
    echo -e "${RED}Failed to create EKS cluster${NC}"
    exit 1
fi