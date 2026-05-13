# 1Password Operator (OnePasswordItem) Reference

The `onepassword-connect` operator in `op-connect` namespace watches `OnePasswordItem` CRDs and creates Kubernetes secrets from 1Password vault items.

## How It Works

1. `OnePasswordItem` CRD references a vault item by path: `vaults/<VaultName>/items/<ItemTitle>`
2. Operator calls op-connect API to fetch the item
3. Creates a `Secret` in the same namespace with field names as keys, field values as values
4. Secret keys match the **field labels** in 1Password exactly (e.g., a field labeled `pw` → key `pw`, not `password`)

## Checking Status

```bash
# Check if item was found and secret created
kubectl get onepassworditems <name> -n <namespace> -o jsonpath='{.status}'

# Ready = True means secret was created
# Ready = False with message = item not found or field mismatch
```

## Force Reconcile

Operator polls on its own interval. To force immediate reconcile:

```bash
kubectl annotate onepassworditems <name> -n <namespace> \
  "operator.1password.io/last-updated=$(date -Iseconds)" --overwrite
```

## Common Errors

**"No items found with identifier X"**  
The item title in 1Password must match the `itemPath` exactly (case-sensitive). Check the title via op-connect API (see `reference-op-connect-api-access.md`).

**"couldn't find key `password` in Secret"**  
Pod referencing secret with wrong key name. Check actual secret keys:
```bash
kubectl get secret <name> -n <namespace> -o jsonpath='{.data}' | python3 -c "import json,sys; [print(k) for k in json.load(sys.stdin)]"
```
Key names come from 1Password field labels, not field types. A password field labeled `pw` creates key `pw`.

**Secret not created after item exists in 1Password**  
Operator may have cached the "not found" state. Force reconcile via annotation (see above).

## Example OnePasswordItem

```yaml
apiVersion: onepassword.com/v1
kind: OnePasswordItem
metadata:
  name: pihole-admin-secret
  namespace: external-dns
spec:
  itemPath: "vaults/Homelab/items/pihole.local.abbottland.io (bananapi)"
```

Results in a Secret named `pihole-admin-secret` with keys matching each field label in the 1Password item.

## Checking What's in a Secret

```bash
kubectl get secret <name> -n <namespace> -o jsonpath='{.data.<key>}' | base64 -d
```

## Related Docs

- `docs/reference-op-connect-api-access.md` — how to query the op-connect API directly to browse vault items
