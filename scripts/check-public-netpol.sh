#!/usr/bin/env bash
# Offline check (no cluster needed): every workload behind a public HTTPRoute (parent Gateway `istio-ingress-public`)
# must be covered by a NetworkPolicy that declares Egress and has no open-ended egress (a rule with no `to`, or 0.0.0.0/0).
# Renders apps/prod-gen3 the way Flux does. Rule and rationale: CLAUDE.md "Rules of the road", workload-conventions.md.
set -euo pipefail
cd "$(dirname "$0")/.."
for t in kubectl jq yq; do command -v "$t" >/dev/null || { echo "needs $t" >&2; exit 2; }; done

read -r -d '' PROG <<'JQ' || true
# true when every key/value in $a is also in $b
def subset($a; $b): all($a | to_entries[]; . as $e | $b[$e.key] == $e.value);

. as $all
| [$all[] | select(.kind == "NetworkPolicy")] as $np
| [$all[] | select(.kind == "Service")] as $svc
| [ $all[]
    | select(.kind == "HTTPRoute" and any(.spec.parentRefs[]?; .name == "istio-ingress-public"))
    | .metadata.namespace as $ns | .metadata.name as $route
    | .spec.rules[].backendRefs[]?
    | {ns: $ns, route: $route, svc: .name} ] | unique[] as $b
| ($svc | map(select(.metadata.namespace == $b.ns and .metadata.name == $b.svc)) | first) as $s
| ($np | map(select(.metadata.namespace == $b.ns))) as $nsnp
| (
    if $s == null then
      # Service comes from a Helm chart so it is not in the render: require some policy in the namespace
      if ($nsnp | length) == 0
      then {msg: "\($b.ns)/\($b.route): backend \($b.svc) has no NetworkPolicy in namespace \($b.ns)", pols: []}
      else {msg: null, pols: $nsnp} end
    elif ($s.spec.selector // {}) == {} then
      {msg: null, pols: []}   # selector-less Service (host proxy): no pods to protect
    else
      ($nsnp | map(select(subset(.spec.podSelector.matchLabels // {}; $s.spec.selector)))) as $m
      | if ($m | length) == 0
        then {msg: "\($b.ns)/\($b.route): no NetworkPolicy selects the pods behind Service \($b.svc)", pols: []}
        else {msg: null, pols: $m} end
    end
  )
| (.msg // empty),
  (.pols[]
   | (if ((.spec.policyTypes // []) | index("Egress")) == null
      then "\(.metadata.namespace)/\(.metadata.name): policyTypes must list Egress (egress is only denied by default when declared)"
      else empty end),
     (.metadata as $m
      | (.spec.egress // [])[]
      | select(((.to // []) | length) == 0 or any(.to[]?; .ipBlock.cidr == "0.0.0.0/0"))
      | "\($m.namespace)/\($m.name): open-ended egress rule; scope each rule to a destination and port"))
JQ

problems=$(kubectl kustomize --load-restrictor=LoadRestrictionsNone apps/prod-gen3 \
  | yq -o=json -I=0 '.' | jq -s -r "$PROG" | sort -u)

if [ -n "$problems" ]; then
  echo "Public workloads must be locked down at the network level (see CLAUDE.md, workload-conventions.md):" >&2
  sed 's/^/  - /' <<<"$problems" >&2
  exit 1
fi
echo "public NetworkPolicy check passed" >&2
