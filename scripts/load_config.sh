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

# Made with Bob
