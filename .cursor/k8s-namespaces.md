# Kubernetes Cluster Namespaces Summary

This document provides a one-sentence summary of each namespace in the Kubernetes cluster.

## Namespace Summaries

- **arc** - GitHub Actions Runner Controller namespace running self-hosted runners for CI/CD workflows including multi-architecture builds (amd64 and arm64).

- **asustor** - Namespace hosting services for Asustor NAS integration, currently with a service endpoint but no active pods.

- **brandon-dev** - Development namespace for personal testing and development work, running an nginx deployment.

- **calico-apiserver** - Calico network policy API server namespace providing Kubernetes-native network policy management through Calico CNI.

- **calico-system** - Core Calico CNI networking components including calico-node daemonsets, calico-typha, and CSI drivers for cluster-wide networking and policy enforcement.

- **cert-manager** - Automated TLS certificate management using Let's Encrypt and other certificate authorities, including a cloudflare-ddns component for dynamic DNS updates.

- **dashy** - Personal dashboard application providing a customizable homepage for organizing and accessing various services and applications.

- **default** - Default Kubernetes namespace running a podinfo deployment for general testing and application deployment.

- **external-dns** - External DNS controller automatically managing DNS records in external DNS providers based on Kubernetes ingress and service resources.

- **flux-system** - GitOps deployment automation system managing cluster configuration and applications through Flux controllers (helm, kustomize, image automation, and notification controllers).

- **fui-components** - Custom frontend UI components application deployed for development or testing purposes.

- **grafana** - Grafana monitoring and visualization platform with operator, production deployment, and staging deployments for dashboards and metrics visualization.

- **haproxy** - HAProxy load balancer service endpoint configured for traffic distribution and load balancing.

- **harbor** - Enterprise container registry solution providing secure image storage, scanning with Trivy, job services, and a web portal for container management.

- **home-assistant** - Home Assistant automation platform service for smart home device integration and automation, currently configured with service but no active pods.

- **home-hud** - Custom home heads-up display application with a Pi LED API service for displaying information on LED displays.

- **ingress-nginx** - NGINX ingress controller running as a daemonset across all nodes to provide HTTP/HTTPS load balancing and SSL termination for cluster ingress traffic.

- **kube-node-lease** - Kubernetes system namespace for node heartbeat coordination using lease objects for node availability tracking.

- **kube-public** - Kubernetes system namespace containing publicly accessible cluster information readable by all authenticated users.

- **kube-system** - Core Kubernetes system namespace hosting essential cluster components including CoreDNS, kube-proxy daemonsets, API server, controller manager, etcd, and sealed-secrets-controller.

- **longhorn-system** - Distributed block storage system providing persistent volumes with CSI drivers, managers, and engines for high-availability storage across the cluster.

- **media** - Media management suite namespace running Prowlarr (indexer manager), Radarr (movie manager), Sonarr (TV manager), and qBittorrent-VPN for media acquisition and organization.

- **monitoring** - Comprehensive observability stack including Prometheus, Grafana, Loki (log aggregation), Alertmanager, OpenTelemetry collectors, and kube-state-metrics for cluster and application monitoring.

- **nas-storage** - Network-attached storage integration using NFS subdir external provisioner for dynamic volume provisioning from NAS systems.

- **op-connect** - 1Password Connect service and operator for secure secret management and integration with 1Password vaults.

- **pihole** - Pi-hole DNS-based network-wide ad blocker service endpoint, configured but currently without active pods.

- **plex** - Plex media server service endpoint for streaming and managing media libraries, configured but currently without active pods.

- **proxmox** - Proxmox virtualization platform service endpoint for managing and accessing Proxmox hypervisor, configured but currently without active pods.

- **tigera-operator** - Tigera operator managing Calico network policies and advanced networking features for the cluster.

- **uptime-kuma** - Uptime monitoring service tracking availability and performance of services and endpoints with multiple replica pods.

- **verdaccio** - Private npm registry proxy for caching and serving Node.js packages within the organization or development environment.
