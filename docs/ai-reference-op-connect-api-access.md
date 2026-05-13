# Accessing 1Password Connect API

op-connect runs in `op-connect` namespace. Connect API is on port 8080 (not 8081 — that's sync).

## Quick Reference

```bash
# 1. Port-forward the connect-api
kubectl port-forward -n op-connect svc/onepassword-connect 18080:8080 &
PF_PID=$!

# 2. Extract token
OP_TOKEN=$(kubectl get secret -n op-connect op-credentials -o jsonpath='{.data.token}' | base64 -d)

# 3. List vaults
curl -s -H "Authorization: Bearer $OP_TOKEN" http://localhost:18080/v1/vaults

# 4. List items in a vault (get vault ID from step 3)
curl -s -H "Authorization: Bearer $OP_TOKEN" \
  http://localhost:18080/v1/vaults/<VAULT_ID>/items \
  | python3 -c "import json,sys; [print(i['id'], i['title']) for i in json.load(sys.stdin)]"

# 5. Get a specific item
curl -s -H "Authorization: Bearer $OP_TOKEN" \
  http://localhost:18080/v1/vaults/<VAULT_ID>/items/<ITEM_ID> \
  | python3 -m json.tool

# 6. Kill port-forward when done
kill $PF_PID
```

## Known Vault IDs

| Vault | ID |
|-------|----|
| Homelab | `fkkvro6akbbm2po5qvh6iask2a` |

## Notes

- Token is in `secret/op-credentials` under key `token` (not `1password-credentials.json`)
- `wget` and `curl` are NOT in the connect-api container — query from outside via port-forward
- Items are synced by the operator; `OnePasswordItem` CRD triggers secret creation
- If an `OnePasswordItem` fails with "No items found", the title in 1Password must match exactly
