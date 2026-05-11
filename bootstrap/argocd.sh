#!/bin/bash
set -euo pipefail

echo "=== ArgoCD Bootstrap ==="
echo "This script installs ArgoCD via Helm, then applies the root-app."
echo "After this, ArgoCD will manage itself and all other apps via Git."

# Add the ArgoCD Helm repo
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

# Install ArgoCD via Helm (matches what the Application CR will manage)
helm install argocd argo/argo-cd \
  --namespace argocd \
  --create-namespace \
  --version 9.5.13 \
  --set 'configs.params.server\.insecure=true' \
  --set server.ingress.enabled=true \
  --set server.ingress.ingressClassName=nginx \
  --set server.ingress.hostname=argocd.nas-local.io \
  --set 'server.ingress.annotations.nginx\.ingress\.kubernetes\.io/backend-protocol=HTTP' \
  --set dex.enabled=false \
  --wait

echo ""
echo "ArgoCD installed. Getting initial admin password..."
echo "Password: $(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d)"
echo ""

# Apply the root-app to kick off GitOps
echo "Applying root-app..."
kubectl apply -f https://raw.githubusercontent.com/marcizhu/microk8s-nas/master/apps/root-app.yaml

echo ""
echo "Done! ArgoCD will now sync all apps from Git, including itself."
echo "Access the UI at: http://argocd.nas-local.io"
