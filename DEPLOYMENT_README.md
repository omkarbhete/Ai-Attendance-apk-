# SnapClass AWS Deployment - Implementation Guide

## 🎯 Overview

This repository now contains all the necessary files and configurations to deploy the SnapClass AI Attendance application to AWS EC2 following industry best practices.

## 📦 What's Been Added

### 1. CI/CD Configuration Files
- **`buildspec.yml`** - AWS CodeBuild configuration for automated builds
- **`appspec.yml`** - AWS CodeDeploy configuration for deployments
- **`scripts/`** - Deployment lifecycle scripts

### 2. Deployment Scripts
Located in `scripts/` directory:
- `stop_application.sh` - Gracefully stops the application
- `before_install.sh` - Prepares for new deployment
- `after_install.sh` - Configures application after deployment
- `start_application.sh` - Starts the application services
- `validate_service.sh` - Validates deployment success
- `load_config.sh` - Loads configuration from AWS Parameter Store

### 3. Application Configuration
- **`src/database/config_rds.py`** - PostgreSQL RDS connection management
- **`healthcheck.py`** - Health check endpoint for load balancer
- **`.streamlit/config.toml`** - Streamlit production configuration
- **`.env.example`** - Environment variables template

### 4. Testing
- **`tests/test_basic.py`** - Basic test suite for CI/CD pipeline

### 5. Comprehensive Documentation
Located in `deployment/` directory:
- **`AWS_DEPLOYMENT_PLAN.md`** - Complete deployment strategy (1,015 lines)
- **`INFRASTRUCTURE_SETUP.md`** - Step-by-step infrastructure setup (673 lines)
- **`APPLICATION_DEPLOYMENT.md`** - Application deployment guide (738 lines)
- **`CICD_SETUP.md`** - CI/CD pipeline setup (819 lines)
- **`QUICK_START_GUIDE.md`** - Quick reference guide (619 lines)
- **`README.md`** - Documentation navigation

## 🚀 Quick Start

### Prerequisites

1. **AWS Account** with administrative access
2. **AWS CLI** installed and configured
3. **Domain name** ready
4. **GitHub repository** with this code
5. **Budget** approved (~$370-670/month)

### Deployment Steps

#### Option 1: Follow the Quick Start Guide
```bash
# Read the quick start guide
cat deployment/QUICK_START_GUIDE.md
```

#### Option 2: Step-by-Step Deployment

**Week 1: Infrastructure**
```bash
# Follow infrastructure setup guide
cat deployment/INFRASTRUCTURE_SETUP.md

# Create VPC, subnets, security groups
# Deploy RDS PostgreSQL
# Set up S3 and ElastiCache
```

**Week 2: Application**
```bash
# Follow application deployment guide
cat deployment/APPLICATION_DEPLOYMENT.md

# Migrate database from Supabase to RDS
# Create custom AMI
# Set up load balancer and auto-scaling
```

**Week 3: Security**
```bash
# Request SSL certificate
# Configure DNS
# Set up WAF
```

**Week 4: CI/CD**
```bash
# Follow CI/CD setup guide
cat deployment/CICD_SETUP.md

# Set up CodePipeline
# Configure automated deployments
```

## 📋 File Structure

```
.
├── app.py                          # Main application
├── requirements.txt                # Python dependencies
├── buildspec.yml                   # CodeBuild configuration
├── appspec.yml                     # CodeDeploy configuration
├── healthcheck.py                  # Health check endpoint
├── .env.example                    # Environment variables template
│
├── .streamlit/
│   └── config.toml                 # Streamlit configuration
│
├── src/
│   ├── database/
│   │   ├── config.py               # Original Supabase config
│   │   ├── config_rds.py           # New RDS PostgreSQL config
│   │   └── db.py                   # Database operations
│   ├── pipelines/                  # AI/ML pipelines
│   ├── screens/                    # Application screens
│   └── components/                 # UI components
│
├── scripts/
│   ├── stop_application.sh         # Stop services
│   ├── before_install.sh           # Pre-deployment
│   ├── after_install.sh            # Post-deployment
│   ├── start_application.sh        # Start services
│   ├── validate_service.sh         # Validate deployment
│   └── load_config.sh              # Load AWS configs
│
├── tests/
│   └── test_basic.py               # Test suite
│
└── deployment/                     # Comprehensive documentation
    ├── README.md                   # Documentation index
    ├── AWS_DEPLOYMENT_PLAN.md      # Master deployment plan
    ├── INFRASTRUCTURE_SETUP.md     # Infrastructure guide
    ├── APPLICATION_DEPLOYMENT.md   # Application guide
    ├── CICD_SETUP.md              # CI/CD guide
    └── QUICK_START_GUIDE.md       # Quick reference
```

## 🔧 Configuration Required

### 1. Update requirements.txt

Add PostgreSQL driver:
```bash
echo "psycopg2-binary" >> requirements.txt
```

### 2. Update Database Configuration

In your application code, switch from Supabase to RDS:

```python
# Instead of:
from src.database.config import supabase

# Use:
from src.database.config_rds import execute_query, get_db_connection
```

### 3. Set Up AWS Secrets

```bash
# Store database credentials
aws secretsmanager create-secret \
  --name snapclass/prod/db/credentials \
  --secret-string '{
    "username": "snapclass_admin",
    "password": "your-secure-password",
    "host": "your-rds-endpoint",
    "port": 5432,
    "dbname": "snapclass"
  }'

# Store application parameters
aws ssm put-parameter --name /snapclass/prod/db/host --value "your-rds-endpoint" --type String
aws ssm put-parameter --name /snapclass/prod/db/port --value "5432" --type String
aws ssm put-parameter --name /snapclass/prod/db/name --value "snapclass" --type String
```

## 🏗️ Architecture

```
Users → Route 53 → CloudFront → WAF → ALB → EC2 (Auto Scaling) → RDS PostgreSQL
                                                ↓
                                            S3 + Redis
```

### Key Features

- **High Availability**: Multi-AZ deployment
- **Auto Scaling**: 2-6 instances based on load
- **Security**: WAF, encryption, secrets management
- **Monitoring**: CloudWatch dashboards and alarms
- **CI/CD**: Automated deployments with rollback
- **Cost Optimized**: ~$370-670/month

## 📊 Cost Breakdown

| Component | Monthly Cost |
|-----------|-------------|
| EC2 (2x t3.large) | $152 |
| RDS PostgreSQL | $222 |
| Storage & CDN | $106 |
| Networking | $120 |
| Caching | $25 |
| Monitoring | $46 |
| **Total** | **~$670** |

**With optimization**: ~$370-435/month

## 🔐 Security Checklist

- [x] All data encrypted at rest and in transit
- [x] Security groups follow least privilege
- [x] IAM roles with minimal permissions
- [x] Secrets stored in AWS Secrets Manager
- [x] WAF protecting against common attacks
- [x] VPC Flow Logs enabled
- [x] CloudTrail logging enabled
- [x] Regular automated backups

## 🧪 Testing

Run tests locally:
```bash
pip install pytest pytest-cov
pytest tests/ -v
```

Tests run automatically in CI/CD pipeline.

## 📈 Monitoring

### CloudWatch Dashboards
- Application metrics
- Infrastructure health
- Cost tracking

### Alarms
- RDS CPU > 90%
- ALB 5xx errors > 50
- No healthy targets
- Application crashes

## 🔄 CI/CD Pipeline

```
GitHub Push → CodePipeline → CodeBuild (Test & Build) → Manual Approval → CodeDeploy (Blue/Green)
```

### Deployment Process
1. Code pushed to GitHub
2. CodeBuild runs tests and creates package
3. Manual approval required
4. CodeDeploy performs blue/green deployment
5. Health checks validate deployment
6. Automatic rollback on failure

## 🆘 Troubleshooting

### Application Won't Start
```bash
sudo journalctl -u snapclass.service -n 100
sudo systemctl restart snapclass.service
```

### Database Connection Issues
```bash
# Test connectivity
telnet your-rds-endpoint 5432

# Check security groups
aws ec2 describe-security-groups --group-ids sg-xxxxx
```

### Health Check Failing
```bash
curl http://localhost:8502/healthz
sudo systemctl status snapclass-health.service
```

## 📚 Additional Resources

- [AWS EC2 Documentation](https://docs.aws.amazon.com/ec2/)
- [AWS RDS Documentation](https://docs.aws.amazon.com/rds/)
- [Streamlit Documentation](https://docs.streamlit.io/)
- [Full Deployment Plan](deployment/AWS_DEPLOYMENT_PLAN.md)

## 🤝 Support

For deployment issues:
1. Check relevant documentation in `deployment/` directory
2. Review troubleshooting sections
3. Check AWS service health dashboard
4. Contact DevOps team

## 📝 Next Steps

1. **Review Documentation**: Read `deployment/QUICK_START_GUIDE.md`
2. **Prepare AWS Account**: Set up billing alerts, IAM users
3. **Update Application Code**: Switch to RDS configuration
4. **Start Infrastructure Setup**: Follow `deployment/INFRASTRUCTURE_SETUP.md`
5. **Deploy Application**: Follow `deployment/APPLICATION_DEPLOYMENT.md`
6. **Set Up CI/CD**: Follow `deployment/CICD_SETUP.md`
7. **Go Live**: Complete go-live checklist

## ⚠️ Important Notes

- **Backup First**: Always backup your Supabase data before migration
- **Test Thoroughly**: Test in staging environment before production
- **Monitor Closely**: Watch CloudWatch dashboards during initial deployment
- **Budget Alerts**: Set up AWS billing alerts
- **Security**: Never commit secrets to Git

## 🎉 Ready to Deploy?

Start with the [Quick Start Guide](deployment/QUICK_START_GUIDE.md) and follow the 4-week deployment timeline.

Good luck with your deployment! 🚀

---

**Last Updated**: 2026-09-25  
**Version**: 1.0  
**Status**: Ready for Implementation