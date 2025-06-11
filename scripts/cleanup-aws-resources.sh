#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
CLUSTER_NAME=${CLUSTER_NAME:-"housing-prediction-cluster"}
REGION=${AWS_REGION:-"us-west-2"}
ECR_REPOSITORY=${ECR_REPOSITORY:-"housing-price-prediction"}
NAMESPACE=${NAMESPACE:-"kubeflow"}

echo -e "${BLUE}=== AWS Resources Cleanup Script ===${NC}"
echo -e "${YELLOW}This script will delete ALL AWS resources created by the housing price prediction project${NC}"
echo -e "${RED}WARNING: This action is irreversible!${NC}"
echo ""

# Function to print status
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if AWS CLI is configured
check_aws_cli() {
    if ! command -v aws &> /dev/null; then
        print_error "AWS CLI is not installed"
        exit 1
    fi
    
    if ! aws sts get-caller-identity &> /dev/null; then
        print_error "AWS CLI is not configured or credentials are invalid"
        exit 1
    fi
    
    print_status "AWS CLI is configured"
}

# Function to check if kubectl is available
check_kubectl() {
    if ! command -v kubectl &> /dev/null; then
        print_warning "kubectl is not installed, skipping Kubernetes resource cleanup"
        return 1
    fi
    return 0
}

# Function to cleanup Kubeflow resources
cleanup_kubeflow() {
    print_status "Cleaning up Kubeflow resources..."
    
    if check_kubectl; then
        # Update kubeconfig
        aws eks update-kubeconfig --region $REGION --name $CLUSTER_NAME 2>/dev/null || true
        
        # Delete Kubeflow pipelines and related resources
        kubectl delete namespace $NAMESPACE --ignore-not-found=true --timeout=300s || true
        kubectl delete namespace kubeflow-user-example-com --ignore-not-found=true --timeout=300s || true
        kubectl delete namespace istio-system --ignore-not-found=true --timeout=300s || true
        kubectl delete namespace cert-manager --ignore-not-found=true --timeout=300s || true
        kubectl delete namespace knative-eventing --ignore-not-found=true --timeout=300s || true
        kubectl delete namespace knative-serving --ignore-not-found=true --timeout=300s || true
        
        # Delete custom resource definitions
        kubectl delete crd --all --ignore-not-found=true --timeout=300s || true
        
        # Delete cluster roles and bindings
        kubectl delete clusterrolebinding --all --ignore-not-found=true || true
        kubectl delete clusterrole --all --ignore-not-found=true || true
        
        print_status "Kubeflow resources cleanup completed"
    fi
}

# Function to delete EKS cluster
cleanup_eks_cluster() {
    print_status "Checking for EKS cluster: $CLUSTER_NAME"
    
    if aws eks describe-cluster --name $CLUSTER_NAME --region $REGION &> /dev/null; then
        print_status "Found EKS cluster: $CLUSTER_NAME"
        
        # Delete node groups first
        print_status "Deleting EKS node groups..."
        NODE_GROUPS=$(aws eks list-nodegroups --cluster-name $CLUSTER_NAME --region $REGION --query 'nodegroups[]' --output text 2>/dev/null || echo "")
        
        for nodegroup in $NODE_GROUPS; do
            if [ ! -z "$nodegroup" ]; then
                print_status "Deleting node group: $nodegroup"
                aws eks delete-nodegroup --cluster-name $CLUSTER_NAME --nodegroup-name $nodegroup --region $REGION || true
            fi
        done
        
        # Wait for node groups to be deleted
        if [ ! -z "$NODE_GROUPS" ]; then
            print_status "Waiting for node groups to be deleted..."
            for nodegroup in $NODE_GROUPS; do
                if [ ! -z "$nodegroup" ]; then
                    aws eks wait nodegroup-deleted --cluster-name $CLUSTER_NAME --nodegroup-name $nodegroup --region $REGION || true
                fi
            done
        fi
        
        # Delete the cluster
        print_status "Deleting EKS cluster: $CLUSTER_NAME"
        aws eks delete-cluster --name $CLUSTER_NAME --region $REGION
        
        # Wait for cluster deletion
        print_status "Waiting for cluster deletion to complete..."
        aws eks wait cluster-deleted --name $CLUSTER_NAME --region $REGION || true
        
        print_status "EKS cluster deleted successfully"
    else
        print_warning "EKS cluster $CLUSTER_NAME not found"
    fi
}

# Function to cleanup ECR repositories
cleanup_ecr() {
    print_status "Cleaning up ECR repositories..."
    
    # Delete ECR repository
    if aws ecr describe-repositories --repository-names $ECR_REPOSITORY --region $REGION &> /dev/null; then
        print_status "Deleting ECR repository: $ECR_REPOSITORY"
        aws ecr delete-repository --repository-name $ECR_REPOSITORY --region $REGION --force || true
        print_status "ECR repository deleted"
    else
        print_warning "ECR repository $ECR_REPOSITORY not found"
    fi
}

# Function to cleanup IAM roles and policies
cleanup_iam() {
    print_status "Cleaning up IAM roles and policies..."
    
    # List of IAM roles that might be created
    IAM_ROLES=(
        "eksServiceRole"
        "eksNodeInstanceRole"
        "housing-prediction-eks-cluster-role"
        "housing-prediction-eks-node-role"
        "AmazonEKSClusterServiceRole"
        "AmazonEKSNodeInstanceRole"
    )
    
    for role in "${IAM_ROLES[@]}"; do
        if aws iam get-role --role-name $role &> /dev/null; then
            print_status "Deleting IAM role: $role"
            
            # Detach managed policies
            ATTACHED_POLICIES=$(aws iam list-attached-role-policies --role-name $role --query 'AttachedPolicies[].PolicyArn' --output text 2>/dev/null || echo "")
            for policy_arn in $ATTACHED_POLICIES; do
                if [ ! -z "$policy_arn" ]; then
                    aws iam detach-role-policy --role-name $role --policy-arn $policy_arn || true
                fi
            done
            
            # Delete inline policies
            INLINE_POLICIES=$(aws iam list-role-policies --role-name $role --query 'PolicyNames[]' --output text 2>/dev/null || echo "")
            for policy_name in $INLINE_POLICIES; do
                if [ ! -z "$policy_name" ]; then
                    aws iam delete-role-policy --role-name $role --policy-name $policy_name || true
                fi
            done
            
            # Delete instance profiles
            INSTANCE_PROFILES=$(aws iam list-instance-profiles-for-role --role-name $role --query 'InstanceProfiles[].InstanceProfileName' --output text 2>/dev/null || echo "")
            for profile in $INSTANCE_PROFILES; do
                if [ ! -z "$profile" ]; then
                    aws iam remove-role-from-instance-profile --instance-profile-name $profile --role-name $role || true
                    aws iam delete-instance-profile --instance-profile-name $profile || true
                fi
            done
            
            # Delete the role
            aws iam delete-role --role-name $role || true
            print_status "IAM role $role deleted"
        fi
    done
}

# Function to cleanup VPC and networking resources
cleanup_networking() {
    print_status "Cleaning up VPC and networking resources..."
    
    # Find VPCs with the cluster tag
    VPC_IDS=$(aws ec2 describe-vpcs --filters "Name=tag:kubernetes.io/cluster/$CLUSTER_NAME,Values=shared,owned" --query 'Vpcs[].VpcId' --output text --region $REGION 2>/dev/null || echo "")
    
    for vpc_id in $VPC_IDS; do
        if [ ! -z "$vpc_id" ]; then
            print_status "Cleaning up VPC: $vpc_id"
            
            # Delete NAT Gateways
            NAT_GATEWAYS=$(aws ec2 describe-nat-gateways --filter "Name=vpc-id,Values=$vpc_id" --query 'NatGateways[].NatGatewayId' --output text --region $REGION 2>/dev/null || echo "")
            for nat_gw in $NAT_GATEWAYS; do
                if [ ! -z "$nat_gw" ]; then
                    print_status "Deleting NAT Gateway: $nat_gw"
                    aws ec2 delete-nat-gateway --nat-gateway-id $nat_gw --region $REGION || true
                fi
            done
            
            # Delete Internet Gateways
            IGW_IDS=$(aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=$vpc_id" --query 'InternetGateways[].InternetGatewayId' --output text --region $REGION 2>/dev/null || echo "")
            for igw_id in $IGW_IDS; do
                if [ ! -z "$igw_id" ]; then
                    print_status "Detaching and deleting Internet Gateway: $igw_id"
                    aws ec2 detach-internet-gateway --internet-gateway-id $igw_id --vpc-id $vpc_id --region $REGION || true
                    aws ec2 delete-internet-gateway --internet-gateway-id $igw_id --region $REGION || true
                fi
            done
            
            # Delete subnets
            SUBNET_IDS=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$vpc_id" --query 'Subnets[].SubnetId' --output text --region $REGION 2>/dev/null || echo "")
            for subnet_id in $SUBNET_IDS; do
                if [ ! -z "$subnet_id" ]; then
                    print_status "Deleting subnet: $subnet_id"
                    aws ec2 delete-subnet --subnet-id $subnet_id --region $REGION || true
                fi
            done
            
            # Delete route tables (except main)
            ROUTE_TABLE_IDS=$(aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$vpc_id" "Name=association.main,Values=false" --query 'RouteTables[].RouteTableId' --output text --region $REGION 2>/dev/null || echo "")
            for rt_id in $ROUTE_TABLE_IDS; do
                if [ ! -z "$rt_id" ]; then
                    print_status "Deleting route table: $rt_id"
                    aws ec2 delete-route-table --route-table-id $rt_id --region $REGION || true
                fi
            done
            
            # Delete security groups (except default)
            SG_IDS=$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$vpc_id" --query 'SecurityGroups[?GroupName!=`default`].GroupId' --output text --region $REGION 2>/dev/null || echo "")
            for sg_id in $SG_IDS; do
                if [ ! -z "$sg_id" ]; then
                    print_status "Deleting security group: $sg_id"
                    aws ec2 delete-security-group --group-id $sg_id --region $REGION || true
                fi
            done
            
            # Finally delete the VPC
            print_status "Deleting VPC: $vpc_id"
            aws ec2 delete-vpc --vpc-id $vpc_id --region $REGION || true
        fi
    done
}

# Function to cleanup CloudFormation stacks
cleanup_cloudformation() {
    print_status "Cleaning up CloudFormation stacks..."
    
    # Common stack name patterns
    STACK_PATTERNS=(
        "eksctl-$CLUSTER_NAME-*"
        "housing-prediction-*"
        "*$CLUSTER_NAME*"
    )
    
    for pattern in "${STACK_PATTERNS[@]}"; do
        STACKS=$(aws cloudformation list-stacks --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE --query "StackSummaries[?contains(StackName, '$(echo $pattern | sed 's/\*//')')].[StackName]" --output text --region $REGION 2>/dev/null || echo "")
        
        for stack in $STACKS; do
            if [ ! -z "$stack" ]; then
                print_status "Deleting CloudFormation stack: $stack"
                aws cloudformation delete-stack --stack-name $stack --region $REGION || true
            fi
        done
    done
}

# Function to cleanup S3 buckets
cleanup_s3() {
    print_status "Cleaning up S3 buckets..."
    
    # Find buckets related to the project
    BUCKETS=$(aws s3api list-buckets --query "Buckets[?contains(Name, 'housing-prediction') || contains(Name, 'kubeflow') || contains(Name, '$CLUSTER_NAME')].Name" --output text 2>/dev/null || echo "")
    
    for bucket in $BUCKETS; do
        if [ ! -z "$bucket" ]; then
            print_status "Deleting S3 bucket: $bucket"
            # Delete all objects first
            aws s3 rm s3://$bucket --recursive || true
            # Delete the bucket
            aws s3api delete-bucket --bucket $bucket --region $REGION || true
        fi
    done
}

# Main cleanup function
main() {
    echo -e "${YELLOW}Starting cleanup process...${NC}"
    echo ""
    
    # Confirmation prompt
    read -p "Are you sure you want to delete all AWS resources? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        echo "Cleanup cancelled."
        exit 0
    fi
    
    check_aws_cli
    
    echo ""
    echo -e "${BLUE}=== Cleanup Process Started ===${NC}"
    
    # Cleanup in order
    cleanup_kubeflow
    cleanup_eks_cluster
    cleanup_ecr
    cleanup_s3
    cleanup_cloudformation
    cleanup_iam
    cleanup_networking
    
    echo ""
    echo -e "${GREEN}=== Cleanup Process Completed ===${NC}"
    echo -e "${GREEN}All AWS resources have been cleaned up successfully!${NC}"
    echo ""
    echo -e "${BLUE}To recreate the infrastructure, run:${NC}"
    echo -e "${YELLOW}1. ./scripts/setup-eks.sh${NC}"
    echo -e "${YELLOW}2. ./scripts/install-kubeflow.sh${