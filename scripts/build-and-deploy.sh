#!/bin/bash

# Build Docker images
echo "Building Docker images..."

# Build pipeline image
sudo docker build -f docker/Dockerfile.pipeline -t housing-pipeline:latest .

# Build predictor image
sudo docker build -f docker/Dockerfile.predictor -t housing-predictor:latest .

# Tag and push to ECR (replace with your ECR URI)
ECR_URI="123456789012.dkr.ecr.us-west-2.amazonaws.com"

# Login to ECR
aws ecr get-login-password --region us-west-2 | docker login --username AWS --password-stdin $ECR_URI

# Tag and push images
sudo docker tag housing-pipeline:latest $ECR_URI/housing-pipeline:latest
sudo docker tag housing-predictor:latest $ECR_URI/housing-predictor:latest

sudo docker push $ECR_URI/housing-pipeline:latest
sudo docker push $ECR_URI/housing-predictor:latest

# Apply Kubernetes manifests
kubectl apply -f k8s/model-pvc.yaml
kubectl apply -f k8s/pipeline-rbac.yaml

echo "Build and deployment completed!"