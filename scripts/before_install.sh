#!/bin/bash
set -e

echo "Preparing for installation..."

# Create releases directory if not exists
mkdir -p /opt/snapclass/releases

# Backup current release
if [ -d "/opt/snapclass/releases/current" ]; then
    TIMESTAMP=$(date +%Y%m%d-%H%M%S)
    mv /opt/snapclass/releases/current /opt/snapclass/releases/backup-$TIMESTAMP
    echo "Current release backed up to backup-$TIMESTAMP"
fi

# Clean old backups (keep last 3)
cd /opt/snapclass/releases
ls -t | grep backup | tail -n +4 | xargs -r rm -rf

echo "Pre-installation completed"

# Made with Bob
