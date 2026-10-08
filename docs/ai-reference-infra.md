# Infrastructure Reference

## Clusters

Three Kubernetes clusters:

- **Prod gen 1** — being shut down
- **Prod gen 2** — active (WIP)
- **Non-prod gen 2** — active (WIP)

### Prod gen 2 SSH targets
```
tfpc1  → ssh firebolt@192.168.6.24
tfpw1  → ssh firebolt@192.168.6.25
tfpw2  → ssh firebolt@192.168.6.26
tfpw3  → ssh firebolt@192.168.6.27
```

### Non-prod gen 2 SSH targets
```
tfnpc1 → ssh firebolt@192.168.6.31
tfnpw1 → ssh firebolt@192.168.6.32
tfnpw2 → ssh firebolt@192.168.6.33
tfnpw3 → ssh firebolt@192.168.6.34
```

### Prod gen 1 SSH targets
```
controller → ssh firebolt@192.168.4.193
worker1    → ssh firebolt@192.168.4.194
worker2    → ssh firebolt@192.168.4.195
worker3    → ssh firebolt@192.168.5.81
dumbledore → ssh albus@192.168.4.157
```

### Proxmox host

All gen 2 hosts are VMs on this host: `ssh root@192.168.4.192`

### HAProxy (gen 2 load balancer)

Sits in front of prod gen 2 and non-prod gen 2. Stats page: [http://192.168.6.28:8404/](http://192.168.6.28:8404/)

## DNS and Ingress Hostnames

Wildcard patterns for gen 2 clusters (HTTPRoute `hostnames`, TLS certs, split-horizon DNS):

| Pattern | Cluster | Visibility |
| --- | --- | --- |
| `*.abbottland.io` | Prod gen 2 | Public |
| `*.local.abbottland.io` | Prod gen 2 | Internal |
| `*.non-prod.abbottland.io` | Non-prod gen 2 | Public |
| `*.local.non-prod.abbottland.io` | Non-prod gen 2 | Internal |

`*.local.*` = internal. Without `local` = public.

## Flux Layering (Gen 2)

Numbered `Kustomization` files under `clusters/<cluster>/`:

| File | Path | Depends on |
| --- | --- | --- |
| `00-crds-ks.yaml` | `./crds/<cluster>/` | — |
| `01-infra-ks.yaml` | `./infra/<cluster>/` | crds-ks |
| `02-apps-ks.yaml` | `./applications/<cluster>/` | infra-ks |

Add CRD-related material under `crds/<cluster>/` so it applies before infra and apps. Don't rely on app charts to own CRDs when this repo's layering should own the cluster API surface.

## Longhorn Backup Targets

NFS host: `192.168.4.124`, base export: `/volume1/Backups/`

| Cluster | Backup target |
| --- | --- |
| Non-prod gen 2 | `nfs://192.168.4.124:/volume1/Backups/longhorn-nonprod` |
| Prod gen 2 | `nfs://192.168.4.124:/volume1/Backups/longhorn-prod` |

## Cluster Notes

- Workers run containerd
- SSH key auth only (no passwords)
