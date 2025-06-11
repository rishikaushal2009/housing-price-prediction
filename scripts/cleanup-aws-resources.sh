#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration - should match setup-eks.sh
CLUSTER_NAME=${CLUSTER_NAME:-"housing-ml-cluster1"}
REGION=${AWS_REGION:-"us-west-2"}
ECR_REPOSITORY=${ECR_REPOSITORY:-"housing-price-prediction"}
NAMESPACE=${NAMESPACE:-"kubeflow"}
NODE_GROUP_NAME=${NODE_GROUP_NAME:-"housing-prediction-nodes"}

# Additional resources used by setup/install/deploy scripts
ADDITIONAL_NAMESPACES=("kubeflow-user-example-com" "istio-system" "cert-manager" "knative-eventing" "knative-serving")
PVC_NAMES=("minio-pvc" "mysql-pv-claim" "model-pvc")
DEPLOYMENTS=("housing-price-predictor")
SERVICES=("housing-price-predictor-service")

echo -e "${BLUE}=== AWS Resources Cleanup Script ===${NC}"
echo -e "${YELLOW}This script will delete ALL AWS resources created by the housing price prediction project${NC}"
echo -e "${RED}WARNING: This action is irreversible!${NC}"
echo ""

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_aws_cli() {
    if ! command -v aws &>/dev/null; then
        print_error "AWS CLI not installed"
        exit 1
    fi
    
    if ! aws sts get-caller-identity &>/dev/null; then
        print_error "AWS credentials not configured"
        exit 1
    fi
    
    print_status "AWS CLI configured correctly"
}

check_kubectl() {
    if ! command -v kubectl &>/dev/null; then
        print_warning "kubectl not installed"
        return 1
    fi
    return 0
}

cleanup_kubernetes_resources() {
    print_status "Cleaning up Kubernetes resources..."
    
    if check_kubectl; then
        # Update kubeconfig
        aws eks update-kubeconfig --region $REGION --name $CLUSTER_NAME 2>/dev/null || true

        # Delete deployments and services
        for deploy in "${DEPLOYMENTS[@]}"; do
            print_status "Deleting deployment: $deploy"
            kubectl delete deployment $deploy -n $NAMESPACE --ignore-not-found=true || true
        done
        
        for svc in "${SERVICES[@]}"; do
            print_status "Deleting service: $svc"
            kubectl delete svc $svc -n $NAMESPACE --ignore-not-found=true || true
        done

        # Delete PVCs
        for pvc in "${PVC_NAMES[@]}"; do
            print_status "Deleting PVC: $pvc"
            kubectl delete pvc $pvc -n $NAMESPACE --ignore-not-found=true || true
        done

        # Delete all pipeline runs and workflows
        print_status "Deleting Kubeflow pipelines and workflows"
        kubectl delete workflow --all -n $NAMESPACE --ignore-not-found=true || true
        kubectl delete pipelinerun --all -n $NAMESPACE --ignore-not-found=true || true

        # Delete all namespaces
        for ns in "${ADDITIONAL_NAMESPACES[@]}"; do
            print_status "Deleting namespace: $ns"
            kubectl delete ns $ns --ignore-not-found=true --timeout=180s || true
        done
        kubectl delete ns $NAMESPACE --ignore-not-found=true --timeout=180s || true

        print_status "Kubernetes resources cleaned up"
    fi
}

cleanup_eks_cluster() {
    print_status "Cleaning up EKS Cluster: $CLUSTER_NAME"
    
    # Check if cluster exists
    if ! aws eks describe-cluster --name $CLUSTER_NAME --region $REGION &>/dev/null; then
        print_warning "EKS cluster $CLUSTER_NAME not found"
        return 0
    fi

    # Delete node groups first
    print_status "Deleting EKS node groups..."
    NODE_GROUPS=$(aws eks list-nodegroups --cluster-name $CLUSTER_NAME --region $REGION --query 'nodegroups[]' --output text 2>/dev/null || echo "")
    
    for ng in $NODE_GROUPS; do
        if [ ! -z "$ng" ]; then
            print_status "Deleting node group: $ng"
            aws eks delete-nodegroup --cluster-name $CLUSTER_NAME --nodegroup-name $ng --region $REGION || true
        fi
    done
    
    # Wait for node groups to be deleted
    for ng in $NODE_GROUPS; do
        if [ ! -z "$ng" ]; then
            print_status "Waiting for node group deletion: $ng"
            aws eks wait nodegroup-deleted --cluster-name $CLUSTER_NAME --nodegroup-name $ng --region $REGION || true
        fi
    done

    # Delete the cluster
    print_status "Deleting EKS cluster: $CLUSTER_NAME"
    aws eks delete-cluster --name $CLUSTER_NAME --region $REGION || true
    
    # Wait for cluster deletion
    print_status "Waiting for cluster deletion to complete..."
    aws eks wait cluster-deleted --name $CLUSTER_NAME --region $REGION || true
    
    print_status "EKS Cluster $CLUSTER_NAME deleted"
}

cleanup_ecr() {
    print_status "Cleaning up ECR repositories..."
    
    if aws ecr describe-repositories --repository-names $ECR_REPOSITORY --region $REGION &>/dev/null; then
        print_status "Deleting ECR repository: $ECR_REPOSITORY"
        aws ecr delete-repository --repository-name $ECR_REPOSITORY --region $REGION --force || true
        print_status "ECR repository deleted"
    else
        print_warning "ECR repository $ECR_REPOSITORY not found"
    fi
}

cleanup_iam() {
    print_status "Cleaning up IAM roles and policies..."
    
    # Common IAM roles created by EKS setup
    ROLES=(
        "eksServiceRole"
        "eksNodeInstanceRole" 
        "housing-prediction-eks-cluster-role"
        "housing-prediction-eks-node-role"
        "${CLUSTER_NAME}-cluster-ServiceRole"
        "${CLUSTER_NAME}-nodegroup-NodeInstanceRole"
        "eksctl-${CLUSTER_NAME}-cluster-ServiceRole"
        "eksctl-${CLUSTER_NAME}-nodegroup-${NODE_GROUP_NAME}-NodeInstanceRole"
    )
    
    for role in "${ROLES[@]}"; do
        if aws iam get-role --role-name $role &>/dev/null; then
            print_status "Cleaning up IAM role: $role"
            
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
            
            # Remove from instance profiles
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

cleanup_cloudformation() {
    print_status "Cleaning up CloudFormation stacks..."
    
    # Get all stacks and filter by patterns
    ALL_STACKS=$(aws cloudformation list-stacks --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE --query 'StackSummaries[].StackName' --output text --region $REGION 2>/dev/null || echo "")
    
    for stack in $ALL_STACKS; do
        if [[ $stack == *"eksctl-$CLUSTER_NAME"* ]] || [[ $stack == *"$CLUSTER_NAME"* ]] || [[ $stack == *"housing-prediction"* ]]; then
            print_status "Deleting CloudFormation stack: $stack"
            aws cloudformation delete-stack --stack-name $stack --region $REGION || true
        fi
    done
    
    print_status "CloudFormation stacks cleanup initiated"
}

cleanup_s3() {
    print_status "Cleaning up S3 buckets..."
    
    # Get all buckets and filter by patterns
    ALL_BUCKETS=$(aws s3api list-buckets --query 'Buckets[].Name' --output text 2>/dev/null || echo "")
    
    for bucket in $ALL_BUCKETS; do
        if [[ $bucket == *"$CLUSTER_NAME"* ]] || [[ $bucket == *"kubeflow"* ]] || [[ $bucket == *"housing-prediction"* ]]; then
            print_status "Deleting S3 bucket: $bucket"
            # Delete all objects and versions first
            aws s3 rm s3://$bucket --recursive || true
            # Delete the bucket
            aws s3api delete-bucket --bucket $bucket --region $REGION || true
        fi
    done
    
    print_status "S3 buckets cleaned up"
}

cleanup_load_balancers() {
    print_status "Cleaning up Load Balancers..."
    
    # Delete Application Load Balancers
    ALB_ARNS=$(aws elbv2 describe-load-balancers --query "LoadBalancers[?contains(LoadBalancerName, '$CLUSTER_NAME') || contains(LoadBalancerName, 'housing-prediction')].LoadBalancerArn" --output text --region $REGION 2>/dev/null || echo "")
    
    for alb_arn in $ALB_ARNS; do
        if [ ! -z "$alb_arn" ]; then
            print_status "Deleting Application Load Balancer: $alb_arn"
            aws elbv2 delete-load-balancer --load-balancer-arn $alb_arn --region $REGION || true
        fi
    done
    
    # Delete Classic Load Balancers
    CLB_NAMES=$(aws elb describe-load-balancers --query "LoadBalancerDescriptions[?contains(LoadBalancerName, '$CLUSTER_NAME') || contains(LoadBalancerName, 'housing-prediction')].LoadBalancerName" --output text --region $REGION 2>/dev/null || echo "")
    
    for clb_name in $CLB_NAMES; do
        if [ ! -z "$clb_name" ]; then
            print_status "Deleting Classic Load Balancer: $clb_name"
            aws elb delete-load-balancer --load-balancer-name $clb_name --region $REGION || true
        fi
    done
    
    print_status "Load Balancers cleaned up"
}

cleanup_security_groups() {
    print_status "Cleaning up Security Groups..."
    
    # Find security groups with cluster tags or names
    SG_IDS=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=*$CLUSTER_NAME*" --query 'SecurityGroups[].GroupId' --output text --region $REGION 2>/dev/null || echo "")
    
    for sg_id in $SG_IDS; do
        if [ ! -z "$sg_id" ]; then
            print_status "Deleting Security Group: $sg_id"
            aws ec2 delete-security-group --group-id $sg_id --region $REGION || true
        fi
    done
    
    print_status "Security Groups cleaned up"
}

# Main execution
main() {
    echo -e "${YELLOW}Starting cleanup process...${NC}"
    echo ""
    
    # Confirmation prompt
    read -p "Are you sure you want to delete all AWS resources for the housing prediction project? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        echo "Cleanup cancelled."
        exit 0
    fi
    
    check_aws_cli
    
    echo ""
    echo -e "${BLUE}=== Cleanup Process Started ===${NC}"
    
    # Run cleanup functions in order
    cleanup_kubernetes_resources
    cleanup_load_balancers
    cleanup_eks_cluster
    cleanup_ecr
    cleanup_s3
    cleanup_cloudformation
    cleanup_iam
    cleanup_security_groups
    
    echo ""
    echo -e "${GREEN}=== Cleanup Process Completed ===${NC}"
    echo -e "${GREEN}All AWS resources have been cleaned up successfully!${NC}"
    echo ""
    echo -e "${BLUE}To recreate the infrastructure, run the following scripts in order:${NC}"
    echo -e "${YELLOW}1. ./scripts/setup-eks.sh${NC}"
    echo -e "${YELLOW}2. ./scripts/install-kubeflow.sh${NC}"
    echo -e "${YELLOW}3. ./scripts/build-and-deploy.sh${NC}"
    echo ""
}

# Run main function
main "$@"
