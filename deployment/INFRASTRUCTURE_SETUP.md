# Infrastructure Setup Guide - SnapClass AI Attendance

This guide provides detailed step-by-step instructions for setting up the AWS infrastructure for the SnapClass application.

## Prerequisites

- AWS Account with administrative access
- AWS CLI installed and configured
- Terraform installed (v1.0+)
- Domain name ready
- GitHub repository access

## Phase 1: Network Infrastructure

### Step 1: Create VPC

```bash
# Using AWS CLI
aws ec2 create-vpc \
  --cidr-block 10.0.0.0/16 \
  --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=snapclass-prod-vpc}]'

# Note the VPC ID from output
export VPC_ID=<your-vpc-id>
```

### Step 2: Create Subnets

#### Public Subnets (for ALB)
```bash
# Public Subnet AZ-1
aws ec2 create-subnet \
  --vpc-id $VPC_ID \
  --cidr-block 10.0.1.0/24 \
  --availability-zone us-east-1a \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=snapclass-public-1a}]'

# Public Subnet AZ-2
aws ec2 create-subnet \
  --vpc-id $VPC_ID \
  --cidr-block 10.0.2.0/24 \
  --availability-zone us-east-1b \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=snapclass-public-1b}]'
```

#### Private Subnets (for EC2)
```bash
# Private Subnet AZ-1
aws ec2 create-subnet \
  --vpc-id $VPC_ID \
  --cidr-block 10.0.11.0/24 \
  --availability-zone us-east-1a \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=snapclass-private-1a}]'

# Private Subnet AZ-2
aws ec2 create-subnet \
  --vpc-id $VPC_ID \
  --cidr-block 10.0.12.0/24 \
  --availability-zone us-east-1b \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=snapclass-private-1b}]'
```

#### Database Subnets (for RDS)
```bash
# Database Subnet AZ-1
aws ec2 create-subnet \
  --vpc-id $VPC_ID \
  --cidr-block 10.0.21.0/24 \
  --availability-zone us-east-1a \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=snapclass-db-1a}]'

# Database Subnet AZ-2
aws ec2 create-subnet \
  --vpc-id $VPC_ID \
  --cidr-block 10.0.22.0/24 \
  --availability-zone us-east-1b \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=snapclass-db-1b}]'
```

### Step 3: Create Internet Gateway

```bash
# Create IGW
aws ec2 create-internet-gateway \
  --tag-specifications 'ResourceType=internet-gateway,Tags=[{Key=Name,Value=snapclass-igw}]'

export IGW_ID=<your-igw-id>

# Attach to VPC
aws ec2 attach-internet-gateway \
  --vpc-id $VPC_ID \
  --internet-gateway-id $IGW_ID
```

### Step 4: Create NAT Gateways

```bash
# Allocate Elastic IPs
aws ec2 allocate-address --domain vpc
export EIP1_ID=<allocation-id-1>

aws ec2 allocate-address --domain vpc
export EIP2_ID=<allocation-id-2>

# Create NAT Gateway in each public subnet
aws ec2 create-nat-gateway \
  --subnet-id <public-subnet-1a-id> \
  --allocation-id $EIP1_ID \
  --tag-specifications 'ResourceType=natgateway,Tags=[{Key=Name,Value=snapclass-nat-1a}]'

aws ec2 create-nat-gateway \
  --subnet-id <public-subnet-1b-id> \
  --allocation-id $EIP2_ID \
  --tag-specifications 'ResourceType=natgateway,Tags=[{Key=Name,Value=snapclass-nat-1b}]'
```

### Step 5: Configure Route Tables

#### Public Route Table
```bash
# Create route table
aws ec2 create-route-table \
  --vpc-id $VPC_ID \
  --tag-specifications 'ResourceType=route-table,Tags=[{Key=Name,Value=snapclass-public-rt}]'

export PUBLIC_RT_ID=<route-table-id>

# Add route to IGW
aws ec2 create-route \
  --route-table-id $PUBLIC_RT_ID \
  --destination-cidr-block 0.0.0.0/0 \
  --gateway-id $IGW_ID

# Associate with public subnets
aws ec2 associate-route-table \
  --subnet-id <public-subnet-1a-id> \
  --route-table-id $PUBLIC_RT_ID

aws ec2 associate-route-table \
  --subnet-id <public-subnet-1b-id> \
  --route-table-id $PUBLIC_RT_ID
```

#### Private Route Tables
```bash
# Create route table for AZ-1
aws ec2 create-route-table \
  --vpc-id $VPC_ID \
  --tag-specifications 'ResourceType=route-table,Tags=[{Key=Name,Value=snapclass-private-rt-1a}]'

export PRIVATE_RT_1A_ID=<route-table-id>

# Add route to NAT Gateway
aws ec2 create-route \
  --route-table-id $PRIVATE_RT_1A_ID \
  --destination-cidr-block 0.0.0.0/0 \
  --nat-gateway-id <nat-gateway-1a-id>

# Associate with private subnet
aws ec2 associate-route-table \
  --subnet-id <private-subnet-1a-id> \
  --route-table-id $PRIVATE_RT_1A_ID

# Repeat for AZ-2
```

### Step 6: Create Security Groups

#### ALB Security Group
```bash
aws ec2 create-security-group \
  --group-name snapclass-alb-sg \
  --description "Security group for Application Load Balancer" \
  --vpc-id $VPC_ID

export ALB_SG_ID=<security-group-id>

# Allow HTTPS
aws ec2 authorize-security-group-ingress \
  --group-id $ALB_SG_ID \
  --protocol tcp \
  --port 443 \
  --cidr 0.0.0.0/0

# Allow HTTP (for redirect)
aws ec2 authorize-security-group-ingress \
  --group-id $ALB_SG_ID \
  --protocol tcp \
  --port 80 \
  --cidr 0.0.0.0/0
```

#### EC2 Security Group
```bash
aws ec2 create-security-group \
  --group-name snapclass-ec2-sg \
  --description "Security group for EC2 instances" \
  --vpc-id $VPC_ID

export EC2_SG_ID=<security-group-id>

# Allow Streamlit port from ALB
aws ec2 authorize-security-group-ingress \
  --group-id $EC2_SG_ID \
  --protocol tcp \
  --port 8501 \
  --source-group $ALB_SG_ID

# Allow SSH from bastion (add bastion SG later)
```

#### RDS Security Group
```bash
aws ec2 create-security-group \
  --group-name snapclass-rds-sg \
  --description "Security group for RDS PostgreSQL" \
  --vpc-id $VPC_ID

export RDS_SG_ID=<security-group-id>

# Allow PostgreSQL from EC2
aws ec2 authorize-security-group-ingress \
  --group-id $RDS_SG_ID \
  --protocol tcp \
  --port 5432 \
  --source-group $EC2_SG_ID
```

#### ElastiCache Security Group
```bash
aws ec2 create-security-group \
  --group-name snapclass-redis-sg \
  --description "Security group for ElastiCache Redis" \
  --vpc-id $VPC_ID

export REDIS_SG_ID=<security-group-id>

# Allow Redis from EC2
aws ec2 authorize-security-group-ingress \
  --group-id $REDIS_SG_ID \
  --protocol tcp \
  --port 6379 \
  --source-group $EC2_SG_ID
```

## Phase 2: Database Setup

### Step 1: Create DB Subnet Group

```bash
aws rds create-db-subnet-group \
  --db-subnet-group-name snapclass-db-subnet-group \
  --db-subnet-group-description "Subnet group for SnapClass RDS" \
  --subnet-ids <db-subnet-1a-id> <db-subnet-1b-id> \
  --tags Key=Name,Value=snapclass-db-subnet-group
```

### Step 2: Create RDS Parameter Group

```bash
aws rds create-db-parameter-group \
  --db-parameter-group-name snapclass-postgres14 \
  --db-parameter-group-family postgres14 \
  --description "Custom parameter group for SnapClass"

# Optimize parameters
aws rds modify-db-parameter-group \
  --db-parameter-group-name snapclass-postgres14 \
  --parameters \
    "ParameterName=shared_buffers,ParameterValue='{DBInstanceClassMemory/4}',ApplyMethod=pending-reboot" \
    "ParameterName=max_connections,ParameterValue=200,ApplyMethod=pending-reboot" \
    "ParameterName=work_mem,ParameterValue=16384,ApplyMethod=immediate"
```

### Step 3: Create RDS Instance

```bash
aws rds create-db-instance \
  --db-instance-identifier snapclass-prod-db \
  --db-instance-class db.t3.medium \
  --engine postgres \
  --engine-version 14.7 \
  --master-username snapclass_admin \
  --master-user-password '<secure-password>' \
  --allocated-storage 100 \
  --storage-type gp3 \
  --storage-encrypted \
  --multi-az \
  --db-subnet-group-name snapclass-db-subnet-group \
  --vpc-security-group-ids $RDS_SG_ID \
  --db-parameter-group-name snapclass-postgres14 \
  --backup-retention-period 7 \
  --preferred-backup-window "03:00-04:00" \
  --preferred-maintenance-window "sun:04:00-sun:05:00" \
  --enable-performance-insights \
  --performance-insights-retention-period 7 \
  --enable-cloudwatch-logs-exports '["postgresql"]' \
  --tags Key=Name,Value=snapclass-prod-db Key=Environment,Value=production
```

### Step 4: Wait for RDS to be Available

```bash
aws rds wait db-instance-available \
  --db-instance-identifier snapclass-prod-db

# Get endpoint
aws rds describe-db-instances \
  --db-instance-identifier snapclass-prod-db \
  --query 'DBInstances[0].Endpoint.Address' \
  --output text
```

## Phase 3: Storage Setup

### Step 1: Create S3 Buckets

```bash
# Main application bucket
aws s3api create-bucket \
  --bucket snapclass-prod-assets-<unique-suffix> \
  --region us-east-1

# Enable versioning
aws s3api put-bucket-versioning \
  --bucket snapclass-prod-assets-<unique-suffix> \
  --versioning-configuration Status=Enabled

# Enable encryption
aws s3api put-bucket-encryption \
  --bucket snapclass-prod-assets-<unique-suffix> \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {
        "SSEAlgorithm": "AES256"
      }
    }]
  }'

# Block public access
aws s3api put-public-access-block \
  --bucket snapclass-prod-assets-<unique-suffix> \
  --public-access-block-configuration \
    "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
```

### Step 2: Configure Lifecycle Policies

```bash
aws s3api put-bucket-lifecycle-configuration \
  --bucket snapclass-prod-assets-<unique-suffix> \
  --lifecycle-configuration file://s3-lifecycle.json
```

**s3-lifecycle.json:**
```json
{
  "Rules": [
    {
      "Id": "DeleteTempFiles",
      "Status": "Enabled",
      "Prefix": "uploads/temp/",
      "Expiration": {
        "Days": 7
      }
    },
    {
      "Id": "ArchiveLogs",
      "Status": "Enabled",
      "Prefix": "logs/",
      "Transitions": [
        {
          "Days": 30,
          "StorageClass": "INTELLIGENT_TIERING"
        }
      ]
    }
  ]
}
```

### Step 3: Create CORS Configuration

```bash
aws s3api put-bucket-cors \
  --bucket snapclass-prod-assets-<unique-suffix> \
  --cors-configuration file://s3-cors.json
```

**s3-cors.json:**
```json
{
  "CORSRules": [
    {
      "AllowedOrigins": ["https://yourdomain.com"],
      "AllowedMethods": ["GET", "PUT", "POST", "DELETE"],
      "AllowedHeaders": ["*"],
      "MaxAgeSeconds": 3000
    }
  ]
}
```

## Phase 4: Caching Setup

### Step 1: Create ElastiCache Subnet Group

```bash
aws elasticache create-cache-subnet-group \
  --cache-subnet-group-name snapclass-redis-subnet-group \
  --cache-subnet-group-description "Subnet group for SnapClass Redis" \
  --subnet-ids <private-subnet-1a-id> <private-subnet-1b-id>
```

### Step 2: Create ElastiCache Redis Cluster

```bash
aws elasticache create-replication-group \
  --replication-group-id snapclass-redis \
  --replication-group-description "Redis cluster for SnapClass" \
  --engine redis \
  --engine-version 7.0 \
  --cache-node-type cache.t3.micro \
  --num-cache-clusters 2 \
  --automatic-failover-enabled \
  --multi-az-enabled \
  --cache-subnet-group-name snapclass-redis-subnet-group \
  --security-group-ids $REDIS_SG_ID \
  --at-rest-encryption-enabled \
  --transit-encryption-enabled \
  --auth-token '<secure-auth-token>' \
  --tags Key=Name,Value=snapclass-redis Key=Environment,Value=production
```

## Phase 5: IAM Roles and Policies

### Step 1: Create EC2 Instance Role

```bash
# Create trust policy
cat > ec2-trust-policy.json << EOF
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

# Create role
aws iam create-role \
  --role-name SnapClass-EC2-Role \
  --assume-role-policy-document file://ec2-trust-policy.json

# Create and attach policy
cat > ec2-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::snapclass-prod-assets-*",
        "arn:aws:s3:::snapclass-prod-assets-*/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "arn:aws:logs:*:*:*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "cloudwatch:PutMetricData"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "ssm:GetParameter",
        "ssm:GetParameters"
      ],
      "Resource": "arn:aws:ssm:*:*:parameter/snapclass/*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue"
      ],
      "Resource": "arn:aws:secretsmanager:*:*:secret:snapclass/*"
    }
  ]
}
EOF

aws iam put-role-policy \
  --role-name SnapClass-EC2-Role \
  --policy-name SnapClass-EC2-Policy \
  --policy-document file://ec2-policy.json

# Create instance profile
aws iam create-instance-profile \
  --instance-profile-name SnapClass-EC2-Profile

aws iam add-role-to-instance-profile \
  --instance-profile-name SnapClass-EC2-Profile \
  --role-name SnapClass-EC2-Role
```

## Phase 6: Secrets Management

### Step 1: Store Database Credentials

```bash
aws secretsmanager create-secret \
  --name snapclass/prod/db/credentials \
  --description "Database credentials for SnapClass production" \
  --secret-string '{
    "username": "snapclass_admin",
    "password": "<secure-password>",
    "engine": "postgres",
    "host": "<rds-endpoint>",
    "port": 5432,
    "dbname": "snapclass"
  }'
```

### Step 2: Store Application Parameters

```bash
# Database host
aws ssm put-parameter \
  --name /snapclass/prod/db/host \
  --value "<rds-endpoint>" \
  --type String

# Database port
aws ssm put-parameter \
  --name /snapclass/prod/db/port \
  --value "5432" \
  --type String

# Database name
aws ssm put-parameter \
  --name /snapclass/prod/db/name \
  --value "snapclass" \
  --type String

# Redis endpoint
aws ssm put-parameter \
  --name /snapclass/prod/redis/endpoint \
  --value "<redis-endpoint>" \
  --type String

# S3 bucket
aws ssm put-parameter \
  --name /snapclass/prod/s3/bucket \
  --value "snapclass-prod-assets-<unique-suffix>" \
  --type String

# Application secret key
aws ssm put-parameter \
  --name /snapclass/prod/app/secret_key \
  --value "<generate-secure-key>" \
  --type SecureString
```

## Verification Checklist

After completing the infrastructure setup, verify:

- [ ] VPC created with correct CIDR block
- [ ] All subnets created in correct AZs
- [ ] Internet Gateway attached
- [ ] NAT Gateways operational in both AZs
- [ ] Route tables configured correctly
- [ ] Security groups allow required traffic only
- [ ] RDS instance running and accessible
- [ ] S3 buckets created with encryption enabled
- [ ] ElastiCache Redis cluster operational
- [ ] IAM roles and policies created
- [ ] Secrets stored in Secrets Manager
- [ ] Parameters stored in Parameter Store

## Next Steps

After infrastructure setup is complete:

1. Proceed to [APPLICATION_DEPLOYMENT.md](APPLICATION_DEPLOYMENT.md) for application deployment
2. Configure monitoring as per [MONITORING_SETUP.md](MONITORING_SETUP.md)
3. Set up CI/CD pipeline as per [CICD_SETUP.md](CICD_SETUP.md)

## Troubleshooting

### Common Issues

**Issue**: NAT Gateway creation fails
- **Solution**: Ensure Elastic IP is allocated first and public subnet exists

**Issue**: RDS instance won't start
- **Solution**: Check security group rules and subnet group configuration

**Issue**: Cannot connect to RDS
- **Solution**: Verify security group allows traffic from EC2 security group

**Issue**: S3 bucket name already taken
- **Solution**: Add unique suffix to bucket name

## Cleanup (For Testing)

To remove all infrastructure:

```bash
# Delete in reverse order
aws rds delete-db-instance --db-instance-identifier snapclass-prod-db --skip-final-snapshot
aws elasticache delete-replication-group --replication-group-id snapclass-redis
aws s3 rb s3://snapclass-prod-assets-<unique-suffix> --force
# Continue with other resources...
```

---

**Document Version**: 1.0  
**Last Updated**: 2026-09-25