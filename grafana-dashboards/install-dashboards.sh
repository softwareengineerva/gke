#!/bin/bash
#
# Script to install all Grafana dashboards in the current directory
#

set -e

# Configuration
GRAFANA_URL=${GRAFANA_URL:-"http://localhost:3000"}
GRAFANA_USER=${GRAFANA_USER:-"admin"}
GRAFANA_PASSWORD=${GRAFANA_PASSWORD:-"admin"}
DASHBOARDS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Checking Grafana connection at $GRAFANA_URL..."
if ! curl -s -f -u "$GRAFANA_USER:$GRAFANA_PASSWORD" "$GRAFANA_URL/api/health" > /dev/null; then
    echo "❌ Cannot connect to Grafana at $GRAFANA_URL (or authentication failed)."
    echo "Please ensure Grafana is accessible and port-forwarding is running:"
    echo "  kubectl port-forward -n monitoring svc/prometheus-stack-grafana 3000:80"
    exit 1
fi

echo "✅ Connected to Grafana successfully."
echo ""

# Loop through all JSON files in the directory
for file in "$DASHBOARDS_DIR"/*.json; do
    if [ -f "$file" ]; then
        filename=$(basename "$file")
        echo "Installing dashboard: $filename"
        
        # The Grafana API requires the dashboard to be wrapped in a {"dashboard": {...}} payload.
        # We use jq to construct this payload on the fly.
        if command -v jq >/dev/null 2>&1; then
            RESPONSE=$(jq -c '{"dashboard": ., "overwrite": true}' "$file" | \
            curl -s -X POST "$GRAFANA_URL/api/dashboards/db" \
                -u "$GRAFANA_USER:$GRAFANA_PASSWORD" \
                -H "Content-Type: application/json" \
                -d @-)
            
            # Basic check if it succeeded
            if echo "$RESPONSE" | grep -q '"status":"success"'; then
                echo "✅ Successfully imported $filename"
            else
                echo "⚠️  Failed or unexpected response for $filename: $RESPONSE"
            fi
        else
            echo "⚠️  'jq' is not installed. Attempting direct upload..."
            # Note: This might fail on some Grafana versions that strictly require the payload wrapper
            curl -s -X POST "$GRAFANA_URL/api/dashboards/db" \
                -u "$GRAFANA_USER:$GRAFANA_PASSWORD" \
                -H "Content-Type: application/json" \
                -d @"$file"
            echo "✅ Direct upload executed for $filename"
        fi
    fi
done

echo ""
echo "🎉 All dashboards processed!"
