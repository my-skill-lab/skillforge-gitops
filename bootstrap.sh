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

# Fly Helm OCI credentials (required for ArgoCD to pull Helm charts)
# Set via: export FLY_HELM_TOKEN=<token>  (read-only Fly token, e.g. argocd-helm-reader)
FLY_HELM_USER="${FLY_HELM_USER:-yaronl+skl@jfrog.com}"
if [ -z "${FLY_HELM_TOKEN:-}" ]; then
  echo "WARNING: FLY_HELM_TOKEN is not set — ArgoCD won't be able to pull Helm charts."
  echo "         Create a read-only token in Fly Web → Token Management and re-run with:"
  echo "         FLY_HELM_TOKEN=<token> ./bootstrap.sh"
fi

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

# 2. Create namespaces
echo "=> Creating staging and production namespaces..."
kubectl --context="$CONTEXT" create namespace staging --dry-run=client -o yaml \
  | kubectl --context="$CONTEXT" apply -f -
kubectl --context="$CONTEXT" create namespace production --dry-run=client -o yaml \
  | kubectl --context="$CONTEXT" apply -f -

# 2b. Configure ArgoCD Helm OCI credentials
if [ -n "${FLY_HELM_TOKEN:-}" ]; then
  echo "=> Configuring ArgoCD Helm OCI credentials..."
  kubectl --context="$CONTEXT" apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: argocd-helm-oci-creds
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: repository
stringData:
  type: helm
  url: skillab.jfrog.io/helmoci
  username: ${FLY_HELM_USER}
  password: ${FLY_HELM_TOKEN}
  enableOCI: "true"
EOF
fi

# 4. Configure ArgoCD sync interval
echo "=> Setting reconciliation interval to 30s..."
kubectl --context="$CONTEXT" patch configmap argocd-cm -n argocd \
  --type merge -p '{"data":{"timeout.reconciliation":"30s"}}'
kubectl --context="$CONTEXT" rollout restart deployment argocd-repo-server -n argocd
kubectl --context="$CONTEXT" wait --for=condition=available \
  deployment/argocd-repo-server -n argocd --timeout=60s

# 5. Apply Application manifests
echo "=> Applying ArgoCD Application manifests..."
kubectl --context="$CONTEXT" apply -f "$SCRIPT_DIR/apps/skill-lab-app/staging/application.yaml"
kubectl --context="$CONTEXT" apply -f "$SCRIPT_DIR/apps/skill-lab-app/production/application.yaml"

# 6. Print admin password and access instructions
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
echo ""
echo "  IMPORTANT — Image pull secrets are NOT created by this script."
echo "  Run the following in Claude Code after bootstrapping:"
echo "  'create fly image pull secret for staging and production'"
echo "========================================="
