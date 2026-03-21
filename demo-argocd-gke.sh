#!/bin/bash
#
# ArgoCD GitOps Demo Script
# Demonstrates automatic deployment and self-healing capabilities
#
# Author: Jian Ouyang (jian.ouyang@sapns2.com)
# Purpose: Concur GKE POC Q&A Demo
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
REPO_DIR="/opt/code/aaa_all_tests/gke"
GITHUB_REPO="https://github.com/softwareengineerva/gke.git"

# Helper functions
print_header() {
    echo -e "${BLUE}===================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}===================================${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_info() {
    echo -e "ℹ️  $1"
}

wait_for_user() {
    echo ""
    read -p "Press ENTER to continue..."
    echo ""
}

# Pre-flight checks
preflight_checks() {
    print_header "Pre-Flight Checks"

    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        print_error "kubectl not found. Please install kubectl."
        exit 1
    fi
    print_success "kubectl installed"

    # Check argocd CLI
    if ! command -v argocd &> /dev/null; then
        print_warning "argocd CLI not found. Installing..."
        brew install argocd
    fi
    print_success "argocd CLI installed"

    # Check cluster connectivity
    if ! kubectl cluster-info &> /dev/null; then
        print_error "Cannot connect to Kubernetes cluster. Please configure kubectl."
        exit 1
    fi
    print_success "Connected to Kubernetes cluster"

    # Check ArgoCD is running
    if ! kubectl get namespace argocd &> /dev/null; then
        print_error "ArgoCD namespace not found. Please install ArgoCD first."
        exit 1
    fi
    print_success "ArgoCD is installed"

    echo ""
}

# Scenario 1: GitOps Deployment Flow
demo_gitops_deployment() {
    print_header "Scenario 1: GitOps Deployment Flow"

    print_info "This demo shows how ArgoCD automatically deploys changes from Git."
    echo ""

    # Show current nginx replicas
    print_info "Current nginx deployment status:"
    kubectl get deployment nginx -o wide || echo "Nginx not deployed yet"
    echo ""

    CURRENT_REPLICAS=$(kubectl get deployment nginx -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")
    print_info "Current replicas: $CURRENT_REPLICAS"

    # Calculate new replicas (toggle between 2 and 3)
    if [ "$CURRENT_REPLICAS" == "2" ]; then
        NEW_REPLICAS=3
    else
        NEW_REPLICAS=2
    fi

    print_info "Will change replicas to: $NEW_REPLICAS"
    wait_for_user

    # Update manifest
    print_info "Updating manifest in Git..."
    cd "$REPO_DIR"

    # Update the deployment file
    sed -i.bak "s/replicas: [0-9]/replicas: $NEW_REPLICAS/" k8s-manifests/nginx-alb/deployment.yaml

    print_info "Modified manifest:"
    grep "replicas:" k8s-manifests/nginx-alb/deployment.yaml
    echo ""

    # Commit and push
    print_info "Committing to Git..."
    git add k8s-manifests/nginx-alb/deployment.yaml
    git commit -m "[Demo] Scale nginx to $NEW_REPLICAS replicas - $(date '+%Y-%m-%d %H:%M:%S')"

    print_warning "Ready to push to GitHub. This will trigger ArgoCD auto-sync."
    wait_for_user

    git push origin main
    print_success "Pushed to GitHub"

    echo ""
    print_info "ArgoCD polls Git every 3 minutes. Watching for sync..."
    print_info "You can also manually sync with: argocd app sync nginx-alb"
    echo ""

    # Watch ArgoCD app status
    print_info "Monitoring ArgoCD app status (press Ctrl+C when synced):"
    watch -n 5 "argocd app get nginx-alb | grep -E 'Sync Status|Health Status|Last Sync'"

    echo ""
    print_success "GitOps deployment completed!"
    echo ""

    # Show final state
    print_info "Final nginx deployment status:"
    kubectl get deployment nginx
    kubectl get pods -l app=nginx
    echo ""
}

# Scenario 2: Self-Healing Demonstration
demo_self_healing() {
    print_header "Scenario 2: Self-Healing Demonstration"

    print_info "This demo shows how ArgoCD automatically reverts manual changes."
    echo ""

    # Show current state
    print_info "Current nginx replicas:"
    kubectl get deployment nginx
    CURRENT_REPLICAS=$(kubectl get deployment nginx -o jsonpath='{.spec.replicas}')
    echo ""

    print_warning "We will manually scale nginx to $((CURRENT_REPLICAS + 2)) replicas using kubectl."
    print_warning "ArgoCD will detect the drift and auto-heal back to Git state."
    wait_for_user

    # Manual scale
    MANUAL_REPLICAS=$((CURRENT_REPLICAS + 2))
    print_info "Manually scaling to $MANUAL_REPLICAS replicas..."
    kubectl scale deployment nginx --replicas=$MANUAL_REPLICAS

    echo ""
    print_info "Manual scale completed. Current state:"
    kubectl get deployment nginx
    kubectl get pods -l app=nginx
    echo ""

    print_info "ArgoCD will detect drift within 3 minutes and revert to Git state ($CURRENT_REPLICAS replicas)."
    print_info "Watch ArgoCD detect and heal the drift (press Ctrl+C when healed):"
    echo ""

    # Watch for drift detection and healing
    watch -n 5 "echo 'ArgoCD Status:' && argocd app get nginx-alb | grep -E 'Sync Status|Health Status' && echo '' && echo 'Actual Replicas:' && kubectl get deployment nginx -o jsonpath='{.spec.replicas}'"

    echo ""
    print_success "Self-healing demonstration completed!"
    print_info "Git remains the single source of truth."
    echo ""
}

# Scenario 3: Multi-App Sync
demo_multi_app_sync() {
    print_header "Scenario 3: Sync All Applications"

    print_info "This demo shows how to sync all ArgoCD applications at once."
    echo ""

    print_info "Current application status:"
    argocd app list
    echo ""

    print_warning "This will sync all applications to their latest Git state."
    wait_for_user

    print_info "Syncing all applications..."
    argocd app sync --all

    echo ""
    print_info "Waiting for all apps to reach healthy state..."
    sleep 10

    echo ""
    print_info "Final application status:"
    argocd app list
    echo ""

    print_success "Multi-app sync completed!"
    echo ""
}

# Scenario 4: Monitoring Sync Progress
demo_monitoring() {
    print_header "Scenario 4: Monitoring ArgoCD"

    print_info "This demo shows various ways to monitor ArgoCD."
    echo ""

    # Application health
    print_info "=== Application Health ==="
    argocd app list
    echo ""

    # Detailed app info
    print_info "=== Nginx Application Details ==="
    argocd app get nginx-alb
    echo ""

    wait_for_user

    # Application logs
    print_info "=== Recent Application Logs (last 20 lines) ==="
    argocd app logs nginx-alb --tail=20
    echo ""

    wait_for_user

    # Sync history
    print_info "=== Sync History ==="
    argocd app history nginx-alb
    echo ""

    wait_for_user

    # Diff between Git and cluster
    print_info "=== Diff Between Git and Cluster ==="
    argocd app diff nginx-alb || echo "No differences found"
    echo ""

    print_success "Monitoring demo completed!"
    echo ""
}

# Scenario 5: Rollback Demonstration
demo_rollback() {
    print_header "Scenario 5: Rollback to Previous Version"

    print_info "This demo shows how to rollback to a previous Git commit."
    echo ""

    # Show history
    print_info "Recent sync history:"
    argocd app history nginx-alb
    echo ""

    print_info "Recent Git commits:"
    cd "$REPO_DIR"
    git log --oneline -5
    echo ""

    print_warning "To rollback:"
    print_info "1. Option A: Use Git revert"
    print_info "   git revert HEAD"
    print_info "   git push origin main"
    echo ""
    print_info "2. Option B: Rollback to specific commit"
    print_info "   git reset --hard <commit-sha>"
    print_info "   git push --force origin main"
    echo ""
    print_info "3. Option C: Use ArgoCD rollback (if available)"
    print_info "   argocd app rollback nginx-alb <revision>"
    echo ""

    print_warning "Git revert is preferred for production (maintains history)."
    echo ""
}

# Scenario 6: Update Sample App (Redis)
demo_update_redis() {
    print_header "Scenario 6: Update Redis Configuration"

    print_info "This demo updates Redis ConfigMap and shows auto-sync."
    echo ""

    print_info "Current Redis ConfigMap:"
    kubectl get configmap redis-config -o yaml | grep -A 5 "data:"
    echo ""

    # Get current maxmemory setting
    CURRENT_MAXMEMORY=$(grep "maxmemory" "$REPO_DIR/k8s-manifests/redis/configmap.yaml" | awk '{print $2}')
    print_info "Current maxmemory: $CURRENT_MAXMEMORY"

    # Toggle between 256mb and 512mb
    if [[ "$CURRENT_MAXMEMORY" == "256mb" ]]; then
        NEW_MAXMEMORY="512mb"
    else
        NEW_MAXMEMORY="256mb"
    fi

    print_info "Will change maxmemory to: $NEW_MAXMEMORY"
    wait_for_user

    # Update ConfigMap
    print_info "Updating Redis ConfigMap..."
    cd "$REPO_DIR"
    sed -i.bak "s/maxmemory [0-9]*mb/maxmemory $NEW_MAXMEMORY/" k8s-manifests/redis/configmap.yaml

    print_info "Modified ConfigMap:"
    grep "maxmemory" k8s-manifests/redis/configmap.yaml
    echo ""

    # Commit and push
    git add k8s-manifests/redis/configmap.yaml
    git commit -m "[Demo] Update Redis maxmemory to $NEW_MAXMEMORY - $(date '+%Y-%m-%d %H:%M:%S')"
    git push origin main

    print_success "Pushed to GitHub"
    echo ""

    print_info "Watching for ArgoCD sync..."
    watch -n 5 "argocd app get redis | grep -E 'Sync Status|Health Status'"

    echo ""
    print_info "ConfigMap updated. Restart Redis pod to apply:"
    print_info "kubectl rollout restart statefulset redis"
    echo ""

    print_success "Redis update demo completed!"
    echo ""
}

# Access Guide
show_access_guide() {
    print_header "Access Information"

    # ArgoCD
    echo ""
    print_info "=== ArgoCD ==="
    ARGOCD_URL=$(kubectl get svc -n argocd argocd-server -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "Not exposed via LoadBalancer")
    echo "URL: http://$ARGOCD_URL"
    echo "Username: admin"
    echo "Password: Run this command to get password:"
    echo "  kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
    echo ""

    # Grafana
    print_info "=== Grafana ==="
    echo "URL: kubectl port-forward -n monitoring svc/prometheus-stack-grafana 3000:80"
    echo "Then access: http://localhost:3000"
    echo "Username: admin"
    echo "Password: admin"
    echo ""

    # Prometheus
    print_info "=== Prometheus ==="
    echo "URL: kubectl port-forward -n monitoring svc/prometheus-stack-kube-prom-prometheus 9090:9090"
    echo "Then access: http://localhost:9090"
    echo ""

    # Nginx ALB
    print_info "=== Nginx Application ==="
    NGINX_URL=$(kubectl get ingress nginx-alb-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "Ingress not ready")
    echo "URL: http://$NGINX_URL"
    echo ""

    # CloudWatch Logs
    print_info "=== CloudWatch Logs ==="
    echo "Log Group: /aws/gke/concur-test-gke/all-pods"
    echo "AWS CLI: aws logs tail /aws/gke/concur-test-gke/all-pods --follow --region us-east-1"
    echo ""
}

# Interactive menu
show_menu() {
    clear
    print_header "ArgoCD GitOps Demo - Concur GKE POC"
    echo ""
    echo "Select a demo scenario:"
    echo ""
    echo "  1) GitOps Deployment Flow (Scale Nginx)"
    echo "  2) Self-Healing Demonstration"
    echo "  3) Sync All Applications"
    echo "  4) Monitoring and Observability"
    echo "  5) Rollback Guide"
    echo "  6) Update Redis Configuration"
    echo "  7) Access Information"
    echo "  8) Run All Demos Sequentially"
    echo "  9) Exit"
    echo ""
    read -p "Enter choice [1-9]: " choice
    echo ""
}

# Main execution
main() {
    # Run preflight checks
    preflight_checks

    # Interactive mode
    while true; do
        show_menu

        case $choice in
            1)
                demo_gitops_deployment
                ;;
            2)
                demo_self_healing
                ;;
            3)
                demo_multi_app_sync
                ;;
            4)
                demo_monitoring
                ;;
            5)
                demo_rollback
                ;;
            6)
                demo_update_redis
                ;;
            7)
                show_access_guide
                ;;
            8)
                print_warning "Running all demos sequentially..."
                echo ""
                demo_gitops_deployment
                demo_self_healing
                demo_multi_app_sync
                demo_monitoring
                demo_rollback
                demo_update_redis
                show_access_guide
                print_success "All demos completed!"
                ;;
            9)
                print_info "Exiting demo..."
                exit 0
                ;;
            *)
                print_error "Invalid choice. Please select 1-9."
                sleep 2
                ;;
        esac

        wait_for_user
    done
}

# Run main
if [ "$1" == "--help" ] || [ "$1" == "-h" ]; then
    echo "ArgoCD GitOps Demo Script"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --help, -h    Show this help message"
    echo "  --access      Show access information only"
    echo ""
    echo "Interactive mode will start if no options provided."
    exit 0
fi

if [ "$1" == "--access" ]; then
    show_access_guide
    exit 0
fi

# Start interactive mode
main
