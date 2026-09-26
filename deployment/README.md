# SnapClass AWS Deployment Documentation

Complete guide for deploying the SnapClass AI Attendance application to AWS following industry best practices.

## 📚 Documentation Structure

This deployment package contains comprehensive guides for every aspect of the AWS deployment:

### 1. [AWS_DEPLOYMENT_PLAN.md](AWS_DEPLOYMENT_PLAN.md) - Master Plan
**Start here for the complete overview**

- Executive summary and architecture diagrams
- Technology stack details
- Infrastructure components breakdown
- Deployment phases (4-week timeline)
- Security implementation
- Monitoring and alerting strategy
- CI/CD pipeline architecture
- Cost estimation ($370-670/month)
- Disaster recovery procedures
- Complete implementation checklist

**Best for**: Understanding the big picture, presenting to stakeholders, architectural decisions

### 2. [QUICK_START_GUIDE.md](QUICK_START_GUIDE.md) - Fast Track
**Your deployment roadmap**

- Prerequisites checklist
- Week-by-week deployment timeline
- Phase-by-phase instructions
- Essential commands reference
- Common issues and solutions
- Cost optimization tips
- Security checklist
- Go-live checklist

**Best for**: Project managers, quick reference, tracking progress

### 3. [INFRASTRUCTURE_SETUP.md](INFRASTRUCTURE_SETUP.md) - Foundation
**Detailed infrastructure commands**

- VPC and network configuration
- Security groups setup
- RDS PostgreSQL deployment
- S3 bucket configuration
- ElastiCache Redis setup
- IAM roles and policies
- Secrets management
- Step-by-step AWS CLI commands

**Best for**: DevOps engineers, infrastructure setup, troubleshooting

### 4. [APPLICATION_DEPLOYMENT.md](APPLICATION_DEPLOYMENT.md) - Application Layer
**Application-specific deployment**

- Database migration from Supabase to RDS
- Custom AMI creation with dependencies
- Application configuration
- Load balancer setup
- Auto Scaling configuration
- Health check implementation
- DNS configuration
- Deployment verification

**Best for**: Application developers, deployment engineers, operations team

### 5. [CICD_SETUP.md](CICD_SETUP.md) - Automation
**Complete CI/CD pipeline**

- Repository preparation (buildspec.yml, appspec.yml)
- CodeBuild configuration
- CodeDeploy setup
- CodePipeline creation
- GitHub integration
- Blue/Green deployment
- Automated testing
- Rollback procedures

**Best for**: DevOps engineers, automation, continuous deployment

## 🚀 Quick Navigation

### I'm a...

**Project Manager / Stakeholder**
1. Read: [AWS_DEPLOYMENT_PLAN.md](AWS_DEPLOYMENT_PLAN.md) - Executive Summary
2. Review: Cost Estimation section
3. Check: [QUICK_START_GUIDE.md](QUICK_START_GUIDE.md) - Timeline

**DevOps Engineer**
1. Start: [QUICK_START_GUIDE.md](QUICK_START_GUIDE.md) - Prerequisites
2. Follow: [INFRASTRUCTURE_SETUP.md](INFRASTRUCTURE_SETUP.md) - Phase by phase
3. Then: [APPLICATION_DEPLOYMENT.md](APPLICATION_DEPLOYMENT.md)
4. Finally: [CICD_SETUP.md](CICD_SETUP.md)

**Application Developer**
1. Review: [APPLICATION_DEPLOYMENT.md](APPLICATION_DEPLOYMENT.md) - Database Migration
2. Understand: Custom AMI creation process
3. Configure: Application for production
4. Test: Health checks and monitoring

**Security Engineer**
1. Review: [AWS_DEPLOYMENT_PLAN.md](AWS_DEPLOYMENT_PLAN.md) - Security Implementation
2. Check: [INFRASTRUCTURE_SETUP.md](INFRASTRUCTURE_SETUP.md) - Security Groups
3. Verify: [QUICK_START_GUIDE.md](QUICK_START_GUIDE.md) - Security Checklist

## 📋 Deployment Phases Overview

```
Week 1: Infrastructure Foundation
├── Network Setup (VPC, Subnets, Security Groups)
├── Database Setup (RDS PostgreSQL Multi-AZ)
└── Storage Setup (S3, ElastiCache Redis)

Week 2: Application Deployment
├── Database Migration (Supabase → RDS)
├── Custom AMI Creation
├── Load Balancer Configuration
└── Auto Scaling Setup

Week 3: Security & SSL
├── SSL Certificate (ACM)
├── DNS Configuration (Route 53)
└── WAF & Security Hardening

Week 4: Operations & CI/CD
├── Monitoring Setup (CloudWatch)
├── CI/CD Pipeline (CodePipeline)
└── Testing & Go-Live
```

## 🏗️ Architecture Highlights

### High Availability
- **Multi-AZ deployment** across 2 availability zones
- **Auto Scaling** from 2 to 6 instances based on load
- **RDS Multi-AZ** with automatic failover
- **Application Load Balancer** with health checks

### Security
- **Defense in depth**: WAF, Security Groups, Network ACLs
- **Encryption**: At rest (RDS, S3, EBS) and in transit (TLS 1.2+)
- **Secrets Management**: AWS Secrets Manager & Parameter Store
- **Monitoring**: CloudWatch, GuardDuty, Security Hub

### Performance
- **CDN**: CloudFront for global content delivery
- **Caching**: ElastiCache Redis for sessions and ML models
- **Optimized**: GP3 SSD storage, enhanced networking

### Reliability
- **Automated backups**: RDS (7 days), S3 versioning
- **Health checks**: Application and infrastructure level
- **Auto-recovery**: Automatic instance replacement
- **Disaster recovery**: Cross-region backup capability

## 💰 Cost Overview

### Initial Monthly Cost: ~$670
- Compute (EC2): $152
- Database (RDS): $222
- Storage & CDN: $106
- Networking: $120
- Caching: $25
- Monitoring: $46
- CI/CD: $2

### Optimized Monthly Cost: ~$370-435
With Reserved Instances, right-sizing, and optimization strategies

**See**: [AWS_DEPLOYMENT_PLAN.md](AWS_DEPLOYMENT_PLAN.md) - Cost Estimation for detailed breakdown

## 🔧 Technology Stack

### Application
- **Framework**: Streamlit (Python 3.9+)
- **AI/ML**: dlib, face_recognition, librosa, resemblyzer, scikit-learn
- **Database**: PostgreSQL 14.x

### Infrastructure
- **Compute**: EC2 t3.large (Auto Scaling)
- **Database**: RDS PostgreSQL (Multi-AZ)
- **Load Balancer**: Application Load Balancer
- **CDN**: CloudFront
- **Storage**: S3, ElastiCache Redis
- **DNS**: Route 53

### DevOps
- **IaC**: Terraform (optional)
- **CI/CD**: CodePipeline, CodeBuild, CodeDeploy
- **Monitoring**: CloudWatch, X-Ray
- **Secrets**: Secrets Manager, Parameter Store

## 📊 Key Metrics & Monitoring

### Application Metrics
- Request rate and response time
- Error rates (4xx, 5xx)
- Face/voice recognition processing time
- Active user sessions

### Infrastructure Metrics
- EC2 CPU, memory, disk utilization
- RDS CPU, connections, latency
- ALB request count and target health
- Cache hit/miss ratio

### Alarms (Critical)
- RDS CPU > 90%
- ALB 5xx errors > 50
- No healthy targets
- Application crashes

**See**: [AWS_DEPLOYMENT_PLAN.md](AWS_DEPLOYMENT_PLAN.md) - Monitoring & Alerting

## 🔐 Security Best Practices

✅ All data encrypted at rest and in transit  
✅ Security groups follow least privilege  
✅ IAM roles with minimal permissions  
✅ MFA enabled on root account  
✅ CloudTrail and GuardDuty enabled  
✅ WAF protecting against common attacks  
✅ Regular security audits  
✅ Secrets never hardcoded  
✅ VPC Flow Logs enabled  
✅ Regular backup testing  

**See**: [QUICK_START_GUIDE.md](QUICK_START_GUIDE.md) - Security Checklist

## 🚨 Common Issues & Quick Fixes

### Application Won't Start
```bash
sudo journalctl -u snapclass.service -n 100
sudo systemctl restart snapclass.service
```

### Database Connection Issues
```bash
# Test connectivity
telnet <rds-endpoint> 5432
# Check security groups
aws ec2 describe-security-groups --group-ids <sg-id>
```

### Health Check Failing
```bash
curl http://localhost:8502/healthz
sudo systemctl status snapclass-health.service
```

**See**: [QUICK_START_GUIDE.md](QUICK_START_GUIDE.md) - Common Issues & Solutions

## 📞 Support & Resources

### AWS Documentation
- [EC2 User Guide](https://docs.aws.amazon.com/ec2/)
- [RDS User Guide](https://docs.aws.amazon.com/rds/)
- [ELB User Guide](https://docs.aws.amazon.com/elasticloadbalancing/)

### Internal Documentation
- All guides in this [`deployment/`](.) directory
- Application code documentation
- Team runbooks and procedures

### Getting Help
1. Check relevant documentation guide
2. Review troubleshooting sections
3. Check AWS service health dashboard
4. Contact AWS Support (if applicable)
5. Escalate to team lead

## ✅ Pre-Deployment Checklist

Before starting deployment, ensure:

- [ ] AWS account configured with billing alerts
- [ ] AWS CLI installed and configured
- [ ] Domain name ready and accessible
- [ ] GitHub repository prepared
- [ ] Team trained on AWS services
- [ ] Budget approved (~$670/month initial)
- [ ] Backup of current Supabase data
- [ ] All documentation reviewed
- [ ] Deployment timeline approved
- [ ] Rollback plan documented

## 🎯 Success Criteria

Deployment is successful when:

- [ ] Application accessible via HTTPS on custom domain
- [ ] Auto Scaling working (scales up/down based on load)
- [ ] Database migrated with all data intact
- [ ] Health checks passing consistently
- [ ] Monitoring and alerting operational
- [ ] CI/CD pipeline tested and working
- [ ] Security audit passed
- [ ] Backup and restore tested
- [ ] Team trained on operations
- [ ] Documentation complete and accessible

## 📈 Post-Deployment Tasks

### Week 1
- Monitor metrics closely
- Optimize based on actual usage
- Address any issues immediately
- Gather user feedback

### Month 1
- Implement cost optimizations
- Review and adjust scaling policies
- Update documentation based on learnings
- Conduct security review

### Month 2-3
- Consider Reserved Instances
- Optimize database queries
- Implement additional caching
- Plan capacity for growth

### Ongoing
- Regular security audits
- Performance optimization
- Cost optimization reviews
- Disaster recovery testing

## 🔄 Maintenance Schedule

### Daily
- Monitor CloudWatch dashboards
- Review error logs
- Check backup status

### Weekly
- Review cost reports
- Analyze performance metrics
- Update security patches

### Monthly
- Security audit
- Capacity planning review
- Cost optimization analysis
- Backup restoration test

### Quarterly
- Disaster recovery drill
- Architecture review
- Team training update
- Documentation review

## 📝 Version History

| Version | Date | Changes | Author |
|---------|------|---------|--------|
| 1.0 | 2026-09-25 | Initial deployment documentation | Deployment Team |

## 🤝 Contributing

To update this documentation:

1. Make changes to relevant markdown files
2. Update version history
3. Test all commands and procedures
4. Submit for review
5. Update after approval

## 📄 License

Internal documentation for SnapClass AI Attendance project.

---

## 🚀 Ready to Deploy?

1. **Start here**: [QUICK_START_GUIDE.md](QUICK_START_GUIDE.md)
2. **Understand the plan**: [AWS_DEPLOYMENT_PLAN.md](AWS_DEPLOYMENT_PLAN.md)
3. **Build infrastructure**: [INFRASTRUCTURE_SETUP.md](INFRASTRUCTURE_SETUP.md)
4. **Deploy application**: [APPLICATION_DEPLOYMENT.md](APPLICATION_DEPLOYMENT.md)
5. **Automate**: [CICD_SETUP.md](CICD_SETUP.md)

**Questions?** Review the relevant guide or contact the deployment team.

**Good luck with your deployment! 🎉**

---

**Last Updated**: 2026-09-25  
**Maintained by**: DevOps Team  
**Status**: Ready for Implementation