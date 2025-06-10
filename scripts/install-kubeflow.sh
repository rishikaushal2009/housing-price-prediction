#!/bin/bash

# Install Kubeflow Pipelines
export PIPELINE_VERSION=1.8.5
kubectl apply -k "github.com/kubeflow/pipelines/manifests/kustomize/cluster-scoped-resources?ref=$PIPELINE_VERSION"
kubectl wait --for condition=established --timeout=60s crd/applications.app.k8s.io
kubectl apply -k "github.com/kubeflow/pipelines/manifests/kustomize/env/platform-agnostic-pns?ref=$PIPELINE_VERSION"

# Wait for deployment
kubectl wait --for=condition=available --timeout=600s deployment/ml-pipeline -n kubeflow

# Get the external IP
echo "Waiting for LoadBalancer IP..."
kubectl get svc ml-pipeline-ui -n kubeflow -w