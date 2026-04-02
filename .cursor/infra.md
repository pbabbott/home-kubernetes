# Infrastructure Overview

This repository is deployed on a small Kubernetes cluster.

## Clusters

I have 3 kubernetes clusters

- Prod gen 1 (soon to be shut down)
- Prod gen 2 (WIP)
- Non-prod gen 2 (WIP)

Here are the hosts for each

### Prod gen 2
tfpc1="ssh firebolt@192.168.6.24"
tfpw1="ssh firebolt@192.168.6.25"
tfpw2="ssh firebolt@192.168.6.26"
tfpw3="ssh firebolt@192.168.6.27"

### Non-prod gen 2
tfnpc1="ssh firebolt@192.168.6.31"
tfnpw1="ssh firebolt@192.168.6.32"
tfnpw2="ssh firebolt@192.168.6.33"
tfnpw3="ssh firebolt@192.168.6.34"

### Prod gen 1
controller="ssh firebolt@192.168.4.193"
worker1="ssh firebolt@192.168.4.194"
worker2="ssh firebolt@192.168.4.195"
worker3="ssh firebolt@192.168.5.81"
dumbledore="ssh albus@192.168.4.157"

## Kubernetes Nodes

Each cluster has three worker nodes. When I refer to them, use the following aliases:

- worker1 → ssh firebolt@192.168.4.194
- worker2 → ssh firebolt@192.168.4.195
- worker3 → ssh firebolt@192.168.5.81
- controller → ssh firebolt@192.168.4.193

If I ask to "SSH into worker2", assume the command:
ssh firebolt@192.168.4.195

## Repository Folder Structure

This repository contains two sets of top-level directories, each tied to a different cluster generation:

### Gen 1 (homelab / "prod gen 1")
- `apps/` — application workloads deployed to the gen 1 cluster
- `infrastructure/` — infrastructure components (controllers, operators, etc.) for the gen 1 cluster

### Gen 2 (prod gen 2 & non-prod gen 2)
- `applications/` — application workloads deployed to gen 2 clusters
- `infra/` — infrastructure components for gen 2 clusters

When I refer to a folder like `apps/` or `infrastructure/`, assume gen 1. When I refer to `applications/` or `infra/`, assume gen 2.

## Cluster Notes

- Workers run containerd
- Access is via SSH keys (no passwords)
