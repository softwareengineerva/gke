# Linkerd Service Mesh Configuration

This directory contains Linkerd service mesh deployment configuration for the GKE cluster.

## Overview

**Linkerd** provides:
- **Zero-trust security**: Automatic mTLS between all services
- **Advanced observability**: Request-level metrics, success rates, latencies
- **Traffic management**: Circuit breaking, retries, timeouts
- **Production resilience**: Without code changes

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│ Linkerd Service Mesh                                    │
│                                                          │
│  ┌──────────────┐        ┌──────────────┐             │
│  │ NGINX Pod    │        │ PostgreSQL   │             │
│  │ ┌──────────┐ │        │ ┌──────────┐ │             │
│  │ │ App      │ │  mTLS  │ │ App      │ │             │
│  │ │Container │ │◄──────►│ │Container │ │             │
│  │ └──────────┘ │  🔒    │ └──────────┘ │             │
│  │ ┌──────────┐ │        │ ┌──────────┐ │             │
│  │ │ Linkerd  │ │        │ │ Linkerd  │ │             │
│  │ │ Proxy    │ │        │ │ Proxy    │ │             │
│  │ └──────────┘ │        │ └──────────┘ │             │
│  └──────────────┘        └──────────────┘             │
│         │                        │                      │
│         └────────────┬───────────┘                      │
│                      ▼                                  │
│              ┌──────────────┐                           │
│              │  Prometheus  │                           │
│              │   (metrics)  │                           │
│              └──────────────┘                           │
└─────────────────────────────────────────────────────────┘
```

## Deployment

Linkerd is deployed via ArgoCD in three components:

### 1. Linkerd CRDs
```yaml
# argocd-apps/linkerd-crds-app.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: linkerd-crds
spec:
  source:
    chart: linkerd-crds
    repoURL: https://helm.linkerd.io/stable
```

### 2. Linkerd Control Plane
```yaml
# argocd-apps/linkerd-app.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: linkerd
spec:
  source:
    chart: linkerd-control-plane
    repoURL: https://helm.linkerd.io/stable
```

### 3. Linkerd Viz (Dashboard & Metrics)
```yaml
# argocd-apps/linkerd-viz-app.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: linkerd-viz
spec:
  source:
    chart: linkerd-viz
    repoURL: https://helm.linkerd.io/stable
```

## Service Mesh Injection

Services are automatically meshed via namespace annotation:

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: nginx-alb
  annotations:
    linkerd.io/inject: enabled
```

**Meshed namespaces:**
- `nginx-alb` - NGINX web server
- `postgres` - PostgreSQL database
- `redis` - Redis cache
- `secrets-demo` - Secrets Manager demo

## Demo Scenarios

### Scenario 1: Verify mTLS Encryption

**Show automatic mTLS between services:**

```bash
# Install Linkerd CLI (if not already installed)
curl -fsL https://run.linkerd.io/install | sh
export PATH=$PATH:$HOME/.linkerd2/bin

# Check cluster status
linkerd check

# View meshed services
linkerd viz stat deploy -n nginx-alb
linkerd viz stat deploy -n postgres
linkerd viz stat deploy -n redis

# Expected output:
# NAME     MESHED   SUCCESS   RPS   P50   P95   P99
# nginx    1/1      100.00%   5.0   2ms   5ms   10ms
```

**Verify mTLS is active:**

```bash
# Tap live traffic (shows 🔒 for encrypted connections)
linkerd viz tap deploy/nginx -n nginx-alb

# Example output:
# req id=0:0 proxy=in  src=10.0.1.45:54321 dst=10.0.1.23:80 tls=true :method=GET
# rsp id=0:0 proxy=in  src=10.0.1.45:54321 dst=10.0.1.23:80 tls=true :status=200
```

### Scenario 2: Golden Metrics (Success Rate, Latency, RPS)

**View service-level metrics automatically:**

```bash
# Overall service metrics
linkerd viz stat deploy --all-namespaces

# Detailed route metrics
linkerd viz routes deploy/nginx -n nginx-alb

# Top metrics (most active services)
linkerd viz top deploy -n nginx-alb

# Expected output:
# SOURCE          METHOD  PATH     COUNT    BEST   WORST  LAST   SUCCESS
# nginx-7d8f9b6   GET     /        1000     1ms    50ms   2ms    100.00%
```

### Scenario 3: Service Topology Visualization

**View service dependencies:**

```bash
# Port-forward Linkerd dashboard
kubectl port-forward -n linkerd-viz svc/web 8084:8084

# Open in browser: http://localhost:8084
# Navigate to: Namespaces → nginx-alb → Deployments → nginx
```

**Dashboard shows:**
- Real-time request rate
- Success rate (%)
- P50, P95, P99 latency
- Service topology graph

### Scenario 4: Traffic Splitting (Canary Deployment)

**Gradual rollout of NGINX version:**

```bash
# 1. Deploy two versions of NGINX (v1.27 and v1.28)
# Edit k8s-manifests/nginx-alb/overlays/dev/kustomization.yaml

# 2. Create TrafficSplit resource
cat <<EOF | kubectl apply -f -
apiVersion: split.smi-spec.io/v1alpha2
kind: TrafficSplit
metadata:
  name: nginx-canary
  namespace: nginx-alb
spec:
  service: nginx
  backends:
  - service: nginx-v127
    weight: 90  # 90% traffic
  - service: nginx-v128
    weight: 10  # 10% traffic (canary)
EOF

# 3. Monitor canary performance
linkerd viz stat deploy/nginx-v128 -n nginx-alb

# 4. If healthy, shift traffic
kubectl patch trafficsplit nginx-canary -n nginx-alb --type merge \
  -p '{"spec":{"backends":[{"service":"nginx-v127","weight":50},{"service":"nginx-v128","weight":50}]}}'
```

### Scenario 5: Circuit Breaking & Retries

**Automatic resilience policies:**

```bash
# 1. View current retry policy
kubectl get httproute -n nginx-alb

# 2. Add retry policy for database connections
cat <<EOF | kubectl apply -f -
apiVersion: policy.linkerd.io/v1beta1
kind: HTTPRoute
metadata:
  name: postgres-retries
  namespace: postgres
spec:
  parentRefs:
    - name: postgres
      kind: Service
  rules:
    - backendRefs:
        - name: postgres
          port: 5432
      timeouts:
        request: 10s
      retry:
        attempts: 3
        backoff: 1s
EOF

# 3. Verify retry policy
linkerd viz tap deploy/postgres -n postgres --to deploy/postgres
```

### Scenario 6: Per-Route Metrics

**Analyze specific API endpoints:**

```bash
# View HTTP route performance
linkerd viz routes deploy/nginx -n nginx-alb --to svc/postgres

# Output shows:
# ROUTE                   SERVICE      SUCCESS   RPS   P50   P95   P99
# GET /api/users          postgres     100.00%   2.5   5ms   12ms  25ms
# POST /api/users         postgres      99.95%   1.2   8ms   20ms  40ms
```

## Integration with Existing Stack

### Prometheus Integration

Linkerd metrics are scraped by existing Prometheus:

```yaml
# k8s-manifests/monitoring/helm-values.yaml
prometheus:
  prometheusSpec:
    additionalScrapeConfigs:
      - job_name: 'linkerd-controller'
        kubernetes_sd_configs:
        - role: pod
          namespaces:
            names: ['linkerd', 'linkerd-viz']

      - job_name: 'linkerd-proxy'
        kubernetes_sd_configs:
        - role: pod
```

**Query Linkerd metrics in Prometheus:**
```promql
# Request success rate
sum(rate(request_total{direction="inbound"}[1m])) by (dst_deployment)

# P99 latency
histogram_quantile(0.99, sum(rate(response_latency_ms_bucket[1m])) by (le, dst_deployment))
```

### Grafana Dashboards

Linkerd provides pre-built dashboards:

1. **Top Line Metrics** - Cluster-wide success rate, RPS, latency
2. **Deployment** - Per-deployment metrics
3. **Pod** - Per-pod metrics
4. **Namespace** - Namespace-level aggregation
5. **Route** - HTTP route performance

**Import dashboards:**
```bash
# Dashboards available at: https://grafana.com/orgs/linkerd
# Dashboard IDs:
# - 15513: Linkerd Top Line
# - 15514: Linkerd Deployment
# - 15515: Linkerd Namespace
```

## Troubleshooting

### Check mesh status
```bash
linkerd check
linkerd check --proxy
```

### Verify pod injection
```bash
kubectl get pods -n nginx-alb -o jsonpath='{.items[*].spec.containers[*].name}'
# Should show: nginx linkerd-proxy
```

### View proxy logs
```bash
kubectl logs -n nginx-alb deploy/nginx -c linkerd-proxy
```

### Debugging connections
```bash
# Live traffic tap
linkerd viz tap deploy/nginx -n nginx-alb --to deploy/postgres -n postgres

# Service profile
linkerd viz profile --tap deploy/nginx -n nginx-alb
```

## Security

### mTLS Certificate Rotation

Linkerd automatically rotates certificates:
- **Leaf certificates:** 24 hours
- **Issuer certificate:** Configured in identity.issuer.crtExpiry

### Authorization Policies

```yaml
# Restrict access to PostgreSQL
apiVersion: policy.linkerd.io/v1beta1
kind: Server
metadata:
  name: postgres
  namespace: postgres
spec:
  podSelector:
    matchLabels:
      app: postgres
  port: 5432
  proxyProtocol: TCP
---
apiVersion: policy.linkerd.io/v1alpha1
kind: AuthorizationPolicy
metadata:
  name: postgres-policy
  namespace: postgres
spec:
  targetRef:
    name: postgres
    kind: Server
  requiredAuthenticationRefs:
    - name: nginx-clients
      kind: MeshTLSAuthentication
```

## Performance Impact

**Resource overhead per pod:**
- CPU: ~10-20m
- Memory: ~20-50Mi

**Latency overhead:**
- p50: < 1ms
- p99: < 5ms

## References

- [Linkerd Documentation](https://linkerd.io/docs/)
- [Linkerd GitOps Guide](https://linkerd.io/2/tasks/gitops/)
- [SMI Traffic Split Spec](https://github.com/servicemeshinterface/smi-spec/blob/main/apis/traffic-split/v1alpha2/traffic-split.md)
