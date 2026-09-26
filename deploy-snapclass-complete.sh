#!/bin/bash

################################################################################
# SnapClass AI Attendance - Complete AWS Deployment Script
# 
# This script automates the entire deployment process for SnapClass application
# on AWS EC2 with Auto Scaling, Load Balancer, RDS PostgreSQL, and S3.
#
# Prerequisites:
# - AWS CLI installed and configured (aws configure)
# - Appropriate IAM permissions
# - Run from Ubuntu EC2 instance or local Linux/Mac
#
# Usage: ./deploy-snapclass-complete.sh
#
# Author: Bob
# Version: 1.0
################################################################################

set -e  # Exit on any error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Configuration Variables
export AWS_REGION="${AWS_REGION:-us-east-1}"
export PROJECT_NAME="snapclass"
export ENVIRONMENT="prod"
export DB_PASSWORD="ChangeThisSecurePassword123!"  # CHANGE THIS!
export APP_SECRET_KEY=$(openssl rand -base64 32)

log_info "Starting SnapClass AWS Deployment..."
log_info "Region: $AWS_REGION"
log_info "Project: $PROJECT_NAME"
log_info "Environment: $ENVIRONMENT"

################################################################################
# Phase 1: Prerequisites Check
################################################################################

log_info "Phase 1: Checking prerequisites..."

# Check AWS CLI
if ! command -v aws &> /dev/null; then
    log_error "AWS CLI not found. Please install it first."
    exit 1
fi

# Check AWS credentials
if ! aws sts get-caller-identity &> /dev/null; then
    log_error "AWS credentials not configured. Run 'aws configure' first."
    exit 1
fi

export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
log_success "AWS Account ID: $AWS_ACCOUNT_ID"

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    log_warning "jq not found. Installing..."
    sudo apt-get update && sudo apt-get install -y jq
fi

################################################################################
# Phase 2: VPC and Network Setup
################################################################################

log_info "Phase 2: Creating VPC and Network Infrastructure..."

# Create VPC
log_info "Creating VPC..."
VPC_ID=$(aws ec2 create-vpc \
    --cidr-block 10.0.0.0/16 \
    --tag-specifications "ResourceType=vpc,Tags=[{Key=Name,Value=${PROJECT_NAME}-${ENVIRONMENT}-vpc}]" \
    --query 'Vpc.VpcId' \
    --output text)

log_success "VPC created: $VPC_ID"

# Enable DNS hostnames
aws ec2 modify-vpc-attribute --vpc-id $VPC_ID --enable-dns-hostnames
aws ec2 modify-vpc-attribute --vpc-id $VPC_ID --enable-dns-support

# Create Internet Gateway
log_info "Creating Internet Gateway..."
IGW_ID=$(aws ec2 create-internet-gateway \
    --tag-specifications "ResourceType=internet-gateway,Tags=[{Key=Name,Value=${PROJECT_NAME}-igw}]" \
    --query 'InternetGateway.InternetGatewayId' \
    --output text)

aws ec2 attach-internet-gateway --vpc-id $VPC_ID --internet-gateway-id $IGW_ID
log_success "Internet Gateway created and attached: $IGW_ID"

# Create Subnets
log_info "Creating subnets..."

# Public Subnet 1 (us-east-1a)
PUBLIC_SUBNET_1=$(aws ec2 create-subnet \
    --vpc-id $VPC_ID \
    --cidr-block 10.0.1.0/24 \
    --availability-zone ${AWS_REGION}a \
    --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=${PROJECT_NAME}-public-1a}]" \
    --query 'Subnet.SubnetId' \
    --output text)

# Public Subnet 2 (us-east-1b)
PUBLIC_SUBNET_2=$(aws ec2 create-subnet \
    --vpc-id $VPC_ID \
    --cidr-block 10.0.2.0/24 \
    --availability-zone ${AWS_REGION}b \
    --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=${PROJECT_NAME}-public-1b}]" \
    --query 'Subnet.SubnetId' \
    --output text)

# Private Subnet 1 (us-east-1a)
PRIVATE_SUBNET_1=$(aws ec2 create-subnet \
    --vpc-id $VPC_ID \
    --cidr-block 10.0.11.0/24 \
    --availability-zone ${AWS_REGION}a \
    --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=${PROJECT_NAME}-private-1a}]" \
    --query 'Subnet.SubnetId' \
    --output text)

# Private Subnet 2 (us-east-1b)
PRIVATE_SUBNET_2=$(aws ec2 create-subnet \
    --vpc-id $VPC_ID \
    --cidr-block 10.0.12.0/24 \
    --availability-zone ${AWS_REGION}b \
    --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=${PROJECT_NAME}-private-1b}]" \
    --query 'Subnet.SubnetId' \
    --output text)

log_success "Subnets created: Public ($PUBLIC_SUBNET_1, $PUBLIC_SUBNET_2), Private ($PRIVATE_SUBNET_1, $PRIVATE_SUBNET_2)"

# Enable auto-assign public IP for public subnets
aws ec2 modify-subnet-attribute --subnet-id $PUBLIC_SUBNET_1 --map-public-ip-on-launch
aws ec2 modify-subnet-attribute --subnet-id $PUBLIC_SUBNET_2 --map-public-ip-on-launch

# Create Route Tables
log_info "Creating route tables..."

# Public Route Table
PUBLIC_RT=$(aws ec2 create-route-table \
    --vpc-id $VPC_ID \
    --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=${PROJECT_NAME}-public-rt}]" \
    --query 'RouteTable.RouteTableId' \
    --output text)

aws ec2 create-route --route-table-id $PUBLIC_RT --destination-cidr-block 0.0.0.0/0 --gateway-id $IGW_ID
aws ec2 associate-route-table --route-table-id $PUBLIC_RT --subnet-id $PUBLIC_SUBNET_1
aws ec2 associate-route-table --route-table-id $PUBLIC_RT --subnet-id $PUBLIC_SUBNET_2

log_success "Route tables configured"

################################################################################
# Phase 3: Security Groups
################################################################################

log_info "Phase 3: Creating Security Groups..."

# ALB Security Group
ALB_SG=$(aws ec2 create-security-group \
    --group-name ${PROJECT_NAME}-alb-sg \
    --description "Security group for Application Load Balancer" \
    --vpc-id $VPC_ID \
    --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=${PROJECT_NAME}-alb-sg}]" \
    --query 'GroupId' \
    --output text)

aws ec2 authorize-security-group-ingress --group-id $ALB_SG --protocol tcp --port 80 --cidr 0.0.0.0/0
aws ec2 authorize-security-group-ingress --group-id $ALB_SG --protocol tcp --port 443 --cidr 0.0.0.0/0

log_success "ALB Security Group created: $ALB_SG"

# EC2 Security Group
EC2_SG=$(aws ec2 create-security-group \
    --group-name ${PROJECT_NAME}-ec2-sg \
    --description "Security group for EC2 instances" \
    --vpc-id $VPC_ID \
    --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=${PROJECT_NAME}-ec2-sg}]" \
    --query 'GroupId' \
    --output text)

aws ec2 authorize-security-group-ingress --group-id $EC2_SG --protocol tcp --port 8501 --source-group $ALB_SG
aws ec2 authorize-security-group-ingress --group-id $EC2_SG --protocol tcp --port 8502 --source-group $ALB_SG
aws ec2 authorize-security-group-ingress --group-id $EC2_SG --protocol tcp --port 22 --cidr 10.0.0.0/16

log_success "EC2 Security Group created: $EC2_SG"

# RDS Security Group
RDS_SG=$(aws ec2 create-security-group \
    --group-name ${PROJECT_NAME}-rds-sg \
    --description "Security group for RDS PostgreSQL" \
    --vpc-id $VPC_ID \
    --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=${PROJECT_NAME}-rds-sg}]" \
    --query 'GroupId' \
    --output text)

aws ec2 authorize-security-group-ingress --group-id $RDS_SG --protocol tcp --port 5432 --source-group $EC2_SG

log_success "RDS Security Group created: $RDS_SG"

################################################################################
# Phase 4: S3 Bucket
################################################################################

log_info "Phase 4: Creating S3 Bucket..."

S3_BUCKET="${PROJECT_NAME}-${ENVIRONMENT}-assets-${AWS_ACCOUNT_ID}"

aws s3 mb s3://${S3_BUCKET} --region $AWS_REGION 2>/dev/null || log_warning "Bucket may already exist"

# Enable versioning
aws s3api put-bucket-versioning \
    --bucket ${S3_BUCKET} \
    --versioning-configuration Status=Enabled

# Enable encryption
aws s3api put-bucket-encryption \
    --bucket ${S3_BUCKET} \
    --server-side-encryption-configuration '{
        "Rules": [{
            "ApplyServerSideEncryptionByDefault": {
                "SSEAlgorithm": "AES256"
            }
        }]
    }'

# Block public access
aws s3api put-public-access-block \
    --bucket ${S3_BUCKET} \
    --public-access-block-configuration \
        "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

log_success "S3 Bucket created: $S3_BUCKET"

################################################################################
# Phase 5: RDS PostgreSQL Database
################################################################################

log_info "Phase 5: Creating RDS PostgreSQL Database..."

# Create DB Subnet Group
aws rds create-db-subnet-group \
    --db-subnet-group-name ${PROJECT_NAME}-db-subnet \
    --db-subnet-group-description "Subnet group for ${PROJECT_NAME} RDS" \
    --subnet-ids $PRIVATE_SUBNET_1 $PRIVATE_SUBNET_2 \
    --tags Key=Name,Value=${PROJECT_NAME}-db-subnet 2>/dev/null || log_warning "DB subnet group may already exist"

# Create RDS Instance
log_info "Creating RDS instance (this takes 10-15 minutes)..."

aws rds create-db-instance \
    --db-instance-identifier ${PROJECT_NAME}-${ENVIRONMENT}-db \
    --db-instance-class db.t3.medium \
    --engine postgres \
    --engine-version 14.10 \
    --master-username ${PROJECT_NAME}_admin \
    --master-user-password "$DB_PASSWORD" \
    --allocated-storage 100 \
    --storage-type gp3 \
    --vpc-security-group-ids $RDS_SG \
    --db-subnet-group-name ${PROJECT_NAME}-db-subnet \
    --backup-retention-period 7 \
    --multi-az \
    --publicly-accessible false \
    --storage-encrypted \
    --tags Key=Name,Value=${PROJECT_NAME}-${ENVIRONMENT}-db 2>/dev/null || log_warning "RDS instance may already exist"

log_info "Waiting for RDS instance to be available..."
aws rds wait db-instance-available --db-instance-identifier ${PROJECT_NAME}-${ENVIRONMENT}-db

RDS_ENDPOINT=$(aws rds describe-db-instances \
    --db-instance-identifier ${PROJECT_NAME}-${ENVIRONMENT}-db \
    --query 'DBInstances[0].Endpoint.Address' \
    --output text)

log_success "RDS instance created: $RDS_ENDPOINT"

################################################################################
# Phase 6: IAM Roles and Policies
################################################################################

log_info "Phase 6: Creating IAM Roles..."

# Create IAM role for EC2
cat > /tmp/ec2-trust-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

aws iam create-role \
    --role-name ${PROJECT_NAME}-ec2-role \
    --assume-role-policy-document file:///tmp/ec2-trust-policy.json \
    --tags Key=Name,Value=${PROJECT_NAME}-ec2-role 2>/dev/null || log_warning "IAM role may already exist"

# Attach policies
aws iam attach-role-policy \
    --role-name ${PROJECT_NAME}-ec2-role \
    --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess 2>/dev/null || true

aws iam attach-role-policy \
    --role-name ${PROJECT_NAME}-ec2-role \
    --policy-arn arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy 2>/dev/null || true

aws iam attach-role-policy \
    --role-name ${PROJECT_NAME}-ec2-role \
    --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore 2>/dev/null || true

# Create instance profile
aws iam create-instance-profile \
    --instance-profile-name ${PROJECT_NAME}-ec2-profile 2>/dev/null || log_warning "Instance profile may already exist"

aws iam add-role-to-instance-profile \
    --instance-profile-name ${PROJECT_NAME}-ec2-profile \
    --role-name ${PROJECT_NAME}-ec2-role 2>/dev/null || true

log_success "IAM roles created"

# Wait for instance profile to be ready
sleep 10

################################################################################
# Phase 7: Store Secrets in AWS Secrets Manager
################################################################################

log_info "Phase 7: Storing secrets in AWS Secrets Manager..."

# Create database credentials secret
aws secretsmanager create-secret \
    --name ${PROJECT_NAME}/${ENVIRONMENT}/db/credentials \
    --description "Database credentials for ${PROJECT_NAME}" \
    --secret-string "{
        \"username\": \"${PROJECT_NAME}_admin\",
        \"password\": \"$DB_PASSWORD\",
        \"host\": \"$RDS_ENDPOINT\",
        \"port\": 5432,
        \"dbname\": \"${PROJECT_NAME}\"
    }" \
    --tags Key=Name,Value=${PROJECT_NAME}-db-credentials 2>/dev/null || log_warning "Secret may already exist"

# Store configuration in Parameter Store
aws ssm put-parameter \
    --name /${PROJECT_NAME}/${ENVIRONMENT}/db/host \
    --value "$RDS_ENDPOINT" \
    --type String \
    --overwrite 2>/dev/null || true

aws ssm put-parameter \
    --name /${PROJECT_NAME}/${ENVIRONMENT}/s3/bucket \
    --value "$S3_BUCKET" \
    --type String \
    --overwrite 2>/dev/null || true

aws ssm put-parameter \
    --name /${PROJECT_NAME}/${ENVIRONMENT}/app/secret-key \
    --value "$APP_SECRET_KEY" \
    --type SecureString \
    --overwrite 2>/dev/null || true

log_success "Secrets stored in AWS Secrets Manager and Parameter Store"

################################################################################
# Phase 8: Create SSH Key Pair
################################################################################

log_info "Phase 8: Creating SSH Key Pair..."

if [ ! -f "${PROJECT_NAME}-key.pem" ]; then
    aws ec2 create-key-pair \
        --key-name ${PROJECT_NAME}-key \
        --query 'KeyMaterial' \
        --output text > ${PROJECT_NAME}-key.pem
    
    chmod 400 ${PROJECT_NAME}-key.pem
    log_success "SSH key created: ${PROJECT_NAME}-key.pem"
else
    log_warning "SSH key already exists: ${PROJECT_NAME}-key.pem"
fi

################################################################################
# Phase 9: Create Base EC2 Instance and AMI
################################################################################

log_info "Phase 9: Creating base EC2 instance for AMI..."

# Get latest Amazon Linux 2023 AMI
BASE_AMI=$(aws ec2 describe-images \
    --owners amazon \
    --filters "Name=name,Values=al2023-ami-2023.*-x86_64" \
    --query 'sort_by(Images, &CreationDate)[-1].ImageId' \
    --output text)

log_info "Using base AMI: $BASE_AMI"

# Create user data script
cat > /tmp/user-data.sh <<'EOF'
#!/bin/bash
set -e

# Update system
yum update -y

# Install Python 3.9 and dependencies
yum install -y python3.9 python3.9-pip git cmake gcc gcc-c++ libX11-devel

# Install system dependencies for dlib and audio processing
yum install -y libsndfile ffmpeg

# Create application directory
mkdir -p /opt/snapclass
cd /opt/snapclass

# Clone repository (replace with your repo URL)
# git clone https://github.com/yourusername/snapclass.git .

# For now, create placeholder
echo "Application will be deployed here" > README.txt

# Install Python packages (will be done after code is uploaded)
# pip3.9 install -r requirements.txt

# Create systemd service
cat > /etc/systemd/system/snapclass.service <<'SERVICEEOF'
[Unit]
Description=SnapClass AI Attendance Application
After=network.target

[Service]
Type=simple
User=ec2-user
WorkingDirectory=/opt/snapclass
Environment="PATH=/usr/local/bin:/usr/bin:/bin"
EnvironmentFile=/opt/snapclass/.env
ExecStart=/usr/local/bin/streamlit run app.py --server.port=8501 --server.address=0.0.0.0
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
SERVICEEOF

# Create health check service
cat > /etc/systemd/system/snapclass-health.service <<'HEALTHEOF'
[Unit]
Description=SnapClass Health Check Service
After=network.target

[Service]
Type=simple
User=ec2-user
WorkingDirectory=/opt/snapclass
ExecStart=/usr/bin/python3.9 /opt/snapclass/healthcheck.py
Restart=always

[Install]
WantedBy=multi-user.target
HEALTHEOF

# Enable services (don't start yet)
systemctl daemon-reload
systemctl enable snapclass.service
systemctl enable snapclass-health.service

# Set permissions
chown -R ec2-user:ec2-user /opt/snapclass

echo "Base instance setup complete"
EOF

# Launch base instance
BASE_INSTANCE_ID=$(aws ec2 run-instances \
    --image-id $BASE_AMI \
    --instance-type t3.large \
    --key-name ${PROJECT_NAME}-key \
    --security-group-ids $EC2_SG \
    --subnet-id $PUBLIC_SUBNET_1 \
    --iam-instance-profile Name=${PROJECT_NAME}-ec2-profile \
    --user-data file:///tmp/user-data.sh \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=${PROJECT_NAME}-base-instance}]" \
    --query 'Instances[0].InstanceId' \
    --output text)

log_info "Base instance launched: $BASE_INSTANCE_ID"
log_info "Waiting for instance to be running..."

aws ec2 wait instance-running --instance-ids $BASE_INSTANCE_ID

BASE_INSTANCE_IP=$(aws ec2 describe-instances \
    --instance-ids $BASE_INSTANCE_ID \
    --query 'Reservations[0].Instances[0].PublicIpAddress' \
    --output text)

log_success "Base instance running at: $BASE_INSTANCE_IP"
log_warning "SSH into instance: ssh -i ${PROJECT_NAME}-key.pem ec2-user@$BASE_INSTANCE_IP"
log_warning "Upload your application code to /opt/snapclass/"
log_warning "Install requirements: sudo pip3.9 install -r /opt/snapclass/requirements.txt"

# Wait for user data to complete
log_info "Waiting 5 minutes for user data script to complete..."
sleep 300

################################################################################
# Phase 10: Create Application Load Balancer
################################################################################

log_info "Phase 10: Creating Application Load Balancer..."

# Create Target Group
TG_ARN=$(aws elbv2 create-target-group \
    --name ${PROJECT_NAME}-tg \
    --protocol HTTP \
    --port 8501 \
    --vpc-id $VPC_ID \
    --health-check-path /healthz \
    --health-check-port 8502 \
    --health-check-interval-seconds 30 \
    --health-check-timeout-seconds 10 \
    --healthy-threshold-count 2 \
    --unhealthy-threshold-count 3 \
    --tags Key=Name,Value=${PROJECT_NAME}-tg \
    --query 'TargetGroups[0].TargetGroupArn' \
    --output text)

log_success "Target Group created: $TG_ARN"

# Create Application Load Balancer
ALB_ARN=$(aws elbv2 create-load-balancer \
    --name ${PROJECT_NAME}-alb \
    --subnets $PUBLIC_SUBNET_1 $PUBLIC_SUBNET_2 \
    --security-groups $ALB_SG \
    --scheme internet-facing \
    --type application \
    --tags Key=Name,Value=${PROJECT_NAME}-alb \
    --query 'LoadBalancers[0].LoadBalancerArn' \
    --output text)

log_success "Application Load Balancer created: $ALB_ARN"

# Create Listener
LISTENER_ARN=$(aws elbv2 create-listener \
    --load-balancer-arn $ALB_ARN \
    --protocol HTTP \
    --port 80 \
    --default-actions Type=forward,TargetGroupArn=$TG_ARN \
    --query 'Listeners[0].ListenerArn' \
    --output text)

log_success "Listener created: $LISTENER_ARN"

# Get ALB DNS name
ALB_DNS=$(aws elbv2 describe-load-balancers \
    --load-balancer-arns $ALB_ARN \
    --query 'LoadBalancers[0].DNSName' \
    --output text)

log_success "ALB DNS: $ALB_DNS"

################################################################################
# Phase 11: Create AMI from Base Instance
################################################################################

log_info "Phase 11: Creating AMI from base instance..."
log_warning "IMPORTANT: Before creating AMI, ensure you have:"
log_warning "1. Uploaded your application code to /opt/snapclass/"
log_warning "2. Installed all requirements"
log_warning "3. Tested the application"

read -p "Press Enter to continue with AMI creation (or Ctrl+C to abort)..."

# Stop instance
log_info "Stopping instance..."
aws ec2 stop-instances --instance-ids $BASE_INSTANCE_ID
aws ec2 wait instance-stopped --instance-ids $BASE_INSTANCE_ID

# Create AMI
AMI_ID=$(aws ec2 create-image \
    --instance-id $BASE_INSTANCE_ID \
    --name "${PROJECT_NAME}-app-$(date +%Y%m%d-%H%M%S)" \
    --description "SnapClass Application AMI" \
    --tag-specifications "ResourceType=image,Tags=[{Key=Name,Value=${PROJECT_NAME}-app-ami}]" \
    --query 'ImageId' \
    --output text)

log_info "AMI creation initiated: $AMI_ID"
log_info "Waiting for AMI to be available (this may take 5-10 minutes)..."

aws ec2 wait image-available --image-ids $AMI_ID

log_success "AMI created: $AMI_ID"

# Terminate base instance
log_info "Terminating base instance..."
aws ec2 terminate-instances --instance-ids $BASE_INSTANCE_ID

################################################################################
# Phase 12: Create Launch Template
################################################################################

log_info "Phase 12: Creating Launch Template..."

# Create environment file template
cat > /tmp/env-template <<EOF
DB_HOST=$RDS_ENDPOINT
DB_PORT=5432
DB_NAME=${PROJECT_NAME}
DB_USERNAME=${PROJECT_NAME}_admin
DB_PASSWORD=$DB_PASSWORD
S3_BUCKET=$S3_BUCKET
AWS_REGION=$AWS_REGION
APP_SECRET_KEY=$APP_SECRET_KEY
APP_ENV=production
LOG_LEVEL=INFO
STREAMLIT_SERVER_PORT=8501
STREAMLIT_SERVER_ADDRESS=0.0.0.0
STREAMLIT_SERVER_HEADLESS=true
STREAMLIT_BROWSER_GATHER_USAGE_STATS=false
EOF

# Encode user data
USER_DATA=$(cat <<'USEREOF'
#!/bin/bash
# Load environment variables from Parameter Store
aws ssm get-parameter --name /snapclass/prod/db/host --query 'Parameter.Value' --output text > /tmp/db_host
aws secretsmanager get-secret-value --secret-id snapclass/prod/db/credentials --query 'SecretString' --output text > /tmp/db_creds

# Create .env file
cat > /opt/snapclass/.env <<EOF
DB_HOST=$(cat /tmp/db_host)
DB_PORT=5432
DB_NAME=snapclass
DB_USERNAME=$(jq -r '.username' /tmp/db_creds)
DB_PASSWORD=$(jq -r '.password' /tmp/db_creds)
S3_BUCKET=$(aws ssm get-parameter --name /snapclass/prod/s3/bucket --query 'Parameter.Value' --output text)
AWS_REGION=$(ec2-metadata --availability-zone | cut -d' ' -f2 | sed 's/.$//')
APP_SECRET_KEY=$(aws ssm get-parameter --name /snapclass/prod/app/secret-key --with-decryption --query 'Parameter.Value' --output text)
APP_ENV=production
LOG_LEVEL=INFO
EOF

# Start services
systemctl start snapclass-health.service
systemctl start snapclass.service
USEREOF
)

# Create launch template
aws ec2 create-launch-template \
    --launch-template-name ${PROJECT_NAME}-lt \
    --version-description "v1.0" \
    --launch-template-data "{
        \"ImageId\": \"$AMI_ID\",
        \"InstanceType\": \"t3.large\",
        \"KeyName\": \"${PROJECT_NAME}-key\",
        \"SecurityGroupIds\": [\"$EC2_SG\"],
        \"IamInstanceProfile\": {\"Name\": \"${PROJECT_NAME}-ec2-profile\"},
        \"UserData\": \"$(echo "$USER_DATA" | base64 -w 0)\",
        \"TagSpecifications\": [{
            \"ResourceType\": \"instance\",
            \"Tags\": [{\"Key\": \"Name\", \"Value\": \"${PROJECT_NAME}-app-instance\"}]
        }]
    }"

log_success "Launch Template created"

################################################################################
# Phase 13: Create Auto Scaling Group
################################################################################

log_info "Phase 13: Creating Auto Scaling Group..."

aws autoscaling create-auto-scaling-group \
    --auto-scaling-group-name ${PROJECT_NAME}-asg \
    --launch-template LaunchTemplateName=${PROJECT_NAME}-lt,Version='$Latest' \
    --min-size 2 \
    --max-size 6 \
    --desired-capacity 2 \
    --target-group-arns $TG_ARN \
    --vpc-zone-identifier "$PRIVATE_SUBNET_1,$PRIVATE_SUBNET_2" \
    --health-check-type ELB \
    --health-check-grace-period 300 \
    --tags Key=Name,Value=${PROJECT_NAME}-asg-instance,PropagateAtLaunch=true

log_success "Auto Scaling Group created"

# Create scaling policies
log_info "Creating scaling policies..."

# Scale up policy
SCALE_UP_POLICY=$(aws autoscaling put-scaling-policy \
    --auto-scaling-group-name ${PROJECT_NAME}-asg \
    --policy-name ${PROJECT_NAME}-scale-up \
    --policy-type TargetTrackingScaling \
    --target-tracking-configuration "{
        \"PredefinedMetricSpecification\": {
            \"PredefinedMetricType\": \"ASGAverageCPUUtilization\"
        },
        \"TargetValue\": 70.0
    }" \
    --query 'PolicyARN' \
    --output text)

log_success "Scaling policies created"

################################################################################
# Phase 14: Create CloudWatch Alarms
################################################################################

log_info "Phase 14: Creating CloudWatch Alarms..."

# Create SNS topic for alarms
SNS_TOPIC_ARN=$(aws sns create-topic \
    --name ${PROJECT_NAME}-alarms \
    --query 'TopicArn' \
    --output text)

log_info "SNS Topic created: $SNS_TOPIC_ARN"
log_warning "Subscribe to SNS topic for alarm notifications:"
log_warning "aws sns subscribe --topic-arn $SNS_TOPIC_ARN --protocol email --notification-endpoint your-email@example.com"

# RDS CPU Alarm
aws cloudwatch put-metric-alarm \
    --alarm-name ${PROJECT_NAME}-rds-cpu-high \
    --alarm-description "RDS CPU utilization is too high" \
    --metric-name CPUUtilization \
    --namespace AWS/RDS \
    --statistic Average \
    --period 300 \
    --evaluation-periods 2 \
    --threshold 90 \
    --comparison-operator GreaterThanThreshold \
    --dimensions Name=DBInstanceIdentifier,Value=${PROJECT_NAME}-${ENVIRONMENT}-db \
    --alarm-actions $SNS_TOPIC_ARN

# ALB 5xx Errors
aws cloudwatch put-metric-alarm \
    --alarm-name ${PROJECT_NAME}-alb-5xx-errors \
    --alarm-description "ALB 5xx errors are too high" \
    --metric-name HTTPCode_Target_5XX_Count \
    --namespace AWS/ApplicationELB \
    --statistic Sum \
    --period 300 \
    --evaluation-periods 1 \
    --threshold 50 \
    --comparison-operator GreaterThanThreshold \
    --dimensions Name=LoadBalancer,Value=$(echo $ALB_ARN | cut -d: -f6 | cut -d/ -f2-) \
    --alarm-actions $SNS_TOPIC_ARN

log_success "CloudWatch Alarms created"

################################################################################
# Deployment Summary
################################################################################

log_success "=========================================="
log_success "SnapClass Deployment Complete!"
log_success "=========================================="
echo ""
log_info "Infrastructure Details:"
echo "  VPC ID: $VPC_ID"
echo "  RDS Endpoint: $RDS_ENDPOINT"
echo "  S3 Bucket: $S3_BUCKET"
echo "  ALB DNS: $ALB_DNS"
echo "  AMI ID: $AMI_ID"
echo ""
log_info "Access your application at:"
echo "  http://$ALB_DNS"
echo ""
log_warning "Important Next Steps:"
echo "  1. Subscribe to SNS topic for alarms:"
echo "     aws sns subscribe --topic-arn $SNS_TOPIC_ARN --protocol email --notification-endpoint your-email@example.com"
echo ""
echo "  2. Configure DNS (Route 53):"
echo "     - Create A record pointing to ALB: $ALB_DNS"
echo ""
echo "  3. Request SSL Certificate (ACM):"
echo "     - Request certificate for your domain"
echo "     - Add HTTPS listener to ALB"
echo ""
echo "  4. Initialize Database:"
echo "     - Connect to RDS and create schema"
echo "     - Run migrations if needed"
echo ""
log_info "Credentials saved in AWS Secrets Manager:"
echo "  Secret: ${PROJECT_NAME}/${ENVIRONMENT}/db/credentials"
echo ""
log_info "SSH Key saved as: ${PROJECT_NAME}-key.pem"
echo ""
log_success "Deployment script completed successfully!"

# Save deployment info to file
cat > deployment-info.txt <<EOF
SnapClass Deployment Information
Generated: $(date)

VPC ID: $VPC_ID
Public Subnets: $PUBLIC_SUBNET_1, $PUBLIC_SUBNET_2
Private Subnets: $PRIVATE_SUBNET_1, $PRIVATE_SUBNET_2

Security Groups:
  ALB: $ALB_SG
  EC2: $EC2_SG
  RDS: $RDS_SG

RDS Endpoint: $RDS_ENDPOINT
RDS Username: ${PROJECT_NAME}_admin
RDS Password: [Stored in AWS Secrets Manager]

S3 Bucket: $S3_BUCKET

Load Balancer:
  ARN: $ALB_ARN
  DNS: $ALB_DNS
  Target Group: $TG_ARN

AMI ID: $AMI_ID
Launch Template: ${PROJECT_NAME}-lt
Auto Scaling Group: ${PROJECT_NAME}-asg

SNS Topic: $SNS_TOPIC_ARN

Application URL: http://$ALB_DNS

SSH Key: ${PROJECT_NAME}-key.pem
EOF

log_success "Deployment information saved to: deployment-info.txt"

# Made with Bob
