#!/bin/bash
set -e

echo "Stopping SnapClass application..."

# Stop services gracefully
sudo systemctl stop snapclass.service || true
sudo systemctl stop snapclass-health.service || true

# Wait for processes to stop
sleep 5

echo "Application stopped successfully"

# Made with Bob
