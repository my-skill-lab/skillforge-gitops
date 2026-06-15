#!/usr/bin/env bash
# Bootstrap ArgoCD and apply all Skill Lab Application manifests.
# Run this any time the cluster is reset (e.g. after Rancher Desktop update).
#
# Usage: ./bootstrap.sh [--context <kubectl-context>]
#
# Requirements: kubectl, curl

set -euo pipefail

CONTEXT="${KUBECTL_CONTEXT:-$(kubectl config current-context)}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Parse optional --context flag
while [[ $# -gt 0 ]]; do
  case $1 in
    --context) CONTEXT="$2"; shift 2 ;;
    *) echo "Unknown argument: $1"; exit 1 ;;
  esac
done

echo "=> Using kubectl context: $CONTEXT"

# 1. Install ArgoCD
echo "=> Installing ArgoCD..."
kubectl --context="$CONTEXT" create namespace argocd --dry-run=client -o yaml \
  | kubectl --context="$CONTEXT" apply -f -

kubectl --context="$CONTEXT" apply -n argocd \
  --server-side --force-conflicts \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

echo "=> Waiting for ArgoCD server to be ready..."
kubectl --context="$CONTEXT" wait --for=condition=available \
  deployment/argocd-server -n argocd --timeout=120s

# 2. Apply Application manifests
echo "=> Applying ArgoCD Application manifests..."
kubectl --context="$CONTEXT" apply -f "$SCRIPT_DIR/apps/skill-lab-app/staging/application.yaml"
kubectl --context="$CONTEXT" apply -f "$SCRIPT_DIR/apps/skill-lab-app/production/application.yaml"

# 3. Print admin password and access instructions
ARGOCD_PASSWORD=$(kubectl --context="$CONTEXT" -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d)

echo ""
echo "========================================="
echo "  ArgoCD is ready!"
echo "========================================="
echo ""
echo "  Open the UI:"
echo "  kubectl --context=$CONTEXT port-forward svc/argocd-server -n argocd 8080:443"
echo "  Then visit: https://localhost:8080"
echo ""
echo "  Login:"
echo "  Username: admin"
echo "  Password: $ARGOCD_PASSWORD"
echo ""
echo "  Applications deployed:"
echo "  - skill-lab-staging  (namespace: staging)"
echo "  - skill-lab-production (namespace: production)"
echo "========================================="
