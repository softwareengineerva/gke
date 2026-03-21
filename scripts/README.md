# Load Test Scripts for Metrics Generation

**Author:** Jian Ouyang (jian.ouyang@sapns2.com)

This directory contains load test scripts to generate realistic metrics for PostgreSQL and NGINX monitoring in Grafana.

## Scripts

### 1. `postgres-load-test.sh`

Generates PostgreSQL database activity for metrics collection.

**What it does:**
- Checks if test table exists, creates it if needed
- Inserts records with unique IDs (no primary key duplication)
- Performs SELECT, UPDATE, and transaction operations
- Generates metrics for connection count, transaction rates, tuple operations, and database size

**Usage:**

```bash
# Run the script
./scripts/postgres-load-test.sh
```

**Metrics Generated:**

View these metrics in Grafana:
- `pg_stat_database_connections` - Active connections
- `pg_stat_database_transactions_commits` - Transaction commits
- `pg_stat_database_transactions_rollbacks` - Transaction rollbacks
- `pg_stat_database_transactions_tuples_inserted` - Rows inserted
- `pg_stat_database_transactions_tuples_updated` - Rows updated
- `pg_stat_database_size_bytes` - Database size
- `pg_table_size_bytes` - Table size
- Cache hit ratio (blocks_hit / (blocks_hit + blocks_read))

**Sample Output:**

```
=== PostgreSQL Load Test Script ===
Namespace: postgres
Pod: postgres-0
Database: testdb
Table: metrics_test

✓ Pod is running
✓ Table metrics_test already exists
Current max ID: 50
Inserting test records...
  Inserted record 1: login (value: 234)
  Inserted record 2: purchase (value: 789)
  ...
✓ Inserted 10 records successfully
✓ Database operations completed

=== Database Statistics ===
Total records: 60
Records by event type:
  purchase: 15
  login: 12
  ...
```

---

### 2. `nginx-load-test.sh`

Generates HTTP traffic to NGINX for metrics collection.

**What it does:**
- Makes continuous HTTP requests to NGINX service
- 70% successful requests (GET /)
- 30% failed requests (404 errors to various non-existent paths)
- Displays real-time statistics and success/failure rates

**Usage:**

```bash
# Run for 60 seconds (default)
./scripts/nginx-load-test.sh

# Run indefinitely (press Ctrl+C to stop)
# Edit DURATION=0 in the script
```

**Configuration:**

Edit these variables in the script:
```bash
INTERVAL=0.5   # Seconds between requests (default: 0.5s)
DURATION=60    # Total duration in seconds (0 for infinite)
```

**Metrics Generated:**

View these metrics in Grafana:
- `nginx_http_requests_total` - Total HTTP requests
- `nginx_connections_active` - Active connections
- `nginx_connections_accepted` - Accepted connections
- `nginx_connections_handled` - Handled connections
- `nginx_connections_reading` - Connections reading request
- `nginx_connections_writing` - Connections writing response
- `nginx_connections_waiting` - Idle keepalive connections
- HTTP status code distribution (200, 404)

**Sample Output:**

```
=== NGINX Load Test Script ===
Namespace: nginx-alb
Service: nginx:80
Interval: 0.5s between requests
Duration: 60s

✓ Service found at 10.0.1.123:80
Starting load test...

✓ [1] GET / (index.html) - HTTP 200 (Success)
✗ [2] GET /notfound.html - HTTP 404 (Expected: 404)
✓ [3] GET / (index.html) - HTTP 200 (Success)
...

=== Statistics ===
Total Requests:   100
Successful:       70
Failed:           30
Success Rate:     70.00%
Failure Rate:     30.00%
```

---

## Prerequisites

- kubectl configured with access to the GKE cluster
- PostgreSQL pod running in `postgres` namespace
- NGINX service running in `nginx-alb` namespace
- Prometheus and Grafana monitoring stack deployed

## Grafana Dashboard Setup

### For PostgreSQL Metrics

1. **Import PostgreSQL Dashboard:**
   - Dashboard ID: `9628` (PostgreSQL Database)
   - Or create custom dashboard using metrics above

2. **Sample Queries:**
   ```promql
   # Active connections
   pg_stat_database_connections{datname="testdb"}

   # Transaction rate
   rate(pg_stat_database_transactions_commits[5m])

   # Cache hit ratio
   rate(pg_stat_database_transactions_blocks_hit[5m]) /
   (rate(pg_stat_database_transactions_blocks_hit[5m]) +
    rate(pg_stat_database_transactions_blocks_read[5m]))

   # Rows inserted per second
   rate(pg_stat_database_transactions_tuples_inserted[5m])
   ```

### For NGINX Metrics

1. **Import NGINX Dashboard:**
   - Dashboard ID: `12708` (NGINX Exporter)
   - Or create custom dashboard using metrics above

2. **Sample Queries:**
   ```promql
   # Requests per second
   rate(nginx_http_requests_total[5m])

   # Active connections
   nginx_connections_active

   # Success rate (if you have status codes)
   sum(rate(nginx_http_requests_total{status=~"2.."}[5m])) /
   sum(rate(nginx_http_requests_total[5m]))

   # Error rate
   sum(rate(nginx_http_requests_total{status=~"4..|5.."}[5m])) /
   sum(rate(nginx_http_requests_total[5m]))
   ```

---

## Running Tests Continuously

### Using cron (every 5 minutes)

```bash
# Add to crontab
*/5 * * * * /path/to/gke/scripts/postgres-load-test.sh >> /tmp/postgres-load.log 2>&1
```

### Using Kubernetes CronJob

Create a CronJob to run the load tests periodically:

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: postgres-load-test
  namespace: postgres
spec:
  schedule: "*/5 * * * *"  # Every 5 minutes
  jobTemplate:
    spec:
      template:
        spec:
          serviceAccountName: postgres-sa
          containers:
          - name: load-test
            image: postgres:16-alpine
            command:
            - /bin/sh
            - -c
            - |
              psql -U postgres -d testdb -c "INSERT INTO metrics_test (event_type, message, value) VALUES ('cronjob', 'Scheduled test', $((RANDOM % 1000)));"
          restartPolicy: OnFailure
```

---

## Troubleshooting

### PostgreSQL Script Issues

**Error: Pod postgres-0 not found**
```bash
# Check if pod exists
kubectl get pods -n postgres

# Check pod status
kubectl describe pod postgres-0 -n postgres
```

**Error: Table creation failed**
```bash
# Check PostgreSQL logs
kubectl logs postgres-0 -n postgres -c postgres

# Verify database exists
kubectl exec -it postgres-0 -n postgres -c postgres -- psql -U postgres -l
```

### NGINX Script Issues

**Error: Service nginx not found**
```bash
# Check if service exists
kubectl get svc -n nginx-alb

# Check if pods are running
kubectl get pods -n nginx-alb
```

**Curl pod fails to start**
```bash
# Check for resource constraints
kubectl describe nodes

# Manually test NGINX service
kubectl run -it --rm debug --image=curlimages/curl --restart=Never -- \
  curl http://nginx.nginx-alb.svc.cluster.local
```

---

## Best Practices

1. **PostgreSQL Load Test:**
   - Run periodically (every 5-10 minutes) to generate steady metrics
   - Monitor table size growth and clean up old records if needed
   - Adjust RECORD_COUNT based on desired load

2. **NGINX Load Test:**
   - Adjust INTERVAL to control request rate (lower = more load)
   - Run for limited DURATION to avoid overwhelming the service
   - Monitor NGINX pod resource usage

3. **Metrics Collection:**
   - Ensure Prometheus scrape interval matches load test frequency
   - Set appropriate retention periods for metrics
   - Create alerts for abnormal patterns

---

## Cleaning Up Test Data

### PostgreSQL

```bash
# Connect to database
kubectl exec -it postgres-0 -n postgres -c postgres -- psql -U postgres -d testdb

# Delete old records (keep last hour)
DELETE FROM metrics_test WHERE created_at < NOW() - INTERVAL '1 hour';

# Or truncate entire table
TRUNCATE TABLE metrics_test;

# Drop table completely
DROP TABLE metrics_test;
```

---

## References

- [PostgreSQL Monitoring with Prometheus](https://prometheus.io/docs/guides/postgres/)
- [NGINX Prometheus Exporter](https://github.com/nginxinc/nginx-prometheus-exporter)
- [Grafana Dashboard for PostgreSQL](https://grafana.com/grafana/dashboards/9628)
- [Grafana Dashboard for NGINX](https://grafana.com/grafana/dashboards/12708)
