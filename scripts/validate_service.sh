#!/bin/bash
set -e

echo "Validating service..."

# Check if services are running
if ! sudo systemctl is-active --quiet snapclass.service; then
    echo "ERROR: SnapClass service is not running"
    exit 1
fi

if ! sudo systemctl is-active --quiet snapclass-health.service; then
    echo "ERROR: Health check service is not running"
    exit 1
fi

# Test health endpoint
MAX_RETRIES=10
RETRY_COUNT=0

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    if curl -f http://localhost:8502/healthz > /dev/null 2>&1; then
        echo "Health check passed"
        break
    fi
    
    RETRY_COUNT=$((RETRY_COUNT + 1))
    echo "Health check attempt $RETRY_COUNT/$MAX_RETRIES failed, retrying..."
    sleep 5
done

if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
    echo "ERROR: Health check failed after $MAX_RETRIES attempts"
    exit 1
fi

# Test application endpoint
if curl -f http://localhost:8501 > /dev/null 2>&1; then
    echo "Application endpoint is responding"
else
    echo "WARNING: Application endpoint not responding, but health check passed"
fi

echo "Service validation completed successfully"
exit 0

# Made with Bob
