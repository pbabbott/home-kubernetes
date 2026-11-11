# New cluster checklist (Flux Operator)

1. Copy `clusters/<existing>/` to `clusters/<new>/`; set `sync.path: clusters/<new>` in `flux-system/flux-instance.yaml`.
2. Add `apps/<new>/` overlays on `apps/base/` (add `crds/`, `infra/` and `00-crds-ks`/`01-infra-ks` later, with `dependsOn` chaining).
3. Merge to `main`.
4. From `home-playbooks`, run the cluster's flux-operator playbook (e.g. `playbooks/kubernetes-gen3/05-flux-operator.yml`);
   add the deploy key at github.com/pbabbott/home-kubernetes/settings/keys if needed.
5. Verify: `flux get all -A --context <new>`.

`prod-gen3` currently runs only podinfo.
