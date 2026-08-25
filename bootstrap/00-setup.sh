#!/bin/bash
set -euo pipefail

# =============================================================
# NAS Base Setup
# Run this on a fresh Ubuntu Server installation.
# Prerequisites: Ubuntu Server installed, user has sudo access
#
# This script only sets up the base system + MicroK8s cluster.
# When it finishes, open a NEW terminal (so the microk8s group is
# active for this user) and continue with:
#   01-sealed-secrets.sh   (only if restoring from a backup)
#   02-raid.sh             (optional: RAID / NFS storage)
#   03-argocd.sh           (ArgoCD + user accounts)
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
echo -e "${COLOR_WHITE}Welcome to the NAS base setup!${COLOR_RESET}"
echo -e "${COLOR_WHITE}==================================${COLOR_RESET}"
echo
echo "You will be asked for your sudo password a few times."
echo
read -p "Press Enter to continue..."

# ------- Network: Static IP -------
echo -e "${COLOR_BLUE}Configuring static IP...${COLOR_RESET}"
cat <<'EOF' | sudo tee /etc/netplan/01-static.yaml
network:
  version: 2
  ethernets:
    eno1:
      dhcp4: false
      addresses:
        - 192.168.1.15/24
      routes:
        - to: default
          via: 192.168.1.1
      nameservers:
        addresses:
          - 8.8.8.8
          - 1.1.1.1
EOF
sudo netplan apply

# ------- OS Prep -------
echo -e "${COLOR_BLUE}Disabling swap...${COLOR_RESET}"
sudo swapoff -a
sudo sed -i '/ swap / s/^/#/' /etc/fstab

echo -e "${COLOR_BLUE}Installing prerequisites...${COLOR_RESET}"
sudo apt-get update
sudo apt-get install -y open-iscsi nfs-kernel-server

# ------- MicroK8s -------
echo -e "${COLOR_BLUE}Installing MicroK8s...${COLOR_RESET}"
sudo snap install microk8s --classic --channel=1.31/stable

echo -e "${COLOR_BLUE}Configuring user permissions...${COLOR_RESET}"
sudo usermod -aG microk8s $USER
sudo chown -f -R $USER ~/.kube || true

echo -e "${COLOR_BLUE}Waiting for MicroK8s to be ready...${COLOR_RESET}"
sudo microk8s status --wait-ready

echo -e "${COLOR_BLUE}Configuring MicroK8s addons...${COLOR_RESET}"
sudo microk8s disable ha-cluster --force
sudo microk8s enable dns
sudo microk8s enable helm3
sudo microk8s enable hostpath-storage
sudo microk8s enable ingress
sudo microk8s enable metallb:192.168.1.10-192.168.1.14

echo -e "${COLOR_BLUE}Setting up kubectl/helm aliases...${COLOR_RESET}"
sudo snap alias microk8s.kubectl kubectl
sudo snap alias microk8s.helm3 helm

echo
echo -e "${COLOR_WHITE}==========================================${COLOR_RESET}"
echo -e "${COLOR_WHITE} Base setup complete!${COLOR_RESET}"
echo -e "${COLOR_WHITE}==========================================${COLOR_RESET}"
echo
echo -e "${COLOR_YELLOW}IMPORTANT:${COLOR_RESET} open a NEW terminal so the 'microk8s' group is"
echo "active for $USER, then continue with the remaining scripts:"
echo
echo "  01-sealed-secrets.sh   (only if you have a sealing key backup to restore)"
echo "  02-raid.sh             (optional: RAID / NFS storage)"
echo "  03-argocd.sh           (ArgoCD + user accounts)"
echo
