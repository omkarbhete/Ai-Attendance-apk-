#!/bin/bash
set -e

echo "Starting SnapClass application..."

# Start health check service first
sudo systemctl start snapclass-health.service

# Wait for health check to be ready
sleep 3

# Start main application
sudo systemctl start snapclass.service

# Wait for application to start
sleep 10

echo "Application started successfully"

# Made with Bob
