# prod-gen2: external-dns / external-dns-pihole frequent restarts

Date: 2026-11-08. Cluster: `prod-gen2` (gen3 compared). Read-only investigation, **no changes were made**; no fix is applied or scheduled. Notes kept for later.
Follows up `2026-10-12-prod-gen2-high-restarts.md` (which already saw two external-dns restarts) and the loose end in `docs/plans/2026-11-08-gen2-to-gen3-migration.md`.

## Summary

Both Deployments (chart `external-dns` 1.15.0, image `v0.15.0`) restart because **v0.15.0 exits on any non-`SoftError` sync failure**: `Controller.Run` does `log.Fatalf("Failed to do run once: %v")` (verified in the v0.15.0 `controller/controller.go`). Any transient provider/DNS/API error becomes a process exit and a Kubernetes restart. It is not OOM, probes, or node trouble.

The *triggers* are several, all transient. One is fully evidenced (Pi-hole host unreachable via CoreDNS, 2026-11-05); the rest are inferred or from the earlier incident note.

Restarts at the time: `external-dns` (Cloudflare) 134 in 118d; `external-dns-pihole` 107 in 118d (pod replaced 2026-11-08 for the upsert-only change, so its history is gone).

## Evidence

**Last Cloudflare crash (2026-11-05 08:59:55Z), fully evidenced**
- `lastState`: Error, exit 1, ran 24s. Not 137, so not OOM.
- Last log: `level=fatal msg="Failed to do run once: HTTP request failed: Get \"https://api.cloudflare.com/client/v4/zones?per_page=50\": dial tcp: lookup api.cloudflare.com on 10.96.0.10:53: server misbehaving"`.
- gen2 CoreDNS forwards everything to one upstream, the Pi-hole (`forward . 192.168.4.144`). Its logs (kept back to 2026-09-30) show 4,638 `i/o timeout` errors, all against 192.168.4.144. Burst: continuous ~190/min from 08:39Z to 09:02Z on 2026-11-05 (~23 min). The pod crash-looped (with backoff) through it and the surviving container started 09:02:35Z, when timeouts stopped.
- Other CoreDNS timeout episodes: 2026-10-21 17Z (61), 2026-10-22 07Z (180); blips on Oct 12, 13, 17, 18, 20 and Nov 2, 3.
- Since 09:02Z on Nov 5 the pod made 4,975 syncs with zero errors; it also survived the 03:05Z control-plane stalls on Nov 6 and Nov 8.

**Other data points (from `2026-10-12-prod-gen2-high-restarts.md`)**
- 2026-10-07 14:46Z `external-dns`: fatal on Cloudflare HTTP 502 (same fatal path, provider-side).
- 2026-09-30 12:47Z `external-dns-pihole`: exit 255, healthy logs, killed externally; etcd restarted 12:46:57Z.

**Ruled out**
- Memory: peak working set ~23 MiB (Cloudflare) / ~22 MiB (Pi-hole) over the 3d Prometheus retention. No requests/limits set (BestEffort), so no OOM kill is possible by limit.
- Node: `tf-prod-k8s-worker-2` has no pressure conditions or events. Other pods there restart for leader-election reasons, not node trouble.
- Control-plane stalls (~03:05Z, tied to the Longhorn 03:00 backups in the Oct 12 note): they restarted apiserver/controller-manager/scheduler/tigera/CSI pods on Oct 26, Nov 6, Nov 8 but **not** external-dns once running.

**Limits of the evidence**
- Prometheus retention is 3 days (starts 2026-11-05 18:00Z), after the last restart. `lastState` exists only for the latest restart. Only the Nov 5 crash can be tied to a cause; the other ~130 are inference.
- The Pi-hole instance's old pod (107 restarts) and its exit codes are gone.

## Is it harmful?

No evidence of harm.
- Cloudflare: all 5 labelled hostnames have CNAMEs; no orphan records owned by external-dns.
- Pi-hole: 47 A records (45 + `podinfo-gen3` + `prometheus-gen3`); all 31 labelled routes present at 192.168.6.28; `nas.local` matches its DNSEndpoint.
- A restart can only delay an update by the length of the outage, and writes cannot succeed during the outage anyway. Upsert-only on the Pi-hole instance removes wrong-delete risk.

## Hypotheses (ranked)

1. **Pi-hole host (bananapi, 192.168.4.144) intermittently unreachable.** Cloudflare pod dies through CoreDNS lookups; Pi-hole pod dies on API calls. Confirmed for the 2026-11-05 Cloudflare crash; inferred for the Pi-hole pod. *Confirm:* bananapi `journalctl` and `/var/log/pihole/FTL.log` around 2026-11-05 08:39-09:02Z, 2026-10-21 17Z, 2026-10-22 07Z. (Not checked: needed SSH.)
2. **Provider-side transient errors** (e.g. Cloudflare 502 on 2026-10-07), same fatal path.
3. **apiserver/etcd events killing the container** (Pi-hole pod, 2026-09-30), plausibly related to the Longhorn 03:00 backup load documented in the Oct 12 note.

## Gen3

Same chart, image, args, no resource limits. Gen3 CoreDNS uses `forward . /etc/resolv.conf` (what the node resolver points to was not checked; if it is the Pi-hole, the Cloudflare instance has the same exposure once enabled in Phase 8). The Pi-hole instance depends only on the Pi-hole API. Pods were ~50 min old, 0 restarts, 0 CoreDNS timeouts: too little history to judge.

## Candidate fixes (NOT applied; undecided)

- Find the cause of the bananapi outages (hypothesis 1).
- Add a second CoreDNS upstream on gen2 (in `home-playbooks`, not this repo). Trade-off: a fallback such as 1.1.1.1 answers `*.local.abbottland.io` with NXDOMAIN while the Pi-hole is down.
- Hygiene in `infra/base/external-dns` (does not stop the restarts): add `resources` (requests cpu 10m / mem 48Mi, limit mem 128Mi) to both HelmReleases so pods are no longer BestEffort; optionally `dnsConfig.options: ndots=1` on the Cloudflare release to cut search-domain lookups to the Pi-hole (unproven; `dnsConfig` was not tested against chart 1.15.0 rendering).
- Check whether a newer external-dns release tolerates provider errors without exiting before relying on an upgrade.

## Commands used (read-only)

```bash
kc(){ kubectl --context prod-gen2 "$@"; }
kc -n external-dns describe pod -l app.kubernetes.io/instance=external-dns
kc -n external-dns logs <pod> --previous
kc -n kube-system logs <coredns-pod> --timestamps     # i/o timeout counts; note offsets switch -05:00 -> -06:00 on Nov 1
# Prometheus via port-forward svc/kube-prometheus-stack-prometheus (retention 3d)
```
Records were compared against HTTPRoutes labelled `external-dns-enabled` / `pihole-dns-enabled` and DNSEndpoints, via Cloudflare `GET dns_records` and Pi-hole `customdns&action=get`.
