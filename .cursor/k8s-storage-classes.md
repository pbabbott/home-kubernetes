# Kubernetes Storage Classes Summary

Overview of available storage classes in the cluster for creating PersistentVolumeClaims (PVCs).

## Storage Classes

### 1. longhorn (Default)

**Type:** Fast SSD Storage  
**Provisioner:** `driver.longhorn.io`  
**Reclaim Policy:** Delete | **Volume Expansion:** Enabled | **Binding Mode:** Immediate

**Configuration:**
- 3 replicas for high availability
- ext4 filesystem
- v1 data engine

**Use Cases:** Databases, caches, applications requiring fast I/O and low latency.

**Example:**
```yaml
spec:
  storageClassName: longhorn  # or omit to use default
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: 10Gi
```

---

### 2. longhorn-static

**Type:** Fast SSD Storage (Static Provisioning)  
**Provisioner:** `driver.longhorn.io`  
**Reclaim Policy:** Delete | **Volume Expansion:** Enabled | **Binding Mode:** Immediate

**Configuration:**
- Uses default Longhorn settings
- Minimal parameters (staleReplicaTimeout: 30)

**Use Cases:** Static volume provisioning where you manually create PersistentVolumes and bind them to PVCs. Used when you need pre-existing volumes with specific configurations.

**Example:**
```yaml
# First create a PV, then bind to PVC
spec:
  storageClassName: longhorn-static
  volumeName: my-precreated-pv
  accessModes: [ReadWriteMany]
  resources:
    requests:
      storage: 2Gi
```

---

### 3. nas-storage

**Type:** Network Attached Storage (NFS)  
**Provisioner:** `cluster.local/nas-storage-nfs-subdir-external-provisioner`  
**Reclaim Policy:** Delete | **Volume Expansion:** Enabled | **Binding Mode:** Immediate

**Configuration:**
- Archives data on PVC deletion (`archiveOnDelete: true`)
- Path pattern: `${.PVC.namespace}-${.PVC.name}`

**Use Cases:** Large datasets, media files, backups, shared storage. Slower than Longhorn but suitable for capacity-intensive workloads.

**Example:**
```yaml
spec:
  storageClassName: nas-storage
  accessModes: [ReadWriteMany]  # NFS supports multiple readers/writers
  resources:
    requests:
      storage: 100Gi
```

---

## Quick Reference

| Storage Class | Type | Speed | Use Case |
|--------------|------|-------|----------|
| **longhorn** (default) | SSD Block | Fast | Dynamic provisioning, databases, fast I/O |
| **longhorn-static** | SSD Block | Fast | Static provisioning, pre-created volumes |
| **nas-storage** | NFS Network | Slower | Large files, media, backups, shared storage |

## Selection Guide

- **Use `longhorn`** for: Fast I/O, databases, dynamic volume creation (default)
- **Use `longhorn-static`** for: Pre-created volumes, static provisioning scenarios
- **Use `nas-storage`** for: Large capacity, media files, backups, ReadWriteMany access

---

*Last updated: Generated from cluster inspection*
