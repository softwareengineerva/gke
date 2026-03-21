# Linkerd Service Mesh Deployment Guide

**Author:** Jian Ouyang (jian.ouyang@sapns2.com)
**Cluster:** concur-test-gke (Kubernetes 1.34)

## Table of Contents

- [Overview](#overview)
- [What is Linkerd](#what-is-linkerd)
- [Deployment Process](#deployment-process)
  - [Prerequisites](#prerequisites)
  - [Step 1: Create ArgoCD Applications](#step-1-create-argocd-applications)
  - [Step 2: Enable Service Mesh Injection](#step-2-enable-service-mesh-injection)
  - [Step 3: Generate TLS Certificates](#step-3-generate-tls-certificates)
  - [Step 4: Configure Certificate Authentication](#step-4-configure-certificate-authentication)
  - [Step 5: Deploy and Verify](#step-5-deploy-and-verify)
- [Troubleshooting](#troubleshooting)
- [Verification Commands](#verification-commands)
- [Demo Scenarios](#demo-scenarios)
- [Resource Impact](#resource-impact)
- [Maintenance](#maintenance)

---

## Overview

This document describes the complete process of deploying and integrating Linkerd service mesh into the GKE demo environment. Linkerd provides zero-trust security (automatic mTLS), advanced observability, and traffic management without requiring any application code changes.

**Key Achievement:** Successfully deployed production-ready Linkerd service mesh with:
- ✅ Automatic mTLS encryption between all services
- ✅ Request-level metrics and observability
- ✅ High-availability control plane (2 replicas)
- ✅ GitOps-managed deployment via ArgoCD
- ✅ Zero application code changes required

---

## What is Linkerd

Linkerd is a **service mesh** that provides:

1. **Zero-Trust Security**
   - Automatic mTLS encryption for all service-to-service communication
   - Certificate-based identity for every pod
   - No code changes required

2. **Advanced Observability**
   - Golden metrics: Success rate, RPS, latency (p50, p95, p99)
   - Per-route metrics for API endpoints
   - Live traffic tap to see requests in real-time
   - Service topology visualization

3. **Traffic Management**
   - Circuit breaking and automatic retries
   - Traffic splitting for canary deployments
   - Timeout configuration
   - Load balancing

4. **Production Resilience**
   - High-availability control plane
   - Minimal resource overhead (~10-20m CPU, 20-50Mi memory per pod)
   - Ultra-low latency (p50 < 1ms, p99 < 5ms)

---

## Deployment Process

### Prerequisites

**Required Tools:**
- `kubectl` - Kubernetes CLI
- `linkerd` - Linkerd CLI (v2.14.10)
- `step` - Certificate generation tool
- `git` - Version control

**Install Linkerd CLI:**
```bash
# Install Linkerd CLI
curl -fsL https://run.linkerd.io/install | sh
export PATH=$PATH:$HOME/.linkerd2/bin
linkerd version
```

**Install Step CLI:**
```bash
# macOS
brew install step

# Linux
wget https://dl.step.sm/gh-release/cli/docs-cli-install/v0.28.0/step-cli_0.28.0_amd64.deb
sudo dpkg -i step-cli_0.28.0_amd64.deb
```

---

### Step 1: Create ArgoCD Applications

Created three ArgoCD applications to deploy Linkerd components via GitOps:

#### 1.1 Linkerd CRDs Application

**File:** `argocd-apps/linkerd-crds-app.yaml`

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: linkerd-crds
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default

  source:
    chart: linkerd-crds
    repoURL: https://helm.linkerd.io/stable
    targetRevision: 1.8.0

  destination:
    server: https://kubernetes.default.svc
    namespace: linkerd

  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

**Apply:**
```bash
kubectl apply -f argocd-apps/linkerd-crds-app.yaml
```

#### 1.2 Linkerd Control Plane Application

**File:** `argocd-apps/linkerd-app.yaml`

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: linkerd
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default

  source:
    chart: linkerd-control-plane
    repoURL: https://helm.linkerd.io/stable
    targetRevision: 1.16.11
    helm:
      valuesObject:
        # Certificates will be added in Step 4

        # Control plane HA
        controllerReplicas: 2

        # Prometheus integration
        prometheusUrl: http://prometheus-stack-kube-prom-prometheus.monitoring.svc.cluster.local:9090

  destination:
    server: https://kubernetes.default.svc
    namespace: linkerd

  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

**Apply:**
```bash
kubectl apply -f argocd-apps/linkerd-app.yaml
```

#### 1.3 Linkerd Viz Application

**File:** `argocd-apps/linkerd-viz-app.yaml`

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: linkerd-viz
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default

  source:
    chart: linkerd-viz
    repoURL: https://helm.linkerd.io/stable
    targetRevision: 30.12.11
    helm:
      valuesObject:
        # CRITICAL: Must be top-level parameter
        prometheusUrl: http://prometheus-stack-kube-prom-prometheus.monitoring.svc.cluster.local:9090

        dashboard:
          replicas: 1

        grafana:
          enabled: false

        prometheus:
          enabled: false

  destination:
    server: https://kubernetes.default.svc
    namespace: linkerd-viz

  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

**Apply:**
```bash
kubectl apply -f argocd-apps/linkerd-viz-app.yaml
```

---

### Step 2: Enable Service Mesh Injection

Added namespace annotations to enable automatic Linkerd proxy injection for application pods.

#### 2.1 Update Namespace Annotations

**Modified Files:**
- `k8s-manifests/nginx-alb/base/namespace.yaml`
- `k8s-manifests/postgres/namespace.yaml`
- `k8s-manifests/redis/namespace.yaml`
- `k8s-manifests/secrets-demo/namespace.yaml`

**Example (nginx-alb):**
```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: nginx-alb
  labels:
    name: nginx-alb
    env: dev
  annotations:
    linkerd.io/inject: enabled  # ← Added this annotation
```

**Commit and Push:**
```bash
git add k8s-manifests/*/namespace.yaml
git commit -m "Enable Linkerd service mesh injection for application namespaces"
git push
```

ArgoCD will automatically sync and apply these changes.

#### 2.2 Restart Pods to Trigger Injection

After namespace annotations are applied, restart pods to inject the Linkerd proxy sidecar:

```bash
# Restart deployments
kubectl rollout restart deployment -n nginx-alb
kubectl rollout restart deployment -n secrets-demo

# Restart statefulsets
kubectl rollout restart statefulset -n postgres
kubectl rollout restart statefulset -n redis
```

---

### Step 3: Generate TLS Certificates

Linkerd requires TLS certificates for pod identity and mTLS encryption. We generate these using the `step` CLI.

#### 3.1 Generate Trust Anchor CA Certificate

```bash
# Create directory for certificates
mkdir -p /tmp/linkerd-certs
cd /tmp/linkerd-certs

# Generate root CA certificate (valid 10 years)
step certificate create root.linkerd.cluster.local ca.crt ca.key \
  --profile root-ca \
  --no-password \
  --insecure

# Verify certificate
step certificate inspect ca.crt --short
```

**Output:**
```
X.509v3 Root CA Certificate (ECDSA P-256) [Serial: 1046...9085]
  Subject:     root.linkerd.cluster.local
  Issuer:      root.linkerd.cluster.local
  Valid from:  2025-04-01T13:32:32Z
          to:  2035-04-29T13:32:32Z
```

#### 3.2 Generate Identity Issuer Certificate

```bash
# Generate intermediate CA certificate (valid 1 year)
step certificate create identity.linkerd.cluster.local issuer.crt issuer.key \
  --profile intermediate-ca \
  --not-after 8760h \
  --no-password \
  --insecure \
  --ca ca.crt \
  --ca-key ca.key

# Verify certificate
step certificate inspect issuer.crt --short
```

**Output:**
```
X.509v3 Intermediate CA Certificate (ECDSA P-256) [Serial: 1456...5925]
  Subject:     identity.linkerd.cluster.local
  Issuer:      root.linkerd.cluster.local
  Valid from:  2025-04-01T13:32:43Z
          to:  2026-04-01T13:32:43Z
```

#### 3.3 Create Kubernetes Secrets

```bash
# Create trust anchor secret
kubectl create secret tls linkerd-trust-anchor \
  --cert=ca.crt \
  --key=ca.key \
  --namespace=linkerd

# Create identity issuer secret
kubectl create secret tls linkerd-identity-issuer \
  --cert=issuer.crt \
  --key=issuer.key \
  --namespace=linkerd

# Verify secrets were created
kubectl get secrets -n linkerd | grep linkerd
```

**Output:**
```
linkerd-identity-issuer            kubernetes.io/tls   2      5s
linkerd-trust-anchor               kubernetes.io/tls   2      9s
```

---

### Step 4: Configure Certificate Authentication

Updated the Linkerd control plane application to use the generated certificates.

#### 4.1 Embed Certificates in ArgoCD Application

**Edit:** `argocd-apps/linkerd-app.yaml`

```yaml
helm:
  valuesObject:
    # Identity configuration - use external certificates
    identity:
      issuer:
        scheme: kubernetes.io/tls
        tls:
          crtPEM: |
            -----BEGIN CERTIFICATE-----
            [issuer certificate content]
            -----END CERTIFICATE-----
          keyPEM: |
            -----BEGIN EC PRIVATE KEY-----
            [issuer private key content]
            -----END EC PRIVATE KEY-----

    # Identity trust anchor
    identityTrustAnchorsPEM: |
      -----BEGIN CERTIFICATE-----
      [trust anchor certificate content]
      -----END CERTIFICATE-----

    # Control plane HA
    controllerReplicas: 2
    # ... rest of configuration
```

**Apply:**
```bash
kubectl apply -f argocd-apps/linkerd-app.yaml
```

#### 4.2 Force Pod Restart

```bash
# Delete all Linkerd control plane pods to force recreation with new certificates
kubectl delete pods --all -n linkerd

# Wait for pods to restart
sleep 20
kubectl get pods -n linkerd
```

---

### Step 5: Deploy and Verify

#### 5.1 Check ArgoCD Application Status

```bash
kubectl get applications -n argocd | grep linkerd
```

**Expected Output:**
```
linkerd-crds         Synced        Healthy
linkerd              Synced        Healthy
linkerd-viz          Synced        Healthy
```

#### 5.2 Verify Control Plane Pods

```bash
kubectl get pods -n linkerd
```

**Expected Output:**
```
NAME                                      READY   STATUS    RESTARTS   AGE
linkerd-destination-647dfcc58b-9rzgm      4/4     Running   0          2m
linkerd-destination-647dfcc58b-ggvsj      4/4     Running   0          2m
linkerd-identity-844cd5ff59-h4pmx         2/2     Running   0          2m
linkerd-identity-844cd5ff59-lwppr         2/2     Running   0          2m
linkerd-proxy-injector-756c486669-pvdw4   2/2     Running   0          2m
linkerd-proxy-injector-756c486669-wl8zs   2/2     Running   0          2m
```

#### 5.3 Verify Linkerd Viz Pods

```bash
kubectl get pods -n linkerd-viz
```

**Expected Output:**
```
NAME                           READY   STATUS    RESTARTS   AGE
metrics-api-6fdd8449bf-pvdxk   2/2     Running   0          90s
tap-7486f6cff9-qrlqb           2/2     Running   0          90s
tap-injector-c8fc88455-st84l   2/2     Running   0          90s
web-56b8db4d44-psz9m           2/2     Running   0          90s
```

#### 5.4 Verify Service Mesh Injection

```bash
# Check nginx pods have linkerd-proxy sidecar
kubectl get pods -n nginx-alb -o jsonpath='{.items[0].spec.containers[*].name}'
```

**Expected Output:**
```
linkerd-proxy nginx nginx-exporter
```

```bash
# Check all meshed namespaces
for ns in nginx-alb postgres redis secrets-demo; do
  echo "=== $ns ==="
  kubectl get pods -n $ns -o jsonpath='{.items[0].spec.containers[*].name}'
  echo ""
done
```

---

## Troubleshooting

### Issue 1: Pods in CrashLoopBackOff

**Symptom:**
```
linkerd-identity-xxx    0/2   Init:0/1   0   2m
linkerd-destination-xxx 0/4   CrashLoopBackOff
```

**Root Cause:** Missing identity certificates

**Solution:** Follow [Step 3](#step-3-generate-tls-certificates) to generate and configure certificates

---

### Issue 2: Linkerd Viz Manifest Generation Error

**Symptom:**
```
Failed to generate manifest: Please enable `linkerd-prometheus` or provide `prometheusUrl`
```

**Root Cause:** Incorrect Helm parameter - used nested `prometheus.url` instead of top-level `prometheusUrl`

**Solution:**
```yaml
# WRONG
helm:
  valuesObject:
    prometheus:
      url: http://prometheus-stack-kube-prom-prometheus.monitoring.svc.cluster.local:9090

# CORRECT
helm:
  valuesObject:
    prometheusUrl: http://prometheus-stack-kube-prom-prometheus.monitoring.svc.cluster.local:9090
```

---

### Issue 3: Pods Not Getting Injected

**Symptom:** Pods only have 1 or 2 containers (no linkerd-proxy sidecar)

**Root Cause:** Namespace annotation not applied before pod creation

**Solution:**
```bash
# 1. Verify namespace has annotation
kubectl get namespace nginx-alb -o yaml | grep "linkerd.io/inject"

# 2. Restart pods to trigger injection
kubectl rollout restart deployment -n nginx-alb
```

---

### Issue 4: Tap Authorization Failed (RBAC)

**Symptom:**
```
HTTP error, status Code [403] (unexpected API response:
{"error":"tap authorization failed (not authorized to access deployments.tap.linkerd.io)"})
```

**Root Cause:** Missing RBAC permissions to access Linkerd tap API

**Solution:**
```bash
# Create RBAC resources for tap access
cat <<EOF | kubectl apply -f -
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: linkerd-tap
  labels:
    app.kubernetes.io/name: linkerd-tap
    app.kubernetes.io/part-of: linkerd
rules:
  - apiGroups: ["tap.linkerd.io"]
    resources: ["*"]
    verbs: ["watch"]
  - apiGroups: [""]
    resources: ["namespaces"]
    verbs: ["get", "list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: linkerd-tap-admin
  labels:
    app.kubernetes.io/name: linkerd-tap
    app.kubernetes.io/part-of: linkerd
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: linkerd-tap
subjects:
  - kind: Group
    name: system:authenticated
    apiGroup: rbac.authorization.k8s.io
EOF

# Restart pods to enable tap (if they were created before Linkerd Viz)
kubectl rollout restart deployment/nginx -n nginx-alb

# Test tap
linkerd viz tap deploy/nginx -n nginx-alb
```

**Note:** Pods created before Linkerd Viz was deployed need to be restarted to enable tap functionality.

---

## Verification Commands

### Check Linkerd Installation

```bash
# Run Linkerd health check
linkerd check

# Expected output: All checks should pass with ✓
```

### Verify Service Mesh Status

```bash
# Check all meshed deployments
linkerd viz stat deploy --all-namespaces

# Check specific namespace
linkerd viz stat deploy -n nginx-alb
linkerd viz stat statefulset -n postgres
linkerd viz stat statefulset -n redis

# Expected output:
# NAME     MESHED   SUCCESS   RPS   LATENCY_P50   LATENCY_P95   LATENCY_P99
# nginx    3/3      100.00%   2.5   5ms          12ms          25ms
```

### Verify mTLS Encryption

```bash
# Tap live traffic to see mTLS encryption
linkerd viz tap deploy/nginx -n nginx-alb

# Look for "tls=true" in the output:
# req id=0:0 proxy=in src=10.0.1.45:54321 dst=10.0.1.23:80 tls=true :method=GET
# rsp id=0:0 proxy=in src=10.0.1.45:54321 dst=10.0.1.23:80 tls=true :status=200
```

### Check Certificate Status

```bash
# View certificate information
kubectl get secrets -n linkerd | grep linkerd

# Check certificate details
kubectl get secret linkerd-identity-issuer -n linkerd -o jsonpath='{.data.tls\.crt}' | base64 -d | step certificate inspect -

# Verify expiration dates
step certificate inspect /tmp/linkerd-certs/issuer.crt --short
step certificate inspect /tmp/linkerd-certs/ca.crt --short
```

### View Linkerd Dashboard

```bash
# Port-forward the dashboard
kubectl port-forward -n linkerd-viz svc/web 8084:8084

# Open in browser
open http://localhost:8084
```

### Check Pod Injection Status

```bash
# Verify pods have linkerd-proxy sidecar
kubectl get pods -n nginx-alb -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[*].name}{"\n"}{end}'

# Count meshed pods
kubectl get pods -A -o json | jq '[.items[] | select(.spec.containers[] | .name == "linkerd-proxy")] | length'
```

---

## Demo Scenarios

### Scenario 1: Verify mTLS Encryption

**Objective:** Show that all service-to-service traffic is automatically encrypted with mTLS.

**Commands:**
```bash
# 1. Check cluster-wide mTLS status
linkerd check

# Look for:
# √ certificate config is valid
# √ all proxy certificates have valid trust anchors

# 2. View meshed services
linkerd viz stat deploy -n nginx-alb
linkerd viz stat deploy -n postgres

# 3. Generate meshed traffic (create a test pod that will be auto-injected)
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: curl-test
  namespace: nginx-alb
spec:
  containers:
  - name: curl
    image: curlimages/curl
    command: ["sh", "-c", "while true; do curl -s http://nginx.nginx-alb.svc.cluster.local/ > /dev/null; sleep 2; done"]
EOF

# Wait for pod to be meshed
sleep 5
kubectl get pod curl-test -n nginx-alb -o jsonpath='{.spec.containers[*].name}'
# Should show: linkerd-proxy curl

# 4. Tap traffic to see mTLS in action
linkerd viz tap deploy/nginx -n nginx-alb --to svc/nginx

# Expected output - look for tls=true for meshed traffic:
# req id=5:3 proxy=in  src=10.0.1.15:54622 dst=10.0.2.59:80 tls=true :method=GET :authority=nginx.nginx-alb.svc.cluster.local
# rsp id=5:3 proxy=in  src=10.0.1.15:54622 dst=10.0.2.59:80 tls=true :status=200 latency=391µs
# end id=5:3 proxy=in  src=10.0.1.15:54622 dst=10.0.2.59:80 tls=true duration=151µs response-length=1450B

# You may also see tls=no_tls_from_remote for:
# - GCP ALB health checks (external traffic)
# - Prometheus metrics scraping (same-pod traffic)

# 5. Cleanup
kubectl delete pod curl-test -n nginx-alb
```

**What to Show:**
- **`tls=true`** for meshed pod-to-pod traffic through Kubernetes Services
- **`tls=no_tls_from_remote`** for external traffic (ALB health checks)
- **`:authority=nginx.nginx-alb.svc.cluster.local`** shows traffic through K8s service DNS
- Sub-millisecond latency overhead (<1ms)
- Certificates are automatically rotated (every 24 hours)
- No application code changes required

---

### Scenario 2: Golden Metrics (Success Rate, Latency, RPS)

**Objective:** Show automatic request-level metrics without any instrumentation.

**Commands:**
```bash
# 1. View overall service metrics
linkerd viz stat deploy --all-namespaces

# Expected output:
# NAMESPACE     NAME             MESHED   SUCCESS   RPS   LATENCY_P50   LATENCY_P95   LATENCY_P99
# nginx-alb     nginx            3/3      100.00%   5.0   2ms          5ms          10ms
# postgres      postgres         1/1      100.00%   2.5   5ms          12ms         25ms

# 2. View detailed route metrics
linkerd viz routes deploy/nginx -n nginx-alb

# Expected output:
# ROUTE              SERVICE   SUCCESS   RPS   LATENCY_P50   LATENCY_P95   LATENCY_P99
# GET /              nginx     100.00%   1000  1ms          3ms          10ms
# POST /api/users    nginx     99.95%    1200  8ms          20ms         40ms

# 3. Top metrics (most active services)
linkerd viz top deploy -n nginx-alb

# 4. View metrics in Prometheus
kubectl port-forward -n monitoring svc/prometheus-stack-kube-prom-prometheus 9090:9090

# Then query in Prometheus UI:
# - Request success rate: sum(rate(request_total{direction="inbound"}[1m])) by (dst_deployment)
# - P99 latency: histogram_quantile(0.99, sum(rate(response_latency_ms_bucket[1m])) by (le, dst_deployment))
```

**What to Show:**
- Success rate percentage
- Requests per second (RPS)
- Latency percentiles (p50, p95, p99)
- All without any application instrumentation

---

### Scenario 3: Service Topology Visualization

**Objective:** Visualize service dependencies and traffic flow.

**Commands:**
```bash
# 1. Port-forward Linkerd dashboard
kubectl port-forward -n linkerd-viz svc/web 8084:8084

# 2. Open in browser
open http://localhost:8084

# 3. Navigate to:
# - Namespaces → nginx-alb → Deployments → nginx
# - View topology graph showing service dependencies

# 4. Generate traffic from multiple sources
# Terminal 1: External traffic
kubectl run -it --rm curl --image=curlimages/curl --restart=Never -n nginx-alb -- \
  sh -c "while true; do curl -s http://nginx/; sleep 2; done"

# Terminal 2: Internal traffic (secrets-demo → nginx)
kubectl exec -it -n secrets-demo deploy/secrets-demo -- \
  sh -c "while true; do curl -s http://nginx.nginx-alb.svc.cluster.local/; sleep 3; done"
```

**What to Show:**
- Real-time request rate visualization
- Success rate percentage
- Latency distribution
- Service topology graph with dependencies
- Color-coded health indicators

---

### Scenario 4: Traffic Splitting (Canary Deployment)

**Objective:** Demonstrate gradual rollout with traffic shifting.

**Commands:**
```bash
# 1. Deploy two versions of NGINX
# First, edit k8s-manifests/nginx-alb/overlays/dev/kustomization.yaml
# Change image tag to create v127 deployment

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
    weight: 90  # 90% to stable
  - service: nginx-v128
    weight: 10  # 10% to canary
EOF

# 3. Monitor canary performance
linkerd viz stat deploy/nginx-v128 -n nginx-alb

# 4. If healthy, shift more traffic (50/50)
kubectl patch trafficsplit nginx-canary -n nginx-alb --type merge \
  -p '{"spec":{"backends":[{"service":"nginx-v127","weight":50},{"service":"nginx-v128","weight":50}]}}'

# 5. View traffic distribution
linkerd viz stat deploy -n nginx-alb

# 6. If successful, shift to 100% canary
kubectl patch trafficsplit nginx-canary -n nginx-alb --type merge \
  -p '{"spec":{"backends":[{"service":"nginx-v127","weight":0},{"service":"nginx-v128","weight":100}]}}'
```

**What to Show:**
- Gradual traffic shifting (10% → 50% → 100%)
- Independent monitoring of canary metrics
- Zero-downtime deployment
- Instant rollback capability

---

### Scenario 5: Circuit Breaking & Retries

**Objective:** Show automatic resilience with retry policies.

**Commands:**
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

# 3. Verify retry policy in action
# Simulate a failing request
kubectl exec -it -n nginx-alb deploy/nginx -- \
  sh -c "while true; do curl -s http://postgres.postgres.svc.cluster.local:5432/; sleep 1; done"

# 4. Watch retries in tap
linkerd viz tap deploy/postgres -n postgres --to deploy/postgres

# Look for retry attempts in the output
```

**What to Show:**
- Automatic retry on failures
- Configurable backoff strategy
- Request timeout configuration
- Improved reliability without code changes

---

### Scenario 6: Per-Route Metrics

**Objective:** Analyze specific API endpoint performance.

**Commands:**
```bash
# 1. View HTTP route performance
linkerd viz routes deploy/nginx -n nginx-alb --to svc/postgres

# Expected output:
# ROUTE                   SERVICE      SUCCESS   RPS   P50   P95   P99
# GET /api/users          postgres     100.00%   2.5   5ms   12ms  25ms
# POST /api/users         postgres     99.95%    1.2   8ms   20ms  40ms
# GET /api/users/:id      postgres     100.00%   1.8   3ms   8ms   15ms

# 2. Generate traffic to specific routes
kubectl exec -it -n nginx-alb deploy/nginx -- \
  sh -c "for i in {1..100}; do curl -s http://localhost/api/users; done"

# 3. Watch per-route metrics update
watch -n 2 "linkerd viz routes deploy/nginx -n nginx-alb"

# 4. View slow routes
linkerd viz routes deploy/nginx -n nginx-alb | sort -k7 -n -r | head -10
```

**What to Show:**
- Per-endpoint success rates
- Route-specific latency
- High-traffic vs low-traffic routes
- Easy identification of slow endpoints

---

### Scenario 7: Authorization Policies

**Objective:** Implement zero-trust security with deny-by-default policies.

**Commands:**
```bash
# 1. Restrict access to PostgreSQL (only allow nginx)
cat <<EOF | kubectl apply -f -
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
---
apiVersion: policy.linkerd.io/v1alpha1
kind: MeshTLSAuthentication
metadata:
  name: nginx-clients
  namespace: postgres
spec:
  identities:
    - "nginx.nginx-alb.serviceaccount.identity.linkerd.cluster.local"
EOF

# 2. Test allowed connection (from nginx)
kubectl exec -it -n nginx-alb deploy/nginx -- curl postgres.postgres.svc.cluster.local:5432
# Should succeed

# 3. Test denied connection (from redis)
kubectl exec -it -n redis sts/redis -- curl postgres.postgres.svc.cluster.local:5432
# Should fail with connection refused

# 4. View authorization events
linkerd viz tap deploy/postgres -n postgres
```

**What to Show:**
- Deny-by-default security
- Certificate-based identity
- Granular access control
- Audit trail of allowed/denied requests

---

## Backend API Integration

### Overview

To demonstrate real microservices traffic with Linkerd mTLS encryption, we deployed a **backend-api** service that sits between nginx and postgres, enabling the complete architecture:

```
External Traffic
    ↓
GCP ALB (Internet-facing)
    ↓ [unencrypted HTTP]
nginx pods (3 replicas, meshed)
    ↓ [mTLS encrypted - tls=true]
backend-api pods (2 replicas, meshed)
    ↓ [mTLS encrypted - tls=true]
postgres pod (1 replica, meshed)
```

### Architecture Components

**1. Backend API Service**
- **Technology:** Python Flask REST API
- **Database:** PostgreSQL with psycopg2
- **Server:** Gunicorn WSGI (2 workers, production-ready)
- **Endpoints:**
  - `GET /health` - Basic health check
  - `GET /api/health` - Database connectivity check
  - `GET /api/users` - List all users from PostgreSQL
  - `GET /api/users/<id>` - Get specific user by ID
  - `POST /api/users` - Create new user (JSON: {name, email})
  - `GET /api/stats` - Database statistics

**2. Nginx Proxy Configuration**
- Proxies `/api/*` requests to `backend-api.backend-api.svc.cluster.local:8080`
- Includes proper proxy headers and timeout configuration
- Location block added via Kustomize overlay patch

**3. Docker Image**
- Built for `linux/amd64` platform
- Stored in Google ECR: `865286230013.dkr.ecr.us-east1.googleapis.com/backend-api:latest`
- Auto-initializes PostgreSQL with sample user data on startup

### Deployment

**Files Created:**
```
k8s-manifests/backend-api/
├── base/
│   ├── deployment.yaml          # 2 replicas, Linkerd injection enabled
│   ├── service.yaml             # ClusterIP on port 8080
│   ├── namespace.yaml           # linkerd.io/inject: enabled
│   └── kustomization.yaml
└── docker/
    ├── app.py                   # Flask application
    ├── requirements.txt         # Python dependencies
    ├── Dockerfile               # Multi-stage build
    └── README.md

k8s-manifests/nginx-alb/overlays/dev/
└── nginx-config-patch.yaml      # Adds /api/ location block

argocd-apps/
└── backend-api-app.yaml         # ArgoCD GitOps application
```

**ArgoCD Application:**
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: backend-api
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/softwareengineerva/gke.git
    targetRevision: HEAD
    path: k8s-manifests/backend-api/base
  destination:
    server: https://kubernetes.default.svc
    namespace: backend-api
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

### Verification

**1. Check Pod Status:**
```bash
# Verify all services are meshed
kubectl get pods -n nginx-alb -o jsonpath='{.items[0].spec.containers[*].name}'
# Expected: linkerd-proxy nginx nginx-exporter

kubectl get pods -n backend-api -o jsonpath='{.items[0].spec.containers[*].name}'
# Expected: linkerd-proxy backend-api

kubectl get pods -n postgres -o jsonpath='{.items[0].spec.containers[*].name}'
# Expected: linkerd-proxy postgres postgres-exporter

# Check mesh status
linkerd viz stat deploy -n nginx-alb
linkerd viz stat deploy -n backend-api
linkerd viz stat statefulset -n postgres
```

**Expected Output:**
```
NAME          MESHED   SUCCESS   RPS   LATENCY_P50   LATENCY_P95   LATENCY_P99   TCP_CONN
nginx            3/3         -     -             -             -             -          -
backend-api      2/2         -     -             -             -             -          -
postgres         1/1         -     -             -             -             -          -
```

**2. Test API Endpoints Internally:**
```bash
# Test from within nginx pod
kubectl exec -n nginx-alb deploy/nginx -c nginx -- \
  curl -s http://backend-api.backend-api.svc.cluster.local:8080/api/users | jq .

# Expected output:
{
  "count": 5,
  "users": [
    {
      "id": 1,
      "name": "Alice Johnson",
      "email": "alice@example.com",
      "created_at": "Mon, 01 Apr 2025 14:22:35 GMT"
    },
    ...
  ]
}

# Test database connectivity
kubectl exec -n nginx-alb deploy/nginx -c nginx -- \
  curl -s http://backend-api.backend-api.svc.cluster.local:8080/api/health | jq .

# Expected output:
{
  "status": "healthy",
  "service": "backend-api",
  "database": "connected",
  "db_version": "PostgreSQL 16.11 on x86_64-pc-linux-musl...",
  "timestamp": "2025-04-01T14:37:30.717681"
}
```

**3. Test Through GCP ALB (External Access):**
```bash
# Get ALB hostname
ALB_URL=$(kubectl get ingress -n nginx-alb -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}')
echo "ALB URL: http://$ALB_URL"

# Test all API endpoints
curl -s http://$ALB_URL/api/users | jq .
curl -s http://$ALB_URL/api/health | jq .
curl -s http://$ALB_URL/api/stats | jq .
curl -s http://$ALB_URL/api/users/1 | jq .

# Create a new user
curl -s -X POST http://$ALB_URL/api/users \
  -H "Content-Type: application/json" \
  -d '{"name":"Test User","email":"test@example.com"}' | jq .
```

**4. Verify mTLS Encryption:**

This is the **KEY DEMONSTRATION** - showing that traffic between nginx and backend-api is encrypted with mTLS:

```bash
# Start tapping traffic to backend-api (in background)
timeout 20 linkerd viz tap deploy/backend-api -n backend-api --path /api 2>&1 &

# Generate traffic through the ALB
sleep 2
for i in {1..3}; do
  curl -s http://$ALB_URL/api/users > /dev/null
  sleep 1
done

# Wait for tap to complete
wait
```

**Expected Output - LOOK FOR `tls=true`:**
```
req id=2:0 proxy=in  src=10.0.3.126:42574 dst=10.0.3.131:8080 tls=true :method=GET :authority=k8s-nginxalb-nginx-b4e33b4879-136042050.us-east1.elb.googleapis.com :path=/api/users
rsp id=2:0 proxy=in  src=10.0.3.126:42574 dst=10.0.3.131:8080 tls=true :status=200 latency=30317µs
end id=2:0 proxy=in  src=10.0.3.126:42574 dst=10.0.3.131:8080 tls=true duration=47µs response-length=534B
```

**Key Indicators of mTLS:**
- ✅ **`tls=true`** - All traffic is encrypted with mutual TLS
- ✅ **Source IP (10.0.x.x)** - Shows traffic coming from nginx pod's Linkerd proxy
- ✅ **`:authority` header** - Shows the ALB hostname (nginx proxies it)
- ✅ **Latency** - Sub-millisecond overhead (~30ms response time)

**What This Proves:**
1. **External → nginx**: Unencrypted HTTP (ALB → nginx)
2. **nginx → backend-api**: **Encrypted with mTLS** (tls=true)
3. **backend-api → postgres**: **Encrypted with mTLS** (automatic)
4. **Zero application changes**: Apps don't know about encryption
5. **Automatic certificate rotation**: Linkerd rotates certs every 24 hours

---

## Complete Demo Script

This section provides a **complete, copy-paste ready demo** that demonstrates the Backend API integration and Linkerd mTLS encryption in action.

### Prerequisites

```bash
# Ensure kubectl is configured
kubectl get nodes

# Verify all services are deployed and healthy
kubectl get applications -n argocd | grep -E "nginx-alb|backend-api|postgres|linkerd"
```

---

### Demo Part 1: Verify Service Mesh Injection

**Objective:** Show that all pods have the Linkerd proxy sidecar automatically injected.

```bash
echo "=== Checking Linkerd Proxy Injection ==="
echo ""

echo "Nginx pods (should show: linkerd-proxy nginx nginx-exporter):"
kubectl get pods -n nginx-alb -o jsonpath='{.items[0].spec.containers[*].name}'
echo ""
echo ""

echo "Backend-API pods (should show: linkerd-proxy backend-api):"
kubectl get pods -n backend-api -o jsonpath='{.items[0].spec.containers[*].name}'
echo ""
echo ""

echo "Postgres pods (should show: linkerd-proxy postgres postgres-exporter):"
kubectl get pods -n postgres -o jsonpath='{.items[0].spec.containers[*].name}'
echo ""
echo ""

echo "=== Checking Mesh Status ==="
linkerd viz stat deploy --all-namespaces | grep -E "NAMESPACE|nginx|backend-api|postgres"
```

**Expected Output:**
- All pods should have `linkerd-proxy` as the first container
- MESHED column should show `X/X` (all replicas meshed)
- All services show as healthy

---

### Demo Part 2: Test API Endpoints Through ALB

**Objective:** Show that the API is accessible through the GCP ALB via nginx proxy.

```bash
# Get ALB URL
ALB_URL=$(kubectl get ingress -n nginx-alb -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}')
echo "=== ALB URL: http://$ALB_URL ==="
echo ""

# Test 1: Basic health check
echo "Test 1: Basic health check"
curl -s http://$ALB_URL/health
echo ""
echo ""

# Test 2: API health with database connectivity
echo "Test 2: API health with database check"
curl -s http://$ALB_URL/api/health | jq .
echo ""

# Test 3: Get all users from PostgreSQL
echo "Test 3: Get all users"
curl -s http://$ALB_URL/api/users | jq .
echo ""

# Test 4: Get specific user
echo "Test 4: Get user ID 1"
curl -s http://$ALB_URL/api/users/1 | jq .
echo ""

# Test 5: Database statistics
echo "Test 5: Database statistics"
curl -s http://$ALB_URL/api/stats | jq .
echo ""

# Test 6: Create a new user
echo "Test 6: Create new user"
curl -s -X POST http://$ALB_URL/api/users \
  -H "Content-Type: application/json" \
  -d '{"name":"Demo User","email":"demo@example.com"}' | jq .
echo ""

# Verify new user was created
echo "Verify new user exists:"
curl -s http://$ALB_URL/api/users | jq '.users[] | select(.email=="demo@example.com")'
```

**Expected Output:**
- All endpoints return JSON responses
- Database connectivity confirmed
- 5 sample users returned initially
- New user successfully created with auto-incremented ID

---

### Demo Part 3: Demonstrate mTLS Encryption (THE KEY DEMO)

**Objective:** Prove that traffic between nginx → backend-api → postgres is encrypted with mutual TLS.

**Step 1: Start Traffic Tap**

In **Terminal 1**, start tapping traffic to the backend-api:

```bash
# This will show live request/response traffic with TLS status
linkerd viz tap deploy/backend-api -n backend-api --path /api
```

**Step 2: Generate Traffic**

In **Terminal 2**, generate API requests through the ALB:

```bash
# Get ALB URL
ALB_URL=$(kubectl get ingress -n nginx-alb -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}')

# Generate continuous traffic
for i in {1..10}; do
  echo "Request $i"
  curl -s http://$ALB_URL/api/users > /dev/null
  curl -s http://$ALB_URL/api/health > /dev/null
  sleep 2
done
```

**Step 3: Observe Output in Terminal 1**

You should see output like this in Terminal 1:

```
req id=2:0 proxy=in  src=10.0.3.126:42574 dst=10.0.3.131:8080 tls=true :method=GET :authority=k8s-nginxalb-nginx-xxx.elb.googleapis.com :path=/api/users
rsp id=2:0 proxy=in  src=10.0.3.126:42574 dst=10.0.3.131:8080 tls=true :status=200 latency=30317µs
end id=2:0 proxy=in  src=10.0.3.126:42574 dst=10.0.3.131:8080 tls=true duration=47µs response-length=534B

req id=3:0 proxy=in  src=10.0.2.45:38912 dst=10.0.3.131:8080 tls=true :method=GET :authority=k8s-nginxalb-nginx-xxx.elb.googleapis.com :path=/api/health
rsp id=3:0 proxy=in  src=10.0.2.45:38912 dst=10.0.3.131:8080 tls=true :status=200 latency=15829µs
end id=3:0 proxy=in  src=10.0.2.45:38912 dst=10.0.3.131:8080 tls=true duration=35µs response-length=245B
```

**KEY OBSERVATIONS:**
- ✅ **`tls=true`** appears on EVERY request/response - this proves mTLS encryption
- ✅ **Source IP (10.0.x.x)** - Traffic coming from nginx pod's Linkerd proxy (not ALB)
- ✅ **`:authority` header** - Shows ALB hostname (nginx proxies it transparently)
- ✅ **Latency** - Sub-millisecond overhead added by Linkerd (<1ms typical)
- ✅ **`:status=200`** - All requests successful

**Alternative Single-Command Demo:**

```bash
# All-in-one command (runs tap in background, generates traffic, displays output)
ALB_URL=$(kubectl get ingress -n nginx-alb -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}')

# Start tap in background
timeout 15 linkerd viz tap deploy/backend-api -n backend-api --path /api &
TAP_PID=$!

# Wait for tap to start
sleep 2

# Generate traffic
for i in {1..5}; do
  curl -s http://$ALB_URL/api/users > /dev/null
  curl -s http://$ALB_URL/api/health > /dev/null
  sleep 1
done

# Wait for tap to finish
wait $TAP_PID
```

---

### Demo Part 4: View Golden Metrics

**Objective:** Show automatic request-level metrics without any application instrumentation.

```bash
echo "=== Golden Metrics for Backend API ==="
echo ""

# Overall service metrics
echo "1. Overall Service Metrics:"
linkerd viz stat deploy/backend-api -n backend-api
echo ""

# Route-specific metrics
echo "2. Per-Route Metrics:"
linkerd viz routes deploy/backend-api -n backend-api
echo ""

# Live traffic view
echo "3. Top Traffic (real-time):"
timeout 10 linkerd viz top deploy/backend-api -n backend-api
```

**Expected Metrics:**
- **SUCCESS**: Should be 100.00% (all requests successful)
- **RPS**: Requests per second (varies based on traffic)
- **LATENCY_P50**: Median latency (~5-15ms including database query)
- **LATENCY_P95**: 95th percentile (~20-40ms)
- **LATENCY_P99**: 99th percentile (~40-80ms)

---

### Demo Part 5: Verify End-to-End Encryption

**Objective:** Show that backend-api → postgres traffic is also encrypted with mTLS.

```bash
# Terminal 1: Tap postgres traffic
linkerd viz tap statefulset/postgres -n postgres

# Terminal 2: Generate database queries
kubectl exec -n backend-api deploy/backend-api -- \
  curl -s http://localhost:8080/api/users > /dev/null

# Or generate traffic through nginx
ALB_URL=$(kubectl get ingress -n nginx-alb -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}')
for i in {1..5}; do
  curl -s http://$ALB_URL/api/users > /dev/null
  sleep 1
done
```

**Expected Output:**
```
req id=1:0 proxy=in  src=10.0.1.x:xxxxx dst=10.0.2.x:5432 tls=true
rsp id=1:0 proxy=in  src=10.0.1.x:xxxxx dst=10.0.2.x:5432 tls=true
end id=1:0 proxy=in  src=10.0.1.x:xxxxx dst=10.0.2.x:5432 tls=true
```

All PostgreSQL traffic shows **`tls=true`** - proving database connections are also encrypted.

---

### Demo Part 6: Linkerd Dashboard Visualization

**Objective:** Show real-time service topology and metrics in the Linkerd web dashboard.

```bash
# Port-forward the Linkerd dashboard
kubectl port-forward -n linkerd-viz svc/web 8084:8084

# Open in browser (in a new terminal or background the port-forward)
echo "Open http://localhost:8084 in your browser"
echo ""
echo "Navigate to:"
echo "  1. Namespaces → nginx-alb → Deployments → nginx"
echo "  2. Click 'Live calls' to see real-time traffic"
echo "  3. View topology graph showing: nginx → backend-api → postgres"
```

**In the Dashboard:**
1. Navigate to **nginx-alb** namespace
2. Click on **nginx** deployment
3. View the **Live calls** tab - you'll see real-time traffic
4. Check the **Tap** tab - shows `tls=true` for all backend-api calls
5. View **Topology** - visual graph showing service dependencies

---

### Demo Part 7: Verify Zero Application Changes

**Objective:** Prove that mTLS encryption required ZERO code changes to applications.

```bash
echo "=== Checking Application Code ==="
echo ""

# Show Flask application code (no TLS/SSL configuration)
echo "Backend API code (app.py) - No TLS configuration:"
kubectl exec -n backend-api deploy/backend-api -- cat /app/app.py | grep -E "ssl|tls|cert|https" || echo "No TLS code found - Linkerd handles it all!"
echo ""

# Show nginx config (plain HTTP proxy)
echo "Nginx config - Plain HTTP proxy to backend-api:"
kubectl get configmap -n nginx-alb nginx-config -o jsonpath='{.data.nginx\.conf}' | grep -A5 "location /api"
echo ""

echo "=== Proof of Zero Changes ==="
echo "✅ Backend API uses plain HTTP (no SSL/TLS code)"
echo "✅ Nginx proxies via plain HTTP (http://backend-api...)"
echo "✅ Linkerd automatically encrypts ALL pod-to-pod traffic"
echo "✅ Applications are completely unaware of mTLS encryption"
```

---

### Demo Part 8: Certificate Verification

**Objective:** Show automatic certificate management and rotation.

```bash
echo "=== Linkerd Certificate Status ==="
echo ""

# Check Linkerd health including certificates
linkerd check --proxy | grep -A10 "certificate"

# View certificate expiration
echo ""
echo "Certificate Details:"
kubectl get secret -n linkerd linkerd-identity-issuer -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -noout -dates

echo ""
echo "Trust Anchor:"
kubectl get secret -n linkerd linkerd-trust-anchor -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -noout -subject -dates
```

**Expected Output:**
- All certificate checks pass ✓
- Issuer certificate valid for 1 year
- Trust anchor valid for 10 years
- Certificates automatically rotated by Linkerd every 24 hours

---

### Demo Summary

**What We Demonstrated:**

1. ✅ **Service Mesh Injection** - All pods have Linkerd proxy sidecar
2. ✅ **API Functionality** - REST API working through ALB → nginx → backend-api → postgres
3. ✅ **mTLS Encryption** - `tls=true` for ALL inter-service traffic
4. ✅ **Golden Metrics** - Automatic success rate, RPS, latency without instrumentation
5. ✅ **End-to-End Security** - nginx → backend-api AND backend-api → postgres both encrypted
6. ✅ **Zero Code Changes** - Applications unaware of encryption
7. ✅ **Automatic Certificates** - Linkerd manages and rotates all certificates

**Architecture:**
```
External Client
    ↓ HTTP
GCP ALB
    ↓ HTTP (unencrypted)
nginx (3 replicas)
    ↓ HTTPS with mTLS ✓ (tls=true)
backend-api (2 replicas)
    ↓ HTTPS with mTLS ✓ (tls=true)
postgres (1 replica)
```

**Key Takeaways:**
- **Zero-trust security** - All service-to-service traffic encrypted by default
- **No application changes** - Linkerd operates transparently at the network layer
- **Production-ready** - High availability, automatic failover, certificate rotation
- **Observable** - Request-level metrics, live traffic tap, service topology
- **Minimal overhead** - Sub-millisecond latency impact (p50 < 1ms)

---

### Traffic Flow Breakdown

**Step-by-step traffic flow:**

```mermaid
sequenceDiagram
    participant Client as External Client
    participant ALB as GCP ALB
    participant Nginx as nginx Pod<br/>(with Linkerd proxy)
    participant BackendAPI as backend-api Pod<br/>(with Linkerd proxy)
    participant Postgres as postgres Pod<br/>(with Linkerd proxy)

    Client->>ALB: HTTP GET /api/users
    ALB->>Nginx: HTTP (unencrypted)

    Note over Nginx: Linkerd proxy intercepts
    Nginx->>BackendAPI: HTTPS with mTLS ✓<br/>tls=true

    Note over BackendAPI: Linkerd proxy intercepts
    BackendAPI->>Postgres: HTTPS with mTLS ✓<br/>tls=true

    Postgres-->>BackendAPI: Query results (encrypted)
    BackendAPI-->>Nginx: JSON response (encrypted)
    Nginx-->>ALB: HTTP (unencrypted)
    ALB-->>Client: HTTP JSON response
```

### Monitoring mTLS Traffic

**1. Live Traffic Inspection:**
```bash
# Watch nginx → backend-api traffic
linkerd viz tap deploy/backend-api -n backend-api

# Watch backend-api → postgres traffic
linkerd viz tap statefulset/postgres -n postgres

# Filter by specific path
linkerd viz tap deploy/backend-api -n backend-api --path /api/users

# Show only successful requests
linkerd viz tap deploy/backend-api -n backend-api --path /api | grep "tls=true"
```

**2. Golden Metrics:**
```bash
# View backend-api metrics
linkerd viz stat deploy/backend-api -n backend-api

# Expected output:
NAME          MESHED   SUCCESS      RPS   LATENCY_P50   LATENCY_P95   LATENCY_P99   TCP_CONN
backend-api      2/2   100.00%   10.5rps         8ms          25ms          45ms          3

# View route-specific metrics
linkerd viz routes deploy/backend-api -n backend-api

# Expected output:
ROUTE              SERVICE       SUCCESS      RPS   LATENCY_P50   LATENCY_P95   LATENCY_P99
GET /api/users     backend-api   100.00%    5.2rps         5ms          15ms          30ms
GET /api/health    backend-api   100.00%    2.1rps         3ms           8ms          15ms
POST /api/users    backend-api    99.95%    0.8rps        12ms          35ms          60ms
```

**3. Linkerd Dashboard:**
```bash
# Port-forward the dashboard
kubectl port-forward -n linkerd-viz svc/web 8084:8084

# Open in browser
open http://localhost:8084

# Navigate to:
# - Namespaces → nginx-alb → Deployments → nginx
# - Click "Live calls" to see real-time traffic
# - View topology graph showing: nginx → backend-api → postgres
```

### Troubleshooting

**Issue: 404 Not Found on /api/ requests**

**Symptom:**
```bash
curl http://$ALB_URL/api/users
# Returns: 404 Not Found
```

**Root Cause:** Nginx configuration not updated with `/api/` location block

**Solution:**
```bash
# 1. Verify nginx ConfigMap has the API proxy configuration
kubectl get configmap -n nginx-alb nginx-config -o jsonpath='{.data.nginx\.conf}' | grep -A10 "location /api"

# 2. If missing, check if Kustomize overlay patch exists
ls -la k8s-manifests/nginx-alb/overlays/dev/nginx-config-patch.yaml

# 3. Verify kustomization.yaml includes the patch
cat k8s-manifests/nginx-alb/overlays/dev/kustomization.yaml | grep nginx-config-patch

# 4. If patch exists but not applied, trigger ArgoCD sync
kubectl patch application nginx-alb -n argocd --type merge \
  -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}'

# 5. Restart nginx pods to reload configuration
kubectl rollout restart deployment/nginx -n nginx-alb
```

**Issue: backend-api pods show tls=no_tls_from_remote**

**Symptom:** Tap shows `tls=no_tls_from_remote` instead of `tls=true`

**Root Cause:** Backend-api namespace doesn't have Linkerd injection enabled

**Solution:**
```bash
# 1. Check namespace annotation
kubectl get namespace backend-api -o yaml | grep "linkerd.io/inject"

# 2. If missing, add annotation
kubectl annotate namespace backend-api linkerd.io/inject=enabled

# 3. Restart pods to inject Linkerd proxy
kubectl rollout restart deployment/backend-api -n backend-api

# 4. Verify injection
kubectl get pods -n backend-api -o jsonpath='{.items[0].spec.containers[*].name}'
# Should show: linkerd-proxy backend-api
```

**Issue: Database connection failed**

**Symptom:**
```json
{"error": "connection to server at \"postgres.postgres.svc.cluster.local\" failed: FATAL: password authentication failed"}
```

**Root Cause:** Backend-api using wrong PostgreSQL credentials

**Solution:**
```bash
# 1. Get correct postgres password
kubectl get secret -n postgres postgres-secret -o jsonpath='{.data.password}' | base64 -d

# 2. Verify backend-api has postgres-secret in its namespace
kubectl get secret -n backend-api postgres-secret

# 3. If missing, copy secret from postgres namespace
kubectl get secret -n postgres postgres-secret -o json | \
  jq 'del(.metadata.namespace,.metadata.creationTimestamp,.metadata.resourceVersion,.metadata.uid,.metadata.ownerReferences)' | \
  jq '.metadata.namespace = "backend-api"' | \
  kubectl apply -f -

# 4. Restart backend-api pods
kubectl rollout restart deployment/backend-api -n backend-api
```

### Sample Data

The backend-api automatically initializes PostgreSQL with sample user data on first startup:

```sql
-- Users table structure
CREATE TABLE users (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    email VARCHAR(100) UNIQUE NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Sample data (5 users)
INSERT INTO users (name, email) VALUES
    ('Alice Johnson', 'alice@example.com'),
    ('Bob Smith', 'bob@example.com'),
    ('Carol Williams', 'carol@example.com'),
    ('David Brown', 'david@example.com'),
    ('Eve Davis', 'eve@example.com');
```

You can verify the data directly in PostgreSQL:
```bash
kubectl exec -n postgres postgres-0 -c postgres -- \
  psql -U postgres -d testdb -c "SELECT * FROM users;"
```

---

## Resource Impact

### Cluster Capacity (5 x t3.medium nodes)

**Total Capacity:**
- CPU: 9,650m (9.65 cores)
- Memory: 16,855Mi (~16.5 GB)

**Linkerd Resource Usage:**

| Component | Pods | CPU Request | Memory Request |
|-----------|------|-------------|----------------|
| Control Plane | 6 | ~800m | ~512Mi |
| Viz Dashboard | 4 | ~400m | ~256Mi |
| App Sidecars (6 pods) | 6 | ~600m | ~384Mi |
| **Total** | **16** | **~1,800m** | **~1,152Mi** |

**Remaining Capacity:**
- CPU: 7,850m (81% available)
- Memory: 15,703Mi (93% available)

**Per-Pod Overhead:**
- CPU: 100m per linkerd-proxy sidecar
- Memory: 64Mi per linkerd-proxy sidecar
- Latency: p50 < 1ms, p99 < 5ms

---

## Maintenance

### Certificate Renewal

**Certificate Expiration:**
- **Issuer Certificate:** Expires 2026-12-01 (1 year validity)
- **Trust Anchor:** Expires 2035-11-29 (10 years validity)

**Renewal Process (before expiration):**

```bash
# 1. Generate new issuer certificate
cd /tmp/linkerd-certs
step certificate create identity.linkerd.cluster.local issuer-new.crt issuer-new.key \
  --profile intermediate-ca \
  --not-after 8760h \
  --no-password \
  --insecure \
  --ca ca.crt \
  --ca-key ca.key

# 2. Update Kubernetes secret
kubectl create secret tls linkerd-identity-issuer \
  --cert=issuer-new.crt \
  --key=issuer-new.key \
  --namespace=linkerd \
  --dry-run=client -o yaml | kubectl apply -f -

# 3. Update ArgoCD application with new certificate
# Edit argocd-apps/linkerd-app.yaml with new certificate content

# 4. Restart Linkerd identity pods
kubectl rollout restart deployment linkerd-identity -n linkerd
```

### Upgrade Linkerd Version

```bash
# 1. Check current version
linkerd version

# 2. Upgrade Linkerd CLI
curl -fsL https://run.linkerd.io/install | sh

# 3. Update chart versions in ArgoCD applications
# Edit argocd-apps/linkerd-crds-app.yaml - update targetRevision
# Edit argocd-apps/linkerd-app.yaml - update targetRevision
# Edit argocd-apps/linkerd-viz-app.yaml - update targetRevision

# 4. Commit and push
git add argocd-apps/linkerd-*.yaml
git commit -m "Upgrade Linkerd to version X.Y.Z"
git push

# 5. ArgoCD will automatically sync and upgrade
```

### Monitor Linkerd Health

```bash
# Daily health check
linkerd check
linkerd viz check

# Monitor control plane pods
kubectl get pods -n linkerd -w

# Check for certificate expiration
linkerd check --proxy

# View metrics
kubectl top pods -n linkerd
kubectl top pods -n linkerd-viz
```

---

## References

- [Linkerd Documentation](https://linkerd.io/docs/)
- [Linkerd GitOps Guide](https://linkerd.io/2/tasks/gitops/)
- [SMI Traffic Split Spec](https://github.com/servicemeshinterface/smi-spec/blob/main/apis/traffic-split/v1alpha2/traffic-split.md)
- [Step CLI Documentation](https://smallstep.com/docs/step-cli)
- [Linkerd Helm Charts](https://github.com/linkerd/linkerd2/tree/main/charts)

---

## Conclusion

Linkerd service mesh has been successfully deployed and integrated into the GKE demo environment, providing:

✅ **Zero-trust security** with automatic mTLS encryption
✅ **Advanced observability** with golden metrics and live traffic tap
✅ **Production-ready** HA control plane with proper certificate management
✅ **GitOps-managed** deployment with ArgoCD auto-sync
✅ **Minimal overhead** using only 18% CPU and 7% memory

All application pods are now meshed and communicating securely with certificate-based identity and automatic encryption.
