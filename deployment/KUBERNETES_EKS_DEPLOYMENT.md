# Kubernetes (EKS) Deployment Guide - SnapClass AI Attendance

This guide covers deploying SnapClass to AWS EKS (Elastic Kubernetes Service) using Docker containers and Kubernetes orchestration.

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Prerequisites](#prerequisites)
3. [Local Development with Docker](#local-development-with-docker)
4. [EKS Cluster Setup](#eks-cluster-setup)
5. [Container Registry Setup](#container-registry-setup)
6. [Kubernetes Deployment](#kubernetes-deployment)
7. [Monitoring & Logging](#monitoring--logging)
8. [CI/CD Pipeline](#cicd-pipeline)
9. [Troubleshooting](#troubleshooting)

## Architecture Overview

```
Users → Route 53 → ALB (Ingress) → EKS Cluster
                                      ↓
                            [Pod] [Pod] [Pod] (Auto-scaling 3-10)
                                      ↓
                            RDS PostgreSQL + ElastiCache Redis
                                      ↓
                                    S3 Storage
```

### Components

- **EKS Cluster**: Managed Kubernetes cluster (3 worker nodes minimum)
- **Docker Containers**: Application packaged in containers
- **ECR**: Elastic Container Registry for Docker images
- **ALB Ingress**: Application Load Balancer for traffic routing
- **HPA**: Horizontal Pod Autoscaler (3-10 pods)
- **RDS**: PostgreSQL database (Multi-AZ)
- **ElastiCache**: Redis for caching
- **S3**: Object storage for assets

## Prerequisites

### Tools Required

```bash
# Install kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# Install eksctl
curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
sudo mv /tmp/eksctl /usr/local/bin

# Install Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Install AWS CLI
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install

# Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
```

### AWS Resources

- AWS Account with admin access
- VPC with public and private subnets
- RDS PostgreSQL instance
- ElastiCache Redis cluster
- S3 bucket
- ACM SSL certificate
- Route 53 hosted zone

## Local Development with Docker

### Step 1: Build Docker Image

```bash
# Build the image
docker build -t snapclass:latest .

# Test locally
docker run -p 8501:8501 -p 8502:8502 \
  -e DB_HOST=localhost \
  -e DB_PORT=5432 \
  -e DB_NAME=snapclass \
  -e DB_USERNAME=admin \
  -e DB_PASSWORD=password \
  snapclass:latest
```

### Step 2: Use Docker Compose

```bash
# Start all services (app + postgres + redis)
docker-compose up -d

# View logs
docker-compose logs -f app

# Stop services
docker-compose down

# Rebuild and restart
docker-compose up -d --build
```

### Step 3: Test Application

```bash
# Access application
open http://localhost:8501

# Check health
curl http://localhost:8502/healthz
```

## EKS Cluster Setup

### Step 1: Create EKS Cluster

```bash
# Create cluster configuration
cat > eks-cluster.yaml << EOF
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig

metadata:
  name: snapclass-prod
  region: us-east-1
  version: "1.28"

vpc:
  id: "vpc-xxxxx"  # Your VPC ID
  subnets:
    private:
      us-east-1a: { id: subnet-xxxxx }
      us-east-1b: { id: subnet-xxxxx }
    public:
      us-east-1a: { id: subnet-xxxxx }
      us-east-1b: { id: subnet-xxxxx }

managedNodeGroups:
  - name: snapclass-nodes
    instanceType: t3.large
    desiredCapacity: 3
    minSize: 3
    maxSize: 10
    privateNetworking: true
    labels:
      role: application
    tags:
      Environment: production
      Application: snapclass
    iam:
      withAddonPolicies:
        imageBuilder: true
        autoScaler: true
        externalDNS: true
        certManager: true
        appMesh: true
        ebs: true
        fsx: true
        efs: true
        albIngress: true
        cloudWatch: true

addons:
  - name: vpc-cni
  - name: coredns
  - name: kube-proxy
  - name: aws-ebs-csi-driver

iam:
  withOIDC: true
  serviceAccounts:
  - metadata:
      name: aws-load-balancer-controller
      namespace: kube-system
    wellKnownPolicies:
      awsLoadBalancerController: true
  - metadata:
      name: snapclass-sa
      namespace: snapclass
    attachPolicyARNs:
    - "arn:aws:iam::aws:policy/AmazonS3FullAccess"
    - "arn:aws:iam::aws:policy/SecretsManagerReadWrite"

cloudWatch:
  clusterLogging:
    enableTypes: ["*"]
EOF

# Create cluster
eksctl create cluster -f eks-cluster.yaml
```

### Step 2: Configure kubectl

```bash
# Update kubeconfig
aws eks update-kubeconfig --region us-east-1 --name snapclass-prod

# Verify connection
kubectl get nodes
kubectl get pods --all-namespaces
```

### Step 3: Install AWS Load Balancer Controller

```bash
# Add Helm repo
helm repo add eks https://aws.github.io/eks-charts
helm repo update

# Install controller
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=snapclass-prod \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller

# Verify installation
kubectl get deployment -n kube-system aws-load-balancer-controller
```

### Step 4: Install Metrics Server

```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# Verify
kubectl get deployment metrics-server -n kube-system
```

## Container Registry Setup

### Step 1: Create ECR Repository

```bash
# Create repository
aws ecr create-repository \
  --repository-name snapclass \
  --region us-east-1 \
  --image-scanning-configuration scanOnPush=true \
  --encryption-configuration encryptionType=AES256

# Get repository URI
export ECR_REPO=$(aws ecr describe-repositories \
  --repository-names snapclass \
  --query 'repositories[0].repositoryUri' \
  --output text)

echo $ECR_REPO
```

### Step 2: Build and Push Image

```bash
# Login to ECR
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin $ECR_REPO

# Build image
docker build -t snapclass:latest .

# Tag image
docker tag snapclass:latest $ECR_REPO:latest
docker tag snapclass:latest $ECR_REPO:v1.0.0

# Push image
docker push $ECR_REPO:latest
docker push $ECR_REPO:v1.0.0
```

### Step 3: Set Up Image Scanning

```bash
# Enable vulnerability scanning
aws ecr put-image-scanning-configuration \
  --repository-name snapclass \
  --image-scanning-configuration scanOnPush=true

# View scan results
aws ecr describe-image-scan-findings \
  --repository-name snapclass \
  --image-id imageTag=latest
```

## Kubernetes Deployment

### Step 1: Update Kubernetes Manifests

```bash
# Update deployment.yaml with your ECR image
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export AWS_REGION=us-east-1

sed -i "s|<AWS_ACCOUNT_ID>|$AWS_ACCOUNT_ID|g" k8s/deployment.yaml
sed -i "s|<REGION>|$AWS_REGION|g" k8s/deployment.yaml
sed -i "s|<AWS_ACCOUNT_ID>|$AWS_ACCOUNT_ID|g" k8s/serviceaccount.yaml
```

### Step 2: Create Secrets

```bash
# Create namespace
kubectl apply -f k8s/namespace.yaml

# Create secrets from AWS Secrets Manager
kubectl create secret generic snapclass-secrets \
  --from-literal=DB_HOST=$(aws ssm get-parameter --name /snapclass/prod/db/host --query 'Parameter.Value' --output text) \
  --from-literal=DB_USERNAME=$(aws secretsmanager get-secret-value --secret-id snapclass/prod/db/credentials --query 'SecretString' --output text | jq -r '.username') \
  --from-literal=DB_PASSWORD=$(aws secretsmanager get-secret-value --secret-id snapclass/prod/db/credentials --query 'SecretString' --output text | jq -r '.password') \
  --from-literal=REDIS_ENDPOINT=$(aws ssm get-parameter --name /snapclass/prod/redis/endpoint --query 'Parameter.Value' --output text) \
  --from-literal=REDIS_AUTH_TOKEN=your-redis-token \
  --from-literal=S3_BUCKET=$(aws ssm get-parameter --name /snapclass/prod/s3/bucket --query 'Parameter.Value' --output text) \
  --from-literal=AWS_REGION=$AWS_REGION \
  --from-literal=APP_SECRET_KEY=$(openssl rand -base64 32) \
  -n snapclass
```

### Step 3: Deploy Application

```bash
# Apply all manifests
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/configmap.yaml
kubectl apply -f k8s/serviceaccount.yaml
kubectl apply -f k8s/deployment.yaml
kubectl apply -f k8s/service.yaml
kubectl apply -f k8s/hpa.yaml
kubectl apply -f k8s/ingress.yaml

# Verify deployment
kubectl get all -n snapclass
kubectl get ingress -n snapclass
```

### Step 4: Monitor Deployment

```bash
# Watch pods
kubectl get pods -n snapclass -w

# Check pod logs
kubectl logs -f deployment/snapclass-app -n snapclass

# Describe pod for issues
kubectl describe pod <pod-name> -n snapclass

# Check HPA status
kubectl get hpa -n snapclass
```

### Step 5: Get Application URL

```bash
# Get ALB DNS name
kubectl get ingress snapclass-ingress -n snapclass -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'

# Update Route 53
aws route53 change-resource-record-sets \
  --hosted-zone-id <your-zone-id> \
  --change-batch '{
    "Changes": [{
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "yourdomain.com",
        "Type": "A",
        "AliasTarget": {
          "HostedZoneId": "<alb-hosted-zone-id>",
          "DNSName": "<alb-dns-name>",
          "EvaluateTargetHealth": true
        }
      }
    }]
  }'
```

## Monitoring & Logging

### Install Prometheus & Grafana

```bash
# Add Helm repos
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

# Install Prometheus
helm install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false

# Install Grafana
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80

# Get Grafana password
kubectl get secret -n monitoring prometheus-grafana -o jsonpath="{.data.admin-password}" | base64 --decode
```

### Configure CloudWatch Container Insights

```bash
# Install CloudWatch agent
kubectl apply -f https://raw.githubusercontent.com/aws-samples/amazon-cloudwatch-container-insights/latest/k8s-deployment-manifest-templates/deployment-mode/daemonset/container-insights-monitoring/quickstart/cwagent-fluentd-quickstart.yaml

# Verify
kubectl get pods -n amazon-cloudwatch
```

### View Logs

```bash
# Application logs
kubectl logs -f deployment/snapclass-app -n snapclass

# All pods logs
kubectl logs -f -l app=snapclass -n snapclass --all-containers=true

# Previous pod logs
kubectl logs deployment/snapclass-app -n snapclass --previous

# CloudWatch Logs Insights query
aws logs start-query \
  --log-group-name /aws/eks/snapclass-prod/cluster \
  --start-time $(date -u -d '1 hour ago' +%s) \
  --end-time $(date -u +%s) \
  --query-string 'fields @timestamp, @message | filter @message like /ERROR/ | sort @timestamp desc | limit 20'
```

## CI/CD Pipeline

### GitHub Actions Workflow

Create `.github/workflows/deploy-eks.yml`:

```yaml
name: Deploy to EKS

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

env:
  AWS_REGION: us-east-1
  EKS_CLUSTER: snapclass-prod
  ECR_REPOSITORY: snapclass

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
    - name: Checkout code
      uses: actions/checkout@v3

    - name: Configure AWS credentials
      uses: aws-actions/configure-aws-credentials@v2
      with:
        aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
        aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
        aws-region: ${{ env.AWS_REGION }}

    - name: Login to Amazon ECR
      id: login-ecr
      uses: aws-actions/amazon-ecr-login@v1

    - name: Build, tag, and push image to Amazon ECR
      env:
        ECR_REGISTRY: ${{ steps.login-ecr.outputs.registry }}
        IMAGE_TAG: ${{ github.sha }}
      run: |
        docker build -t $ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG .
        docker push $ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG
        docker tag $ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG $ECR_REGISTRY/$ECR_REPOSITORY:latest
        docker push $ECR_REGISTRY/$ECR_REPOSITORY:latest

    - name: Update kube config
      run: aws eks update-kubeconfig --name $EKS_CLUSTER --region $AWS_REGION

    - name: Deploy to EKS
      env:
        ECR_REGISTRY: ${{ steps.login-ecr.outputs.registry }}
        IMAGE_TAG: ${{ github.sha }}
      run: |
        kubectl set image deployment/snapclass-app snapclass=$ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG -n snapclass
        kubectl rollout status deployment/snapclass-app -n snapclass
```

## Troubleshooting

### Pod Not Starting

```bash
# Check pod status
kubectl get pods -n snapclass

# Describe pod
kubectl describe pod <pod-name> -n snapclass

# Check events
kubectl get events -n snapclass --sort-by='.lastTimestamp'

# Check logs
kubectl logs <pod-name> -n snapclass
```

### Image Pull Errors

```bash
# Verify ECR permissions
aws ecr get-login-password --region us-east-1

# Check service account
kubectl describe sa snapclass-sa -n snapclass

# Verify image exists
aws ecr describe-images --repository-name snapclass
```

### Health Check Failing

```bash
# Test health endpoint from pod
kubectl exec -it <pod-name> -n snapclass -- curl http://localhost:8502/healthz

# Check service endpoints
kubectl get endpoints -n snapclass

# Verify target group health
aws elbv2 describe-target-health --target-group-arn <tg-arn>
```

### Database Connection Issues

```bash
# Test database connectivity from pod
kubectl exec -it <pod-name> -n snapclass -- bash
psql -h $DB_HOST -U $DB_USERNAME -d $DB_NAME

# Check security groups
aws ec2 describe-security-groups --group-ids <rds-sg-id>

# Verify secrets
kubectl get secret snapclass-secrets -n snapclass -o yaml
```

### Scaling Issues

```bash
# Check HPA status
kubectl get hpa -n snapclass
kubectl describe hpa snapclass-hpa -n snapclass

# Check metrics server
kubectl top nodes
kubectl top pods -n snapclass

# Manual scaling
kubectl scale deployment snapclass-app --replicas=5 -n snapclass
```

## Cost Optimization

### EKS Cluster Costs

- **Control Plane**: $0.10/hour (~$73/month)
- **Worker Nodes** (3x t3.large): ~$150/month
- **Load Balancer**: ~$20/month
- **Data Transfer**: Variable
- **Total**: ~$250-300/month

### Optimization Strategies

1. **Use Spot Instances** for non-critical workloads
2. **Right-size pods** based on actual resource usage
3. **Enable Cluster Autoscaler** to scale nodes
4. **Use Fargate** for serverless pods (optional)
5. **Implement pod disruption budgets**

## Security Best Practices

- ✅ Use IRSA (IAM Roles for Service Accounts)
- ✅ Enable pod security policies
- ✅ Use network policies for pod-to-pod communication
- ✅ Scan container images for vulnerabilities
- ✅ Rotate secrets regularly
- ✅ Enable audit logging
- ✅ Use private subnets for worker nodes
- ✅ Implement least privilege IAM policies

## Next Steps

1. Set up monitoring dashboards in Grafana
2. Configure alerting rules in Prometheus
3. Implement backup strategy for persistent data
4. Set up disaster recovery procedures
5. Document runbooks for common operations

---

**Document Version**: 1.0  
**Last Updated**: 2026-09-25  
**Status**: Production Ready