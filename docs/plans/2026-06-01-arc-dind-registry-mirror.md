# ARC dind Runner — Docker Registry Pull-Through Cache

## Problem

Every dind runner pod spawns with an empty `var-lib-docker` emptyDir. Every job pulls
Docker image layers cold from the public internet. With 6 concurrent dind runners pulling
the same base images (e.g. `node:20`, `actions-runner:latest`), those layers are fetched
6× in parallel. Observed: **50 MB/s network peaks, 134 MB/s disk write peaks** from layer
extraction alone.

Harbor is already running in the cluster at `harbor.local.abbottland.io`. It supports
proxy cache projects that cache layers after the first pull — all subsequent pulls for the
same digest are served from Harbor's NAS-backed registry storage.

---

## Harbor Setup (prerequisite — manual, done once via Harbor UI)

Before any k8s or workflow changes, create proxy cache projects in Harbor:

1. **Admin → Registries → New Endpoint** — create one endpoint per upstream registry:
   - Name: `dockerhub-proxy`, URL: `https://registry-1.docker.io`, provider: Docker Hub
   - Name: `ghcr-proxy`, URL: `https://ghcr.io`, provider: GitHub Container Registry
   - Name: `gcr-proxy`, URL: `https://gcr.io`, provider: Google GCR (if needed)

2. **Projects → New Project** for each:
   - Name: `proxy-dockerhub`, check "Proxy Cache", target: `dockerhub-proxy`
   - Name: `proxy-ghcr`, check "Proxy Cache", target: `ghcr-proxy`
   - Set access level to **public** (anonymous pull, no auth needed in runners)

3. Verify pull works from inside the cluster:
   ```bash
   kubectl run test --rm -it --image=alpine --restart=Never -n arc-runners -- \
     docker pull harbor.local.abbottland.io/proxy-dockerhub/library/alpine:latest
   ```

---

## Changes Required in This Repository

### 1. Create `daemon.json` ConfigMap

New file: `applications/base/arc/arc-dind-daemon-configmap.yaml`

```yaml
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: arc-dind-daemon-config
  namespace: arc-runners
data:
  daemon.json: |
    {
      "registry-mirrors": [
        "https://harbor.local.abbottland.io/proxy-dockerhub"
      ],
      "mtu": 1450,
      "insecure-registries": []
    }
```

Note: `mtu: 1450` also fixes the dead `--mtu=1450` arg from the base HelmRelease that
was never reaching the daemon.

### 2. Rewrite `arc-runner-dind-amd64-helmrelease.yaml`

Remove `containerMode.type: dind` and the dead `containers[1]` block. Specify the full
dind initContainer setup manually under `template.spec.initContainers`, adding a
`/etc/docker` volume mount and a new configmap volume.

**Chart auto-injection lost when switching to `containerMode: {}`:**

When `containerMode.type: dind` is active the chart's `dind-runner-container` helper
automatically adds to the runner container:
- `DOCKER_HOST: unix:///var/run/docker.sock`
- `RUNNER_WAIT_FOR_DOCKER_IN_SECONDS: "120"`
- `volumeMount: dind-sock → /var/run`
- `volumeMount: work → /home/runner/_work`

These must be added explicitly to `template.spec.containers[0]` (the runner) when moving
to manual mode. The chart also auto-injects the `dind-sock` and `dind-externals` volumes —
these must also be explicit in `template.spec.volumes`.

Full diff of what changes in `arc-runner-dind-amd64-helmrelease.yaml` values:

```yaml
containerMode: {}   # was: type: dind

template:
  spec:
    initContainers:
      - name: init-dind-externals
        image: ghcr.io/falcondev-oss/actions-runner:latest   # match runner image
        command: ["cp", "-r", "/home/runner/externals/.", "/home/runner/tmpDir/"]
        volumeMounts:
          - name: dind-externals
            mountPath: /home/runner/tmpDir

      - name: dind
        image: docker:dind
        restartPolicy: Always
        args:
          - dockerd
          - --host=unix:///var/run/docker.sock
          - --group=$(DOCKER_GROUP_GID)
        env:
          - name: DOCKER_GROUP_GID
            value: "123"
        securityContext:
          privileged: true
        startupProbe:
          exec:
            command: [docker, info]
          initialDelaySeconds: 0
          failureThreshold: 24
          periodSeconds: 5
        resources:
          requests:
            cpu: "100m"
            memory: "512Mi"
          limits:
            cpu: "1000m"
            memory: "2Gi"
        volumeMounts:
          - name: work
            mountPath: /home/runner/_work
          - name: dind-sock
            mountPath: /var/run
          - name: dind-externals
            mountPath: /home/runner/externals
          - name: arc-dind-daemon-config
            mountPath: /etc/docker   # new — daemon.json injected here

    containers:
      - name: runner
        # ... existing env/resources/volumeMounts ...
        env:
          # add these (previously injected by chart's dind-runner-container helper):
          - name: DOCKER_HOST
            value: unix:///var/run/docker.sock
          - name: RUNNER_WAIT_FOR_DOCKER_IN_SECONDS
            value: "120"
          # ... existing env vars (CUSTOM_ACTIONS_RESULTS_URL, TURBO_API, TURBO_TOKEN) ...
        volumeMounts:
          # add these (previously injected by chart helper):
          - name: dind-sock
            mountPath: /var/run
          - name: work
            mountPath: /home/runner/_work
          # ... existing (pnpm-store) ...

    volumes:
      # new — must be explicit now that chart no longer injects them:
      - name: dind-sock
        emptyDir: {}
      - name: dind-externals
        emptyDir: {}
      # existing:
      - name: var-lib-docker
        emptyDir: { sizeLimit: 20Gi }
      - name: work
        emptyDir: { sizeLimit: 10Gi }
      - name: pnpm-store
        persistentVolumeClaim:
          claimName: arc-pnpm-store
      # new:
      - name: arc-dind-daemon-config
        configMap:
          name: arc-dind-daemon-config
```

### 3. Add ConfigMap to kustomization

`applications/base/arc/kustomization.yaml` — add `arc-dind-daemon-configmap.yaml` to
resources.

### 4. Remove dead `containers[1]` dind block from base HelmRelease

The `containers[1]` block (`name: dind, args: ["--mtu=1450"]`) in
`arc-runner-dind-amd64-helmrelease.yaml` is currently silently ignored by the chart on
k8s ≥ 1.29. Remove it when switching to manual initContainers to avoid confusion.

---

## Changes Required in GitHub Actions Workflows

**None.** The daemon mirror is fully transparent. All `docker pull` and `docker build`
commands hit Harbor automatically without any workflow changes.

The one exception: if workflows push images to `docker.io` or `ghcr.io`, those pushes are
unaffected — mirrors only intercept pulls.

---

## Verification

```bash
# Confirm daemon.json is mounted and mirror is active
kubectl exec -n arc-runners <dind-pod> -c dind -- docker info | grep -A5 "Registry Mirrors"

# Trigger a job and watch Harbor proxy-dockerhub project for new artifacts
# Harbor UI → proxy-dockerhub → Repositories — should populate after first pull

# Compare job duration before/after for dind jobs that pull large base images
```

---

## Expected Impact

| Metric | Before | After |
|--------|--------|-------|
| Network RX per cold pull | full image size from internet | ~0 after first pull (LAN speed) |
| Disk write (layer extraction) | 134 MB/s peak | same first pull, near-zero on cache hit |
| Job time reduction | — | 30–90s saved per job on cache-hit pulls |
| Concurrent pull amplification | N runners × image size | 1× from internet, N× LAN to Harbor |
