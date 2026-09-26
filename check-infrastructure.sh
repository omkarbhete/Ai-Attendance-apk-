#!/bin/bash

################################################################################
# SnapClass Infrastructure Verification Script
# 
# This script checks if all AWS infrastructure components are deployed
# and shows their current status.
#
# Usage: ./check-infrastructure.sh
################################################################################

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

PROJECT_NAME="snapclass"
ENVIRONMENT="prod"
AWS_REGION="${AWS_REGION:-us-east-1}"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}SnapClass Infrastructure Status Check${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Function to check resource
check_resource() {
    local resource_name=$1
    local status=$2
    
    if [ "$status" = "exists" ]; then
        echo -e "${GREEN}✅ $resource_name${NC}"
    elif [ "$status" = "missing" ]; then
        echo -e "${RED}❌ $resource_name${NC}"
    elif [ "$status" = "pending" ]; then
        echo -e "${YELLOW}⏳ $resource_name${NC}"
    else
        echo -e "${BLUE}ℹ️  $resource_name: $status${NC}"
    fi
}

################################################################################
# 1. Check VPC
################################################################################
echo -e "${BLUE}[1] Checking VPC...${NC}"

VPC_ID=$(aws ec2 describe-vpcs \
    --filters "Name=tag:Name,Values=${PROJECT_NAME}-${ENVIRONMENT}-vpc" \
    --query 'Vpcs[0].VpcId' \
    --output text 2>/dev/null)

if [ "$VPC_ID" != "None" ] && [ -n "$VPC_ID" ]; then
    check_resource "VPC: $VPC_ID" "exists"
    
    # Check subnets
    PUBLIC_SUBNETS=$(aws ec2 describe-subnets \
        --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Name,Values=${PROJECT_NAME}-public-*" \
        --query 'Subnets[*].SubnetId' \
        --output text 2>/dev/null | wc -w)
    
    PRIVATE_SUBNETS=$(aws ec2 describe-subnets \
        --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Name,Values=${PROJECT_NAME}-private-*" \
        --query 'Subnets[*].SubnetId' \
        --output text 2>/dev/null | wc -w)
    
    check_resource "Public Subnets: $PUBLIC_SUBNETS" "exists"
    check_resource "Private Subnets: $PRIVATE_SUBNETS" "exists"
    
    # Check Internet Gateway
    IGW_ID=$(aws ec2 describe-internet-gateways \
        --filters "Name=attachment.vpc-id,Values=$VPC_ID" \
        --query 'InternetGateways[0].InternetGatewayId' \
        --output text 2>/dev/null)
    
    if [ "$IGW_ID" != "None" ] && [ -n "$IGW_ID" ]; then
        check_resource "Internet Gateway: $IGW_ID" "exists"
    else
        check_resource "Internet Gateway" "missing"
    fi
else
    check_resource "VPC" "missing"
fi

echo ""

################################################################################
# 2. Check Security Groups
################################################################################
echo -e "${BLUE}[2] Checking Security Groups...${NC}"

ALB_SG=$(aws ec2 describe-security-groups \
    --filters "Name=group-name,Values=${PROJECT_NAME}-alb-sg" \
    --query 'SecurityGroups[0].GroupId' \
    --output text 2>/dev/null)

EC2_SG=$(aws ec2 describe-security-groups \
    --filters "Name=group-name,Values=${PROJECT_NAME}-ec2-sg" \
    --query 'SecurityGroups[0].GroupId' \
    --output text 2>/dev/null)

RDS_SG=$(aws ec2 describe-security-groups \
    --filters "Name=group-name,Values=${PROJECT_NAME}-rds-sg" \
    --query 'SecurityGroups[0].GroupId' \
    --output text 2>/dev/null)

[ "$ALB_SG" != "None" ] && [ -n "$ALB_SG" ] && check_resource "ALB Security Group: $ALB_SG" "exists" || check_resource "ALB Security Group" "missing"
[ "$EC2_SG" != "None" ] && [ -n "$EC2_SG" ] && check_resource "EC2 Security Group: $EC2_SG" "exists" || check_resource "EC2 Security Group" "missing"
[ "$RDS_SG" != "None" ] && [ -n "$RDS_SG" ] && check_resource "RDS Security Group: $RDS_SG" "exists" || check_resource "RDS Security Group" "missing"

echo ""

################################################################################
# 3. Check S3 Bucket
################################################################################
echo -e "${BLUE}[3] Checking S3 Bucket...${NC}"

AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
S3_BUCKET="${PROJECT_NAME}-${ENVIRONMENT}-assets-${AWS_ACCOUNT_ID}"

if aws s3 ls "s3://${S3_BUCKET}" &>/dev/null; then
    check_resource "S3 Bucket: $S3_BUCKET" "exists"
    
    # Check bucket size
    BUCKET_SIZE=$(aws s3 ls s3://${S3_BUCKET} --recursive --summarize 2>/dev/null | grep "Total Size" | awk '{print $3}')
    if [ -n "$BUCKET_SIZE" ]; then
        SIZE_MB=$((BUCKET_SIZE / 1024 / 1024))
        echo -e "   ${BLUE}Size: ${SIZE_MB} MB${NC}"
    fi
else
    check_resource "S3 Bucket" "missing"
fi

echo ""

################################################################################
# 4. Check RDS Database
################################################################################
echo -e "${BLUE}[4] Checking RDS Database...${NC}"

RDS_STATUS=$(aws rds describe-db-instances \
    --db-instance-identifier ${PROJECT_NAME}-${ENVIRONMENT}-db \
    --query 'DBInstances[0].DBInstanceStatus' \
    --output text 2>/dev/null)

if [ "$RDS_STATUS" != "None" ] && [ -n "$RDS_STATUS" ]; then
    RDS_ENDPOINT=$(aws rds describe-db-instances \
        --db-instance-identifier ${PROJECT_NAME}-${ENVIRONMENT}-db \
        --query 'DBInstances[0].Endpoint.Address' \
        --output text 2>/dev/null)
    
    RDS_ENGINE=$(aws rds describe-db-instances \
        --db-instance-identifier ${PROJECT_NAME}-${ENVIRONMENT}-db \
        --query 'DBInstances[0].Engine' \
        --output text 2>/dev/null)
    
    RDS_VERSION=$(aws rds describe-db-instances \
        --db-instance-identifier ${PROJECT_NAME}-${ENVIRONMENT}-db \
        --query 'DBInstances[0].EngineVersion' \
        --output text 2>/dev/null)
    
    if [ "$RDS_STATUS" = "available" ]; then
        check_resource "RDS Database: ${PROJECT_NAME}-${ENVIRONMENT}-db" "exists"
        echo -e "   ${GREEN}Status: $RDS_STATUS${NC}"
        echo -e "   ${BLUE}Endpoint: $RDS_ENDPOINT${NC}"
        echo -e "   ${BLUE}Engine: $RDS_ENGINE $RDS_VERSION${NC}"
    else
        check_resource "RDS Database: ${PROJECT_NAME}-${ENVIRONMENT}-db" "pending"
        echo -e "   ${YELLOW}Status: $RDS_STATUS${NC}"
    fi
else
    check_resource "RDS Database" "missing"
fi

echo ""

################################################################################
# 5. Check IAM Roles
################################################################################
echo -e "${BLUE}[5] Checking IAM Roles...${NC}"

IAM_ROLE=$(aws iam get-role \
    --role-name ${PROJECT_NAME}-ec2-role \
    --query 'Role.RoleName' \
    --output text 2>/dev/null)

IAM_PROFILE=$(aws iam get-instance-profile \
    --instance-profile-name ${PROJECT_NAME}-ec2-profile \
    --query 'InstanceProfile.InstanceProfileName' \
    --output text 2>/dev/null)

[ "$IAM_ROLE" != "None" ] && [ -n "$IAM_ROLE" ] && check_resource "IAM Role: $IAM_ROLE" "exists" || check_resource "IAM Role" "missing"
[ "$IAM_PROFILE" != "None" ] && [ -n "$IAM_PROFILE" ] && check_resource "Instance Profile: $IAM_PROFILE" "exists" || check_resource "Instance Profile" "missing"

echo ""

################################################################################
# 6. Check Secrets
################################################################################
echo -e "${BLUE}[6] Checking Secrets...${NC}"

SECRET_EXISTS=$(aws secretsmanager describe-secret \
    --secret-id ${PROJECT_NAME}/${ENVIRONMENT}/db/credentials \
    --query 'Name' \
    --output text 2>/dev/null)

if [ "$SECRET_EXISTS" != "None" ] && [ -n "$SECRET_EXISTS" ]; then
    check_resource "Secrets Manager: DB Credentials" "exists"
else
    check_resource "Secrets Manager: DB Credentials" "missing"
fi

# Check Parameter Store
PARAM_COUNT=$(aws ssm describe-parameters \
    --parameter-filters "Key=Name,Option=BeginsWith,Values=/${PROJECT_NAME}/${ENVIRONMENT}/" \
    --query 'Parameters' \
    --output json 2>/dev/null | jq '. | length')

if [ "$PARAM_COUNT" -gt 0 ] 2>/dev/null; then
    check_resource "Parameter Store: $PARAM_COUNT parameters" "exists"
else
    check_resource "Parameter Store" "missing"
fi

echo ""

################################################################################
# 7. Check EC2 Instances
################################################################################
echo -e "${BLUE}[7] Checking EC2 Instances...${NC}"

# Check base instance
BASE_INSTANCE=$(aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=${PROJECT_NAME}-base-instance" "Name=instance-state-name,Values=running,stopped,pending" \
    --query 'Reservations[0].Instances[0].InstanceId' \
    --output text 2>/dev/null)

if [ "$BASE_INSTANCE" != "None" ] && [ -n "$BASE_INSTANCE" ]; then
    BASE_STATE=$(aws ec2 describe-instances \
        --instance-ids $BASE_INSTANCE \
        --query 'Reservations[0].Instances[0].State.Name' \
        --output text 2>/dev/null)
    
    check_resource "Base Instance: $BASE_INSTANCE" "$BASE_STATE"
else
    check_resource "Base Instance" "missing"
fi

# Check Auto Scaling instances
ASG_INSTANCES=$(aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=${PROJECT_NAME}-asg-instance" "Name=instance-state-name,Values=running,pending" \
    --query 'Reservations[*].Instances[*].InstanceId' \
    --output text 2>/dev/null | wc -w)

if [ "$ASG_INSTANCES" -gt 0 ] 2>/dev/null; then
    check_resource "Auto Scaling Instances: $ASG_INSTANCES running" "exists"
else
    check_resource "Auto Scaling Instances" "missing"
fi

echo ""

################################################################################
# 8. Check AMI
################################################################################
echo -e "${BLUE}[8] Checking AMI...${NC}"

AMI_ID=$(aws ec2 describe-images \
    --owners self \
    --filters "Name=tag:Name,Values=${PROJECT_NAME}-app-ami" \
    --query 'sort_by(Images, &CreationDate)[-1].ImageId' \
    --output text 2>/dev/null)

if [ "$AMI_ID" != "None" ] && [ -n "$AMI_ID" ]; then
    AMI_STATE=$(aws ec2 describe-images \
        --image-ids $AMI_ID \
        --query 'Images[0].State' \
        --output text 2>/dev/null)
    
    check_resource "AMI: $AMI_ID" "$AMI_STATE"
else
    check_resource "AMI" "missing"
fi

echo ""

################################################################################
# 9. Check Load Balancer
################################################################################
echo -e "${BLUE}[9] Checking Load Balancer...${NC}"

ALB_ARN=$(aws elbv2 describe-load-balancers \
    --names ${PROJECT_NAME}-alb \
    --query 'LoadBalancers[0].LoadBalancerArn' \
    --output text 2>/dev/null)

if [ "$ALB_ARN" != "None" ] && [ -n "$ALB_ARN" ]; then
    ALB_STATE=$(aws elbv2 describe-load-balancers \
        --load-balancer-arns $ALB_ARN \
        --query 'LoadBalancers[0].State.Code' \
        --output text 2>/dev/null)
    
    ALB_DNS=$(aws elbv2 describe-load-balancers \
        --load-balancer-arns $ALB_ARN \
        --query 'LoadBalancers[0].DNSName' \
        --output text 2>/dev/null)
    
    check_resource "Application Load Balancer" "$ALB_STATE"
    echo -e "   ${BLUE}DNS: $ALB_DNS${NC}"
    
    # Check target group
    TG_ARN=$(aws elbv2 describe-target-groups \
        --names ${PROJECT_NAME}-tg \
        --query 'TargetGroups[0].TargetGroupArn' \
        --output text 2>/dev/null)
    
    if [ "$TG_ARN" != "None" ] && [ -n "$TG_ARN" ]; then
        HEALTHY_TARGETS=$(aws elbv2 describe-target-health \
            --target-group-arn $TG_ARN \
            --query 'TargetHealthDescriptions[?TargetHealth.State==`healthy`]' \
            --output json 2>/dev/null | jq '. | length')
        
        TOTAL_TARGETS=$(aws elbv2 describe-target-health \
            --target-group-arn $TG_ARN \
            --query 'TargetHealthDescriptions' \
            --output json 2>/dev/null | jq '. | length')
        
        check_resource "Target Group: $HEALTHY_TARGETS/$TOTAL_TARGETS healthy" "exists"
    fi
else
    check_resource "Application Load Balancer" "missing"
fi

echo ""

################################################################################
# 10. Check Auto Scaling Group
################################################################################
echo -e "${BLUE}[10] Checking Auto Scaling Group...${NC}"

ASG_EXISTS=$(aws autoscaling describe-auto-scaling-groups \
    --auto-scaling-group-names ${PROJECT_NAME}-asg \
    --query 'AutoScalingGroups[0].AutoScalingGroupName' \
    --output text 2>/dev/null)

if [ "$ASG_EXISTS" != "None" ] && [ -n "$ASG_EXISTS" ]; then
    ASG_DESIRED=$(aws autoscaling describe-auto-scaling-groups \
        --auto-scaling-group-names ${PROJECT_NAME}-asg \
        --query 'AutoScalingGroups[0].DesiredCapacity' \
        --output text 2>/dev/null)
    
    ASG_CURRENT=$(aws autoscaling describe-auto-scaling-groups \
        --auto-scaling-group-names ${PROJECT_NAME}-asg \
        --query 'AutoScalingGroups[0].Instances | length(@)' \
        --output text 2>/dev/null)
    
    ASG_MIN=$(aws autoscaling describe-auto-scaling-groups \
        --auto-scaling-group-names ${PROJECT_NAME}-asg \
        --query 'AutoScalingGroups[0].MinSize' \
        --output text 2>/dev/null)
    
    ASG_MAX=$(aws autoscaling describe-auto-scaling-groups \
        --auto-scaling-group-names ${PROJECT_NAME}-asg \
        --query 'AutoScalingGroups[0].MaxSize' \
        --output text 2>/dev/null)
    
    check_resource "Auto Scaling Group: ${PROJECT_NAME}-asg" "exists"
    echo -e "   ${BLUE}Capacity: $ASG_CURRENT/$ASG_DESIRED (min: $ASG_MIN, max: $ASG_MAX)${NC}"
else
    check_resource "Auto Scaling Group" "missing"
fi

echo ""

################################################################################
# 11. Check Launch Template
################################################################################
echo -e "${BLUE}[11] Checking Launch Template...${NC}"

LT_EXISTS=$(aws ec2 describe-launch-templates \
    --launch-template-names ${PROJECT_NAME}-lt \
    --query 'LaunchTemplates[0].LaunchTemplateName' \
    --output text 2>/dev/null)

if [ "$LT_EXISTS" != "None" ] && [ -n "$LT_EXISTS" ]; then
    LT_VERSION=$(aws ec2 describe-launch-templates \
        --launch-template-names ${PROJECT_NAME}-lt \
        --query 'LaunchTemplates[0].LatestVersionNumber' \
        --output text 2>/dev/null)
    
    check_resource "Launch Template: ${PROJECT_NAME}-lt (v$LT_VERSION)" "exists"
else
    check_resource "Launch Template" "missing"
fi

echo ""

################################################################################
# 12. Check CloudWatch Alarms
################################################################################
echo -e "${BLUE}[12] Checking CloudWatch Alarms...${NC}"

ALARM_COUNT=$(aws cloudwatch describe-alarms \
    --alarm-name-prefix ${PROJECT_NAME} \
    --query 'MetricAlarms | length(@)' \
    --output text 2>/dev/null)

if [ "$ALARM_COUNT" -gt 0 ] 2>/dev/null; then
    check_resource "CloudWatch Alarms: $ALARM_COUNT configured" "exists"
else
    check_resource "CloudWatch Alarms" "missing"
fi

# Check SNS Topic
SNS_TOPIC=$(aws sns list-topics \
    --query "Topics[?contains(TopicArn, '${PROJECT_NAME}-alarms')].TopicArn" \
    --output text 2>/dev/null)

if [ -n "$SNS_TOPIC" ]; then
    check_resource "SNS Topic: ${PROJECT_NAME}-alarms" "exists"
else
    check_resource "SNS Topic" "missing"
fi

echo ""

################################################################################
# Summary
################################################################################
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Summary${NC}"
echo -e "${BLUE}========================================${NC}"

if [ -f "deployment-info.txt" ]; then
    echo -e "${GREEN}✅ Deployment info file found${NC}"
    echo ""
    echo -e "${BLUE}Quick Access:${NC}"
    
    if [ -n "$ALB_DNS" ]; then
        echo -e "   ${GREEN}Application URL: http://$ALB_DNS${NC}"
    fi
    
    if [ "$RDS_STATUS" = "available" ]; then
        echo -e "   ${GREEN}Database: $RDS_ENDPOINT${NC}"
    fi
    
    if [ -n "$S3_BUCKET" ]; then
        echo -e "   ${GREEN}S3 Bucket: $S3_BUCKET${NC}"
    fi
else
    echo -e "${YELLOW}⚠️  deployment-info.txt not found${NC}"
    echo -e "${YELLOW}   Run the deployment script to create it${NC}"
fi

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${GREEN}Infrastructure check complete!${NC}"
echo -e "${BLUE}========================================${NC}"

# Made with Bob
