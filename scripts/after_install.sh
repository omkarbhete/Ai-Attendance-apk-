#!/bin/bash
set -e

echo "Configuring application..."

cd /opt/snapclass/releases/current

# Extract deployment package if exists
if [ -f "deployment.zip" ]; then
    unzip -o deployment.zip
    rm deployment.zip
fi

# Activate virtual environment
source /opt/snapclass/venv/bin/activate

# Install/update dependencies
pip install -r requirements.txt --quiet

# Load configuration from Parameter Store
source /opt/snapclass/scripts/load_config.sh

# Run database migrations if needed
# python scripts/migrate.py

# Set proper permissions
chmod +x /opt/snapclass/scripts/*.sh

# Create log directory if not exists
sudo mkdir -p /var/log/snapclass
sudo chown ec2-user:ec2-user /var/log/snapclass

echo "Post-installation configuration completed"

# Made with Bob
