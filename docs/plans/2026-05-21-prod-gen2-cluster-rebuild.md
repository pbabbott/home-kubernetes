# Prod Gen2 Cluster Rebuild Plan

**Context:** `/dev/sdb` on tfpc1 (192.168.6.24) suffered a hardware failure (bad sector 293667072). Root cause traced to Proxmox host: the physical 1.8T SSD (`CT2000BX500SSD1`, `/dev/sda` on Proxmox host `192.168.4.192`) is failing with `DID_BAD_TARGET` I/O errors. This SSD backs the entire `longhorn-ssd` Proxmox storage pool, which is currently **inactive**. etcd data dir was on a volume from this pool → etcd crash-looped → apiserver down → cluster unresponsive. Decision: replace physical SSD, then rebuild from scratch via home-playbooks + fresh Flux bootstrap.

---

## Pre-Rebuild: Hardware (REQUIRED FIRST)

The `longhorn-ssd` Proxmox storage pool is currently **inactive** due to failures on its backing disk. The disk may need replacing or may just need reseating — investigate before buying hardware.

- Proxmox host: `192.168.4.192`
- Suspect disk: `/dev/sda` — `CT2000BX500SSD1`, serial `2450E99992DB`, 1.8Tjj
- LVM VG on it: `vg_ssd` → Proxmox storage pool `longhorn-ssd`
- All affected VMs (prod gen2 + nonprod gen2 all have 256G disks from this pool):
  - VM 204 (tfpc1), 205 (tfpw1), 206 (tfpw2), 207 (tfpw3)
  - VM 301 (tfnpc1), 302 (tfnpw1), 303 (tfnpw2), 304 (tfnpw3)

**Known failures on sda:**
- LVM PV label area (sda1 offset 0) unreadable → `vg_ssd` won't activate on reboot/rescan
- Bad sector at LBA 293667072 inside the thin pool (caused VM 204's etcd disk to fail)
- Backup GPT table corrupt
- dmesg: `DID_BAD_TARGET` at sectors 0 and 2048 (host-level error — could be cable/controller, not necessarily dead disk)
- SMART self-reports: OK

**Step 1 — Diagnose before replacing:**
1. Power down Proxmox host
2. Reseat the SATA cable on the 1.8T drive (or move to a different SATA port)
3. Boot and run:
   ```bash
   smartctl -t short /dev/sda && sleep 120 && smartctl -a /dev/sda
   pvs /dev/sda1   # if this now works, vg_ssd may be recoverable
   ```
4. If `pvs` reads the PV label successfully → try `vgchange -ay vg_ssd` and `pvesm set longhorn-ssd --disable 0`
5. If `pvs` still fails → replace the drive

**Step 2 — If replacing:**
1. Physically replace the 1.8T SATA SSD
2. On Proxmox host, recreate the LVM thin pool:
   ```bash
   pvcreate /dev/sda1
   vgcreate vg_ssd /dev/sda1
   lvcreate -l 100%FREE --thinpool data vg_ssd
   pvesm set longhorn-ssd --disable 0
   ```
3. Verify `pvesm status` shows `longhorn-ssd` as active
4. Proceed with VM recreation via playbooks

---

## Changes Needed in home-playbooks

### 1. etcd data directory — do NOT use `/mnt/ssd`

The `kubeadm-config.yml.j2` or equivalent must set etcd's data dir to `/var/lib/etcd` (on sda), not `/mnt/ssd/etcd`.

In `kubeadm-config.yml.j2`, ensure this stanza exists under `ClusterConfiguration`:

```yaml
etcd:
  local:
    dataDir: /var/lib/etcd
```

If sdb is replaced and remounted at `/mnt/ssd`, it is fine to use again — but verify it is healthy before doing so.

---

### 2. Calico CNI — add installation step to playbooks

Calico was **not** in the playbooks. It was installed manually outside of Ansible. Add a playbook step (after kubeadm init) to install the Tigera Operator + Installation CR.

**Calico version in use:** `v3.27.3`  
**Pod CIDR:** `10.244.0.0/16`

```bash
# Step A: Install Tigera Operator
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.3/manifests/tigera-operator.yaml

# Step B: Apply Installation CR
kubectl apply -f - <<EOF
apiVersion: operator.tigera.io/v1
kind: Installation
metadata:
  name: default
spec:
  calicoNetwork:
    ipPools:
    - blockSize: 26
      cidr: 10.244.0.0/16
      encapsulation: VXLANCrossSubnet
      natOutgoing: Enabled
      nodeSelector: all()
---
apiVersion: operator.tigera.io/v1
kind: APIServer
metadata:
  name: default
spec: {}
EOF
```

Wait for all calico-node pods to be Running before proceeding.

---

### 3. CoreDNS — handled by kubeadm (no change needed)

`kubeadm init` deploys CoreDNS automatically. The custom Corefile (forwarding to `192.168.4.144`, NAS host entry for `192.168.4.124 nas.local.abbottland.io`) should already be applied via the playbook's `coredns-corefile.j2`. Verify this step runs after init.

---

## Post-Playbook Steps (in order)

After a clean `kubeadm init` + workers joined + Calico running:

### Step 1 — Bootstrap Flux

From the dev container (`/workspaces/home-kubernetes`):

```bash
kubectx prod-gen2

flux bootstrap git \
  --url=ssh://git@github.com/pbabbott/home-kubernetes \
  --branch=main \
  --private-key-file=/home/vscode/.ssh/id_ed25519 \
  --path=clusters/prod-gen2
```

When prompted `"Please give the key access to your repository?"` → answer `y`.  
The deploy key (`ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICXAvekUOBzKDyY3uhjjP/yJvStN5Vjtm2HrLBGzRu01`) is already registered on the GitHub repo — no need to re-add.

Full procedure: `docs/dev-guide-flux-bootstrap.md`

### Step 2 — Restore kubeadm:cluster-admins binding

Fresh etcd requires this binding to be recreated (kubeadm v1.29+ uses `O=kubeadm:cluster-admins` instead of `O=system:masters`). If `kubectl get nodes` returns Forbidden, use the super-admin kubeconfig on tfpc1:

```bash
ssh firebolt@192.168.6.24
export KUBECONFIG=/etc/kubernetes/super-admin.conf
sudo -E kubectl create clusterrolebinding kubeadm:cluster-admins \
  --clusterrole=cluster-admin \
  --group=kubeadm:cluster-admins
```

Consider adding this as an Ansible task post-kubeadm-init to avoid the footgun.

### Step 3 — Set up etcd snapshot backups to NFS

Add a root cron on tfpc1 to snapshot etcd hourly:

```bash
# /etc/cron.d/etcd-backup
0 * * * * root ETCDCTL_API=3 etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/healthcheck-client.crt \
  --key=/etc/kubernetes/pki/etcd/healthcheck-client.key \
  snapshot save /mnt/nfs-backup/etcd/etcd-$(date +%Y%m%dT%H%M%S).db \
  && find /mnt/nfs-backup/etcd -name '*.db' -mtime +3 -delete
```

NFS backup target: `192.168.4.124:/volume1/Backups/longhorn-prod` (or a dedicated etcd subdir).  
Mount the NFS share at `/mnt/nfs-backup` or adjust path.

---

## Cluster Reference (do not change)

| Item | Value |
|------|-------|
| Pod CIDR | `10.244.0.0/16` |
| Service CIDR | `10.96.0.0/12` |
| Cluster DNS IP | `10.96.0.10` |
| Cluster domain | `cluster.local` |
| Calico version | `v3.27.3` |
| k8s version | `v1.35.3` |
| Controller node | `tfpc1` — `192.168.6.24` |
| Worker nodes | `tfpw1-3` — `192.168.6.25-27` |
| Upstream DNS | `192.168.4.144` |
| NAS IP | `192.168.4.124` |
