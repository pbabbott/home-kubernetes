# Infrastructure Overview

This repository is deployed on a small Kubernetes cluster.

## Kubernetes Nodes

There are three worker nodes. When I refer to them, use the following aliases:

- worker1 → ssh firebolt@192.168.4.194
- worker2 → ssh firebolt@192.168.4.195
- worker3 → ssh firebolt@192.168.5.81
- controller → ssh firebolt@192.168.4.193

If I ask to "SSH into worker2", assume the command:
ssh firebolt@192.168.4.195

## Cluster Notes

- Workers run containerd
- Access is via SSH keys (no passwords)
