# Application Deployment Guide - SnapClass AI Attendance

This guide covers the deployment of the SnapClass application to AWS EC2 instances with proper configuration for production use.

## Prerequisites

- Infrastructure setup completed (VPC, RDS, S3, etc.)
- Database migrated from Supabase to RDS
- IAM roles and security groups configured
- Domain and SSL certificate ready

## Phase 1: Database Migration

### Step 1: Export Supabase Schema

```bash
# Connect to Supabase and export schema
pg_dump -h <supabase-host> \
  -U postgres \
  -d postgres \
  --schema-only \
  --no-owner \
  --no-privileges \
  -f supabase_schema.sql
```

### Step 2: Export Supabase Data

```bash
# Export data only
pg_dump -h <supabase-host> \
  -U postgres \
  -d postgres \
  --data-only \
  --no-owner \
  --no-privileges \
  -f supabase_data.sql
```

### Step 3: Create RDS Database Schema

```sql
-- Connect to RDS
psql -h <rds-endpoint> -U snapclass_admin -d postgres

-- Create database
CREATE DATABASE snapclass;

-- Connect to new database
\c snapclass

-- Create tables based on your Supabase schema
CREATE TABLE teachers (
    teacher_id SERIAL PRIMARY KEY,
    username VARCHAR(100) UNIQUE NOT NULL,
    password VARCHAR(255) NOT NULL,
    name VARCHAR(255) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE students (
    student_id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    face_embedding FLOAT8[],
    voice_embedding FLOAT8[],
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE subjects (
    subject_id SERIAL PRIMARY KEY,
    subject_code VARCHAR(50) UNIQUE NOT NULL,
    name VARCHAR(255) NOT NULL,
    section VARCHAR(50),
    teacher_id INTEGER REFERENCES teachers(teacher_id),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE enrollments (
    enrollment_id SERIAL PRIMARY KEY,
    student_id INTEGER REFERENCES students(student_id),
    subject_id INTEGER REFERENCES subjects(subject_id),
    enrolled_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(student_id, subject_id)
);

CREATE TABLE attendance (
    attendance_id SERIAL PRIMARY KEY,
    student_id INTEGER REFERENCES students(student_id),
    subject_id INTEGER REFERENCES subjects(subject_id),
    attendance_date DATE NOT NULL,
    status VARCHAR(20) CHECK (status IN ('present', 'absent')),
    marked_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(student_id, subject_id, attendance_date)
);

-- Create indexes for performance
CREATE INDEX idx_teachers_username ON teachers(username);
CREATE INDEX idx_students_name ON students(name);
CREATE INDEX idx_subjects_code ON subjects(subject_code);
CREATE INDEX idx_subjects_teacher ON subjects(teacher_id);
CREATE INDEX idx_enrollments_student ON enrollments(student_id);
CREATE INDEX idx_enrollments_subject ON enrollments(subject_id);
CREATE INDEX idx_attendance_student ON attendance(student_id);
CREATE INDEX idx_attendance_subject ON attendance(subject_id);
CREATE INDEX idx_attendance_date ON attendance(attendance_date);
```

### Step 4: Import Data to RDS

```bash
# Import data
psql -h <rds-endpoint> -U snapclass_admin -d snapclass -f supabase_data.sql

# Verify data
psql -h <rds-endpoint> -U snapclass_admin -d snapclass -c "SELECT COUNT(*) FROM teachers;"
psql -h <rds-endpoint> -U snapclass_admin -d snapclass -c "SELECT COUNT(*) FROM students;"
```

## Phase 2: Custom AMI Creation

### Step 1: Launch Base EC2 Instance

```bash
# Launch Amazon Linux 2023 instance
aws ec2 run-instances \
  --image-id ami-0c55b159cbfafe1f0 \
  --instance-type t3.large \
  --key-name <your-key-pair> \
  --security-group-ids $EC2_SG_ID \
  --subnet-id <private-subnet-id> \
  --iam-instance-profile Name=SnapClass-EC2-Profile \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=snapclass-ami-builder}]'
```

### Step 2: Connect and Install Dependencies

```bash
# SSH into instance
ssh -i <your-key.pem> ec2-user@<instance-ip>

# Update system
sudo yum update -y

# Install Python 3.9+
sudo yum install -y python3.9 python3-pip python3-devel

# Install system dependencies for dlib and face recognition
sudo yum install -y cmake gcc gcc-c++ make
sudo yum install -y libX11-devel libXext-devel
sudo yum install -y boost-devel
sudo yum install -y openblas-devel lapack-devel

# Install audio processing libraries
sudo yum install -y libsndfile-devel
sudo yum install -y ffmpeg

# Install Git
sudo yum install -y git

# Install PostgreSQL client
sudo yum install -y postgresql15

# Install Redis client
sudo yum install -y redis
```

### Step 3: Set Up Application Directory

```bash
# Create application directory
sudo mkdir -p /opt/snapclass
sudo chown ec2-user:ec2-user /opt/snapclass
cd /opt/snapclass

# Clone repository (or copy files)
git clone <your-repo-url> .

# Create virtual environment
python3.9 -m venv venv
source venv/bin/activate

# Upgrade pip
pip install --upgrade pip setuptools wheel
```

### Step 4: Install Python Dependencies

```bash
# Install requirements
pip install -r requirements.txt

# Verify critical packages
python -c "import dlib; print('dlib:', dlib.__version__)"
python -c "import face_recognition; print('face_recognition installed')"
python -c "import librosa; print('librosa:', librosa.__version__)"
python -c "import streamlit; print('streamlit:', streamlit.__version__)"
```

### Step 5: Install CloudWatch Agent

```bash
# Download CloudWatch agent
wget https://s3.amazonaws.com/amazoncloudwatch-agent/amazon_linux/amd64/latest/amazon-cloudwatch-agent.rpm

# Install
sudo rpm -U ./amazon-cloudwatch-agent.rpm

# Create configuration
sudo tee /opt/aws/amazon-cloudwatch-agent/etc/config.json << 'EOF'
{
  "agent": {
    "metrics_collection_interval": 60,
    "run_as_user": "cwagent"
  },
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/snapclass/application.log",
            "log_group_name": "/aws/ec2/snapclass/application",
            "log_stream_name": "{instance_id}"
          },
          {
            "file_path": "/var/log/snapclass/error.log",
            "log_group_name": "/aws/ec2/snapclass/error",
            "log_stream_name": "{instance_id}"
          }
        ]
      }
    }
  },
  "metrics": {
    "namespace": "SnapClass/Application",
    "metrics_collected": {
      "cpu": {
        "measurement": [
          {"name": "cpu_usage_idle", "rename": "CPU_IDLE", "unit": "Percent"},
          {"name": "cpu_usage_iowait", "rename": "CPU_IOWAIT", "unit": "Percent"}
        ],
        "totalcpu": false
      },
      "disk": {
        "measurement": [
          {"name": "used_percent", "rename": "DISK_USED", "unit": "Percent"}
        ],
        "resources": ["*"]
      },
      "mem": {
        "measurement": [
          {"name": "mem_used_percent", "rename": "MEM_USED", "unit": "Percent"}
        ]
      }
    }
  }
}
EOF

# Start CloudWatch agent
sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config \
  -m ec2 \
  -s \
  -c file:/opt/aws/amazon-cloudwatch-agent/etc/config.json
```

### Step 6: Create Application Configuration

```bash
# Create config directory
mkdir -p /opt/snapclass/.streamlit

# Create Streamlit config
cat > /opt/snapclass/.streamlit/config.toml << 'EOF'
[server]
port = 8501
address = "0.0.0.0"
headless = true
enableCORS = false
enableXsrfProtection = true

[browser]
gatherUsageStats = false

[theme]
primaryColor = "#007bff"
backgroundColor = "#ffffff"
secondaryBackgroundColor = "#f0f2f6"
textColor = "#262730"
font = "sans serif"
EOF
```

### Step 7: Create Systemd Service

```bash
# Create systemd service file
sudo tee /etc/systemd/system/snapclass.service << 'EOF'
[Unit]
Description=SnapClass AI Attendance Application
After=network.target

[Service]
Type=simple
User=ec2-user
WorkingDirectory=/opt/snapclass
Environment="PATH=/opt/snapclass/venv/bin"
ExecStartPre=/bin/bash -c 'source /opt/snapclass/scripts/load_config.sh'
ExecStart=/opt/snapclass/venv/bin/streamlit run app.py
Restart=always
RestartSec=10
StandardOutput=append:/var/log/snapclass/application.log
StandardError=append:/var/log/snapclass/error.log

[Install]
WantedBy=multi-user.target
EOF

# Create log directory
sudo mkdir -p /var/log/snapclass
sudo chown ec2-user:ec2-user /var/log/snapclass

# Enable service
sudo systemctl daemon-reload
sudo systemctl enable snapclass.service
```

### Step 8: Create Configuration Loading Script

```bash
# Create scripts directory
mkdir -p /opt/snapclass/scripts

# Create config loader
cat > /opt/snapclass/scripts/load_config.sh << 'EOF'
#!/bin/bash

# Load configuration from AWS Systems Manager Parameter Store
export DB_HOST=$(aws ssm get-parameter --name /snapclass/prod/db/host --query 'Parameter.Value' --output text --region us-east-1)
export DB_PORT=$(aws ssm get-parameter --name /snapclass/prod/db/port --query 'Parameter.Value' --output text --region us-east-1)
export DB_NAME=$(aws ssm get-parameter --name /snapclass/prod/db/name --query 'Parameter.Value' --output text --region us-east-1)
export REDIS_ENDPOINT=$(aws ssm get-parameter --name /snapclass/prod/redis/endpoint --query 'Parameter.Value' --output text --region us-east-1)
export S3_BUCKET=$(aws ssm get-parameter --name /snapclass/prod/s3/bucket --query 'Parameter.Value' --output text --region us-east-1)

# Load database credentials from Secrets Manager
DB_CREDS=$(aws secretsmanager get-secret-value --secret-id snapclass/prod/db/credentials --query 'SecretString' --output text --region us-east-1)
export DB_USERNAME=$(echo $DB_CREDS | jq -r '.username')
export DB_PASSWORD=$(echo $DB_CREDS | jq -r '.password')

echo "Configuration loaded successfully"
EOF

chmod +x /opt/snapclass/scripts/load_config.sh
```

### Step 9: Update Application Code for RDS

Create a new database configuration file:

```bash
cat > /opt/snapclass/src/database/config_rds.py << 'EOF'
import os
import psycopg2
from psycopg2 import pool
import streamlit as st

# Database connection pool
db_pool = None

def get_db_pool():
    global db_pool
    if db_pool is None:
        db_pool = psycopg2.pool.SimpleConnectionPool(
            1, 20,
            host=os.getenv('DB_HOST'),
            port=os.getenv('DB_PORT', 5432),
            database=os.getenv('DB_NAME'),
            user=os.getenv('DB_USERNAME'),
            password=os.getenv('DB_PASSWORD'),
            sslmode='require'
        )
    return db_pool

def get_db_connection():
    pool = get_db_pool()
    return pool.getconn()

def release_db_connection(conn):
    pool = get_db_pool()
    pool.putconn(conn)

@st.cache_resource
def get_cached_connection():
    return get_db_connection()
EOF
```

### Step 10: Create Health Check Endpoint

```bash
cat > /opt/snapclass/healthcheck.py << 'EOF'
from http.server import HTTPServer, BaseHTTPRequestHandler
import psycopg2
import os

class HealthCheckHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/healthz':
            try:
                # Check database connection
                conn = psycopg2.connect(
                    host=os.getenv('DB_HOST'),
                    port=os.getenv('DB_PORT', 5432),
                    database=os.getenv('DB_NAME'),
                    user=os.getenv('DB_USERNAME'),
                    password=os.getenv('DB_PASSWORD'),
                    connect_timeout=5
                )
                conn.close()
                
                self.send_response(200)
                self.send_header('Content-type', 'text/plain')
                self.end_headers()
                self.wfile.write(b'OK')
            except Exception as e:
                self.send_response(503)
                self.send_header('Content-type', 'text/plain')
                self.end_headers()
                self.wfile.write(f'ERROR: {str(e)}'.encode())
        else:
            self.send_response(404)
            self.end_headers()

if __name__ == '__main__':
    server = HTTPServer(('0.0.0.0', 8502), HealthCheckHandler)
    server.serve_forever()
EOF

# Create systemd service for health check
sudo tee /etc/systemd/system/snapclass-health.service << 'EOF'
[Unit]
Description=SnapClass Health Check Service
After=network.target

[Service]
Type=simple
User=ec2-user
WorkingDirectory=/opt/snapclass
Environment="PATH=/opt/snapclass/venv/bin"
ExecStartPre=/bin/bash -c 'source /opt/snapclass/scripts/load_config.sh'
ExecStart=/opt/snapclass/venv/bin/python healthcheck.py
Restart=always

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable snapclass-health.service
```

### Step 11: Clean Up and Create AMI

```bash
# Clean up
sudo yum clean all
rm -rf ~/.bash_history
history -c

# Stop services before creating AMI
sudo systemctl stop snapclass.service
sudo systemctl stop snapclass-health.service
sudo systemctl stop amazon-cloudwatch-agent

# Exit instance
exit
```

```bash
# Create AMI from instance
aws ec2 create-image \
  --instance-id <ami-builder-instance-id> \
  --name "snapclass-app-v1.0-$(date +%Y%m%d)" \
  --description "SnapClass AI Attendance Application AMI" \
  --no-reboot

# Wait for AMI to be available
aws ec2 wait image-available --image-ids <ami-id>

# Tag AMI
aws ec2 create-tags \
  --resources <ami-id> \
  --tags Key=Name,Value=snapclass-app Key=Version,Value=1.0 Key=Environment,Value=production
```

## Phase 3: Load Balancer Setup

### Step 1: Create Target Group

```bash
aws elbv2 create-target-group \
  --name snapclass-tg \
  --protocol HTTP \
  --port 8501 \
  --vpc-id $VPC_ID \
  --health-check-enabled \
  --health-check-protocol HTTP \
  --health-check-path /healthz \
  --health-check-port 8502 \
  --health-check-interval-seconds 30 \
  --health-check-timeout-seconds 5 \
  --healthy-threshold-count 2 \
  --unhealthy-threshold-count 3 \
  --matcher HttpCode=200 \
  --tags Key=Name,Value=snapclass-tg

export TG_ARN=<target-group-arn>
```

### Step 2: Create Application Load Balancer

```bash
aws elbv2 create-load-balancer \
  --name snapclass-alb \
  --subnets <public-subnet-1a-id> <public-subnet-1b-id> \
  --security-groups $ALB_SG_ID \
  --scheme internet-facing \
  --type application \
  --ip-address-type ipv4 \
  --tags Key=Name,Value=snapclass-alb

export ALB_ARN=<load-balancer-arn>
export ALB_DNS=<load-balancer-dns-name>
```

### Step 3: Request SSL Certificate

```bash
# Request certificate
aws acm request-certificate \
  --domain-name yourdomain.com \
  --subject-alternative-names www.yourdomain.com \
  --validation-method DNS \
  --tags Key=Name,Value=snapclass-cert

export CERT_ARN=<certificate-arn>

# Get validation records
aws acm describe-certificate --certificate-arn $CERT_ARN

# Add CNAME records to your DNS provider for validation
# Wait for certificate to be issued
aws acm wait certificate-validated --certificate-arn $CERT_ARN
```

### Step 4: Create ALB Listeners

```bash
# HTTPS Listener
aws elbv2 create-listener \
  --load-balancer-arn $ALB_ARN \
  --protocol HTTPS \
  --port 443 \
  --certificates CertificateArn=$CERT_ARN \
  --default-actions Type=forward,TargetGroupArn=$TG_ARN \
  --ssl-policy ELBSecurityPolicy-TLS-1-2-2017-01

# HTTP Listener (redirect to HTTPS)
aws elbv2 create-listener \
  --load-balancer-arn $ALB_ARN \
  --protocol HTTP \
  --port 80 \
  --default-actions Type=redirect,RedirectConfig="{Protocol=HTTPS,Port=443,StatusCode=HTTP_301}"
```

## Phase 4: Auto Scaling Setup

### Step 1: Create Launch Template

```bash
aws ec2 create-launch-template \
  --launch-template-name snapclass-lt \
  --version-description "v1.0" \
  --launch-template-data '{
    "ImageId": "<your-ami-id>",
    "InstanceType": "t3.large",
    "IamInstanceProfile": {
      "Name": "SnapClass-EC2-Profile"
    },
    "SecurityGroupIds": ["'$EC2_SG_ID'"],
    "UserData": "'$(base64 -w 0 << 'EOF'
#!/bin/bash
# Start services
systemctl start snapclass.service
systemctl start snapclass-health.service
systemctl start amazon-cloudwatch-agent
EOF
)'",
    "TagSpecifications": [{
      "ResourceType": "instance",
      "Tags": [
        {"Key": "Name", "Value": "snapclass-app"},
        {"Key": "Environment", "Value": "production"}
      ]
    }],
    "Monitoring": {
      "Enabled": true
    }
  }'
```

### Step 2: Create Auto Scaling Group

```bash
aws autoscaling create-auto-scaling-group \
  --auto-scaling-group-name snapclass-asg \
  --launch-template LaunchTemplateName=snapclass-lt,Version='$Latest' \
  --min-size 2 \
  --max-size 6 \
  --desired-capacity 2 \
  --default-cooldown 300 \
  --health-check-type ELB \
  --health-check-grace-period 300 \
  --vpc-zone-identifier "<private-subnet-1a-id>,<private-subnet-1b-id>" \
  --target-group-arns $TG_ARN \
  --tags Key=Name,Value=snapclass-app,PropagateAtLaunch=true Key=Environment,Value=production,PropagateAtLaunch=true
```

### Step 3: Create Scaling Policies

```bash
# Target Tracking Scaling Policy
aws autoscaling put-scaling-policy \
  --auto-scaling-group-name snapclass-asg \
  --policy-name snapclass-target-tracking \
  --policy-type TargetTrackingScaling \
  --target-tracking-configuration '{
    "PredefinedMetricSpecification": {
      "PredefinedMetricType": "ASGAverageCPUUtilization"
    },
    "TargetValue": 60.0
  }'

# Scale Up Policy
aws autoscaling put-scaling-policy \
  --auto-scaling-group-name snapclass-asg \
  --policy-name snapclass-scale-up \
  --policy-type StepScaling \
  --adjustment-type ChangeInCapacity \
  --metric-aggregation-type Average \
  --step-adjustments MetricIntervalLowerBound=0,ScalingAdjustment=1

# Scale Down Policy
aws autoscaling put-scaling-policy \
  --auto-scaling-group-name snapclass-asg \
  --policy-name snapclass-scale-down \
  --policy-type StepScaling \
  --adjustment-type ChangeInCapacity \
  --metric-aggregation-type Average \
  --step-adjustments MetricIntervalUpperBound=0,ScalingAdjustment=-1
```

## Phase 5: DNS Configuration

### Step 1: Create Route 53 Record

```bash
# Get hosted zone ID
aws route53 list-hosted-zones-by-name --dns-name yourdomain.com

export HOSTED_ZONE_ID=<zone-id>

# Create A record pointing to ALB
aws route53 change-resource-record-sets \
  --hosted-zone-id $HOSTED_ZONE_ID \
  --change-batch '{
    "Changes": [{
      "Action": "CREATE",
      "ResourceRecordSet": {
        "Name": "yourdomain.com",
        "Type": "A",
        "AliasTarget": {
          "HostedZoneId": "<alb-hosted-zone-id>",
          "DNSName": "'$ALB_DNS'",
          "EvaluateTargetHealth": true
        }
      }
    }]
  }'
```

## Verification

### Test Application

```bash
# Check ALB health
aws elbv2 describe-target-health --target-group-arn $TG_ARN

# Test HTTPS endpoint
curl -I https://yourdomain.com

# Test health check
curl http://<instance-ip>:8502/healthz

# Check application logs
aws logs tail /aws/ec2/snapclass/application --follow
```

### Verify Auto Scaling

```bash
# Check ASG status
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names snapclass-asg

# Check instances
aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=snapclass-app" \
  --query 'Reservations[*].Instances[*].[InstanceId,State.Name,PrivateIpAddress]'
```

## Troubleshooting

### Application Won't Start

```bash
# Check service status
sudo systemctl status snapclass.service

# Check logs
sudo journalctl -u snapclass.service -n 50

# Check environment variables
sudo systemctl show snapclass.service --property=Environment
```

### Database Connection Issues

```bash
# Test database connectivity
psql -h $DB_HOST -U $DB_USERNAME -d $DB_NAME

# Check security group rules
aws ec2 describe-security-groups --group-ids $RDS_SG_ID
```

### Health Check Failing

```bash
# Test health check endpoint
curl http://localhost:8502/healthz

# Check health check service
sudo systemctl status snapclass-health.service
```

## Rollback Procedure

If deployment fails:

```bash
# Update ASG to use previous AMI
aws autoscaling update-auto-scaling-group \
  --auto-scaling-group-name snapclass-asg \
  --launch-template LaunchTemplateName=snapclass-lt,Version=<previous-version>

# Trigger instance refresh
aws autoscaling start-instance-refresh \
  --auto-scaling-group-name snapclass-asg
```

## Next Steps

1. Configure monitoring: [MONITORING_SETUP.md](MONITORING_SETUP.md)
2. Set up CI/CD: [CICD_SETUP.md](CICD_SETUP.md)
3. Configure WAF: [SECURITY_HARDENING.md](SECURITY_HARDENING.md)

---

**Document Version**: 1.0  
**Last Updated**: 2026-09-25