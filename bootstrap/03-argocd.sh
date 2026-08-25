#!/bin/bash
set -euo pipefail

# =============================================================
# ArgoCD Bootstrap
#
# Installs ArgoCD via Helm, applies the root-app to kick off
# GitOps, then configures the host (DNS name, CLI) and the
# 'marcizhu' account password.
#
# Run this in a NEW terminal after 00-setup.sh so the microk8s
# group is active for cluster access.
# =============================================================

COLOR_BLUE='\033[1;34m'
COLOR_WHITE='\033[1;37m'
COLOR_YELLOW='\033[1;33m'
COLOR_RESET='\033[0m'

echo "███╗░░░███╗██╗░█████╗░██████╗░░█████╗░██╗░░██╗░█████╗░░██████╗  ███╗░░██╗░█████╗░░██████╗"
echo "████╗░████║██║██╔══██╗██╔══██╗██╔══██╗██║░██╔╝██╔══██╗██╔════╝  ████╗░██║██╔══██╗██╔════╝"
echo "██╔████╔██║██║██║░░╚═╝██████╔╝██║░░██║█████═╝░╚█████╔╝╚█████╗░  ██╔██╗██║███████║╚█████╗░"
echo "██║╚██╔╝██║██║██║░░██╗██╔══██╗██║░░██║██╔═██╗░██╔══██╗░╚═══██╗  ██║╚████║██╔══██║░╚═══██╗"
echo "██║░╚═╝░██║██║╚█████╔╝██║░░██║╚█████╔╝██║░╚██╗╚█████╔╝██████╔╝  ██║░╚███║██║░░██║██████╔╝"
echo "╚═╝░░░░░╚═╝╚═╝░╚════╝░╚═╝░░╚═╝░╚════╝░╚═╝░░╚═╝░╚════╝░╚═════╝░  ╚═╝░░╚══╝╚═╝░╚═╝╚═════╝░"
echo
echo -e "${COLOR_WHITE}=== ArgoCD Bootstrap ===${COLOR_RESET}"
echo "This installs ArgoCD via Helm, then applies the root-app."
echo "After this, ArgoCD manages itself and all other apps via Git."
echo
read -p "Press Enter to continue..."

# Sanity check: we need cluster access (microk8s group) in THIS session.
if ! kubectl cluster-info >/dev/null 2>&1; then
    echo -e "${COLOR_YELLOW}WARNING: cannot reach the cluster as '$USER'.${COLOR_RESET}" >&2
    echo "Open a new terminal (so the microk8s group is active) and re-run." >&2
    exit 1
fi

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

echo
echo "ArgoCD installed. Initial admin password:"
echo "  $(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d)"
echo

# Apply the root-app to kick off GitOps
echo -e "${COLOR_BLUE}Applying root-app...${COLOR_RESET}"
kubectl apply -f https://raw.githubusercontent.com/marcizhu/microk8s-nas/master/apps/root-app.yaml

echo
echo "ArgoCD will now sync all apps from Git, including itself."
echo "UI: http://argocd.nas-local.io"
echo

################################
# Configure host + ArgoCD users
################################

# Resolve argocd.nas-local.io locally
if ! grep -qs "argocd.nas-local.io" /etc/hosts; then
    echo "192.168.1.15 argocd.nas-local.io" | sudo tee -a /etc/hosts
fi

# Install ArgoCD CLI
echo -e "${COLOR_BLUE}Installing ArgoCD CLI...${COLOR_RESET}"
curl -sSL -o argocd-linux-amd64 https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
sudo install -m 555 argocd-linux-amd64 /usr/local/bin/argocd
rm argocd-linux-amd64

# Log in as admin using the initial password
password=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d)
argocd login argocd.nas-local.io --username admin --password "$password" --grpc-web

# Set a real password for the 'marcizhu' account (no more placeholder).
echo
read -r -s -p "New password for account 'marcizhu' (leave blank to skip): " newpw
echo
if [ -n "$newpw" ]; then
    argocd account update-password --account marcizhu --new-password "$newpw"
    echo "Updated password for 'marcizhu'."
else
    echo "Skipped. You can set it later with:"
    echo "  argocd account update-password --account marcizhu --new-password '<pass>'"
fi

echo
echo -e "${COLOR_WHITE}Done!${COLOR_RESET} ArgoCD is bootstrapped and GitOps is running."
