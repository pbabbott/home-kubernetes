# home-playbooks: Move etcd off SSD

**Goal:** etcd data dir must live on the host OS disk (`/var/lib/etcd`), not `/mnt/ssd/etcd`. The SSD-backed volume caused etcd to crash-loop when `longhorn-ssd` went inactive.

---

## Change Required

In `home-playbooks`, find `kubeadm-config.yml.j2` (or wherever kubeadm ClusterConfiguration is templated).

Add/update the `etcd` stanza under `ClusterConfiguration`:

```yaml
etcd:
  local:
    dataDir: /var/lib/etcd
```

`/var/lib/etcd` is on the root disk (not `/mnt/ssd`), so a storage pool failure won't take down the control plane.

---

## Verify After Playbook Run

```bash
ssh firebolt@192.168.6.24 "sudo cat /etc/kubernetes/manifests/etcd.yaml | grep data-dir"
```

Expected: `--data-dir=/var/lib/etcd`

Also confirm etcd pod is healthy:

```bash
kubectl -n kube-system get pod -l component=etcd
```
