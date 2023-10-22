# MicroK8s NAS

<img src="https://raw.githubusercontent.com/kubernetes/kubernetes/master/logo/logo.svg" align="left" width="144px" height="144px">

#### microk8s-nas - Home Cloud via ArgoCD | GitOps Toolkit

> GitOps state for my cluster using ArgoCD

[![MicroK8s](https://img.shields.io/github/v/release/canonical/microk8s?label=MicroK8s&color=green)](https://microk8s.io)
[![Last commit](https://img.shields.io/github/last-commit/marcizhu/microk8s-nas?style=flat-square)](https://github.com/marcizhu/microk8s-nas)

Lightweight single-node [MicroK8s](https://microk8s.io) cluster for my home NAS running [Ubuntu Server](https://ubuntu.com/download/server).

## 💻 Nodes

| Device                       | CPU                 | OS Disk       | Data Disk   | RAM   | OS            | Purpose     |
| :--------------------------- | :------------------ | :------------ | :---------- | :---- | :------------ | :---------- |
| Lenovo ThinkCentre M700 Tiny | Intel Core i5-6400T | 1x 256 GB SSD | 3x 2 Tb HDD | 16 GB | Ubuntu Server | NAS/NFS/k8s |

Total CPU: 8 threads  
Total RAM: 16 GB

## Off-cluster support

- RAID: All three disks are in a RAID 5 configuration for redundancy.
- NFS Server: The NFS server runs on the host machine outside Kubernetes and allows connecting to the RAID array from outside the node

## Cluster components

### Networking

- [Blocky](https://0xerr0r.github.io/blocky/v0.22/): A DNS proxy and ad-blocker for the local network with a custom domain
- [Calico](https://www.tigera.io/project-calico/): Container networking with IPv6 support and policy enforcement
- [MetalLB](https://github.com/metallb/metallb): A network load-balancer implementation for Kubernetes using standard routing protocols
- [NGINX Ingress Controller](https://github.com/kubernetes/ingress-nginx): Ingress-NGINX Controller for Kubernetes

### Infrastructure

- [ArgoCD](https://github.com/argoproj/argo-cd): A declarative, GitOps continuous delivery tool for Kubernetes
- [Renovate](https://github.com/renovatebot/renovate): Universal dependency update tool to keep manifests up-to-date
- [Prometheus](https://prometheus.io): A tool to scrape and store time-series metrics from other services
- [Grafana](https://grafana.com): An open-source dashboard to monitor Kubernetes, storage and system metrics

### Applications

- [Transmission](https://transmissionbt.com): A fast, easy and free torrent client for macOS, Windows and Linux
- [Plex](https://www.plex.tv/): A library for all your videos, movies and series, allowing to watch them on you phone, smart TV, computer, etc.
- [Gickup](https://github.com/cooperspencer/gickup): A simple tool to backup all my repositories locally to my NAS

## 🌐 Network configuration

The service Blocky deployed in-cluster has three purposes:

1. Acts as a local DNS cache, speeding up DNS queries at home
2. DNS-level ad-filtering, similar to Pi-Hole. Blocks ads, adult content, etc
3. Custom domain: resolves any subdomain `*.nas-local.io` to the cluster's IP

By configuring the cluster as the primary DNS in the router, any device connected by DHCP will be able to access any service
deployed through the subdomains `*.nas-local.io`. NGINX Ingress will route the requests depending on the `Host:` HTTP header.

Thanks to MetalLB, any non-HTTP service can be deployed on its own IP address, so that it doesn't interfere with other services.

## 🔧 Maintenance

Maintenance of the cluster is fairly minimal thanks to Renovate and ArgoCD: an hourly cronjob runs renovate bot, which will
create PRs in this repo to update docker images in the cluster. Then, ArgoCD will apply any PR merged into `master` automatically,
keeping everything up-to-date with minimal interaction.

## Repository structure

The git repository contains the following directories. The main folder is `apps`, which contains the Kubernetes manifests for all applications running in the cluster. The folder `bootstrap` contains some CRDs needed to bootstrap the cluster, but they are not needed afterwards.

```
📁 (root)
├─📁 apps       # cluster apps, usually one file per application
├─📁 bootstrap  # CRDs and other resources for setting up the cluster
```
