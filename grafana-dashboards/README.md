# Grafana Dashboards for Load Testing

**Author:** Jian Ouyang (jian.ouyang@sapns2.com)

This directory contains Grafana dashboards for monitoring load test activities in the GKE cluster.

## Available Dashboards

### 1. NGINX Load Test Dashboard
**File:** `nginx-load-test-dashboard.json`
**UID:** `nginx-load-test`

Monitors NGINX web server performance during load testing.

**Panels:**
- HTTP Request Rate (requests per second)
- HTTP Status Codes Distribution (2xx, 4xx, 5xx)
- Success Rate (gauge showing % of 2xx responses)
- Active Connections
- Total Requests (last hour)
- NGINX Connection States (active, reading, writing, waiting)
- Status Code Distribution (pie chart)
- CPU Usage

**Refresh Rate:** 5 seconds
**Time Window:** Last 15 minutes

**Key Metrics:**
- `nginx_http_requests_total{namespace="nginx-alb"}`
- `nginx_connections_active{namespace="nginx-alb"}`
- `nginx_connections_reading{namespace="nginx-alb"}`
- `nginx_connections_writing{namespace="nginx-alb"}`
- `nginx_connections_waiting{namespace="nginx-alb"}`
- `container_cpu_usage_seconds_total{namespace="nginx-alb"}`

### 2. PostgreSQL Load Test Dashboard
**File:** `postgres-load-test-dashboard.json`
**UID:** `postgres-load-test`

Monitors PostgreSQL database performance during load testing.

### 3. Kubernetes API Server Dashboard
**File:** `k8s-apiserver-dashboard.json`
**UID:** `k8s-apiserver`

Monitors Kubernetes API Server performance without requiring cluster labels.

**Note:** This is a simplified version of the default Kubernetes API Server dashboard that works in single-cluster deployments without the `cluster` label. The default multi-cluster dashboards require metrics to have a `cluster` label which is not present in single-cluster setups.

**Panels:**
- API Server Request Rate by Status Code
- Total Request Rate
- API Server Request Latency (p99, p95, p50)
- API Server Requests by Verb (GET, LIST, WATCH, etc.)
- API Server In-Flight Requests
- API Server CPU Usage
- API Server Memory Usage

**Refresh Rate:** 5 seconds
**Time Window:** Last 15 minutes

**Key Metrics:**
- `apiserver_request_total`
- `apiserver_request_duration_seconds_bucket`
- `apiserver_current_inflight_requests`
- `process_cpu_seconds_total{job="apiserver"}`
- `process_resident_memory_bytes{job="apiserver"}`

### 4. PostgreSQL (original panels)
- Database Connections by State (active, idle, idle in transaction, waiting)
- Transaction Rate (commits/rollbacks per second)
- Cache Hit Ratio (gauge showing buffer cache efficiency)
- Total Connections
- Database Size
- Tuple Operations Rate (inserts, updates, deletes, fetches)
- Database Locks
- Table Statistics (live vs dead tuples)
- Checkpoint Activity
- CPU Usage

**Refresh Rate:** 5 seconds
**Time Window:** Last 15 minutes

**Key Metrics:**
- `pg_stat_activity_count`
- `pg_stat_database_xact_commit{datname="testdb"}`
- `pg_stat_database_xact_rollback{datname="testdb"}`
- `pg_stat_database_blks_hit{datname="testdb"}`
- `pg_stat_database_blks_read{datname="testdb"}`
- `pg_stat_database_tup_inserted{datname="testdb"}`
- `pg_stat_database_tup_updated{datname="testdb"}`
- `pg_stat_database_tup_deleted{datname="testdb"}`
- `pg_locks_count`
- `pg_database_size_bytes{datname="testdb"}`

## Importing Dashboards into Grafana

### Option 1: Import via Grafana UI

1. Access Grafana:
   ```bash
   kubectl port-forward -n monitoring svc/prometheus-stack-grafana 3000:80
   ```
   Navigate to: http://localhost:3000 (admin/admin)

2. Import dashboard:
   - Click **+** → **Import**
   - Click **Upload JSON file**
   - Select the dashboard JSON file
   - Click **Load**
   - Select **Prometheus** as the datasource
   - Click **Import**

### Option 2: Import via ConfigMap (Auto-provisioning)

Add dashboards to Grafana's provisioning:

```yaml
# Add to k8s-manifests/monitoring/helm-values.yaml
grafana:
  dashboardProviders:
    dashboardproviders.yaml:
      apiVersion: 1
      providers:
        - name: 'load-tests'
          orgId: 1
          folder: 'Load Testing'
          type: file
          disableDeletion: false
          editable: true
          options:
            path: /var/lib/grafana/dashboards/load-tests

  dashboards:
    load-tests:
      nginx-load-test:
        file: grafana-dashboards/nginx-load-test-dashboard.json
      postgres-load-test:
        file: grafana-dashboards/postgres-load-test-dashboard.json
```

### Option 3: Import via API

```bash
# Port-forward Grafana
kubectl port-forward -n monitoring svc/prometheus-stack-grafana 3000:80

# Import NGINX dashboard
curl -X POST http://admin:admin@localhost:3000/api/dashboards/db \
  -H "Content-Type: application/json" \
  -d @nginx-load-test-dashboard.json

# Import PostgreSQL dashboard
curl -X POST http://admin:admin@localhost:3000/api/dashboards/db \
  -H "Content-Type: application/json" \
  -d @postgres-load-test-dashboard.json
```

## Running Load Tests

### NGINX Load Test
```bash
# Run load test script
cd /opt/code/aaa_all_tests/gke/scripts
./nginx-load-test.sh

# Monitor in Grafana
# Navigate to: Dashboards → NGINX Load Test Dashboard
```

### PostgreSQL Load Test
```bash
# Run load test script
cd /opt/code/aaa_all_tests/gke/scripts
./postgres-load-test.sh

# Monitor in Grafana
# Navigate to: Dashboards → PostgreSQL Load Test Dashboard
```

## Prerequisites

Both dashboards require:
1. **Prometheus Operator** with postgres-exporter and nginx-exporter configured
2. **ServiceMonitors** for both NGINX and PostgreSQL
3. **Load test scripts** running to generate metrics

### Verify Metrics Availability

Check if metrics are being collected:

```bash
# Port-forward Prometheus
kubectl port-forward -n monitoring svc/prometheus-stack-kube-prom-prometheus 9090:9090

# Check NGINX metrics (navigate to http://localhost:9090)
nginx_http_requests_total
nginx_connections_active

# Check PostgreSQL metrics
pg_stat_activity_count
pg_stat_database_xact_commit
```

## Troubleshooting

### No data showing in dashboards

1. **Verify Prometheus datasource:**
   ```bash
   # Check datasource configuration in Grafana
   # Settings → Data Sources → Prometheus
   # URL should be: http://prometheus-stack-kube-prom-prometheus:9090
   ```

2. **Verify metrics exist:**
   ```bash
   # Port-forward Prometheus
   kubectl port-forward -n monitoring svc/prometheus-stack-kube-prom-prometheus 9090:9090

   # Query metrics in Prometheus UI
   # http://localhost:9090/graph
   ```

3. **Verify exporters are running:**
   ```bash
   # Check nginx-exporter
   kubectl get pods -n nginx-alb | grep exporter

   # Check postgres-exporter
   kubectl get pods -n default | grep postgres-exporter
   ```

4. **Check ServiceMonitors:**
   ```bash
   kubectl get servicemonitors -A | grep -E 'nginx|postgres'
   ```

### Metrics showing but dashboards empty

- Check time range (top-right corner of Grafana)
- Verify namespace labels match: `namespace="nginx-alb"` for NGINX, `datname="testdb"` for PostgreSQL
- Run the corresponding load test script to generate activity

## Dashboard Customization

Both dashboards are editable and can be customized:

- **Change refresh rate:** Dashboard settings → Time options → Auto refresh
- **Adjust time window:** Top-right time picker
- **Add new panels:** Click **Add panel** → **Add a new panel**
- **Modify queries:** Edit panel → Query tab
- **Change thresholds:** Edit panel → Thresholds tab

## Related Files

- Load test scripts: `/opt/code/aaa_all_tests/gke/scripts/`
  - `nginx-load-test.sh`
  - `postgres-load-test.sh`
- Monitoring configuration: `/opt/code/aaa_all_tests/gke/k8s-manifests/monitoring/`
- Prometheus configuration: `/opt/code/aaa_all_tests/gke/k8s-manifests/monitoring/helm-values.yaml`
