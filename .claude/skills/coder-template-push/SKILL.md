---
name: coder-template-push
description: Upload a Coder template via API — pack tar, upload file, create version with variable overrides, publish or create workspace
---

Use when editing Coder template Terraform files and needing to publish without the Coder CLI.

## IDs (prod)

```
ORG_ID=8aa3e329-80eb-4a8c-a674-2125c4788dc2
BASE=https://coder.local.abbottland.io
TOKEN=$(grep CODER_TOKEN /workspaces/home-kubernetes/.env | cut -d= -f2)
```

Known template IDs:
- `kubernetes-devcontainer`: `9ee07212-25ee-4288-a1f3-1171bc89ff75`
- `kubernetes-ubuntu`: `06e4058e-58f5-4534-894a-9181c7b9d945`

## Step 1: Pack template

```bash
tar -cf /tmp/template.tar -C /tmp/my-template main.tf
# Include README.md if present
```

## Step 2: Upload file

```bash
FILE_ID=$(curl -s -X POST \
  -H "Coder-Session-Token: $TOKEN" \
  -H "Content-Type: application/x-tar" \
  --data-binary @/tmp/template.tar \
  "$BASE/api/v2/files?content_type=application/x-tar" | python3 -c "import sys,json; print(json.load(sys.stdin)['hash'])")
echo "File: $FILE_ID"
```

## Step 3: Create template version

For an **existing** template (new version):
```bash
VERSION=$(curl -s -X POST \
  -H "Coder-Session-Token: $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"storage_method\": \"file\",
    \"file_id\": \"$FILE_ID\",
    \"provisioner\": \"terraform\",
    \"template_id\": \"<template_id>\",
    \"message\": \"<change description>\",
    \"user_variable_values\": [
      {\"name\": \"namespace\", \"value\": \"coder-workspaces\"},
      {\"name\": \"use_kubeconfig\", \"value\": \"false\"}
    ]
  }" \
  "$BASE/api/v2/organizations/$ORG_ID/templateversions") && \
echo "$VERSION" | python3 -c "import sys,json; v=json.load(sys.stdin); print('Version:', v['id'], '| Status:', v['job']['status'])"
```

For a **new** template (no `template_id`): omit the `template_id` field, then create the template separately (Step 5).

## Step 4: Wait for import

```bash
VERSION_ID=<from step 3>
until curl -s -H "Coder-Session-Token: $TOKEN" \
  "$BASE/api/v2/templateversions/$VERSION_ID" | \
  python3 -c "import sys,json; v=json.load(sys.stdin); s=v['job']['status']; print(s); exit(0 if s in ('succeeded','failed') else 1)"; do sleep 3; done
```

Verify variables resolved correctly:
```bash
curl -s -H "Coder-Session-Token: $TOKEN" \
  "$BASE/api/v2/templateversions/$VERSION_ID/variables" | \
  python3 -c "import sys,json; [print(v['name'], '->', v['value']) for v in json.load(sys.stdin)]"
```

## Step 5: Create new template (if brand new)

```bash
curl -s -X POST \
  -H "Coder-Session-Token: $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"name\": \"kubernetes-ubuntu\",
    \"display_name\": \"Kubernetes (Ubuntu)\",
    \"description\": \"Ubuntu workspace in Kubernetes.\",
    \"icon\": \"/icon/k8s.png\",
    \"template_version_id\": \"$VERSION_ID\"
  }" \
  "$BASE/api/v2/organizations/$ORG_ID/templates" | \
  python3 -c "import sys,json; v=json.load(sys.stdin); print('Template:', v.get('id'), v.get('name'))"
```

## Step 6: Create workspace with specific version

```bash
curl -s -X POST \
  -H "Coder-Session-Token: $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"name\": \"<workspace-name>\",
    \"template_version_id\": \"$VERSION_ID\",
    \"rich_parameter_values\": [
      {\"name\": \"repo\", \"value\": \"owner/repo\"}
    ]
  }" \
  "$BASE/api/v2/organizations/$ORG_ID/members/me/workspaces" | \
  python3 -c "import sys,json; v=json.load(sys.stdin); b=v.get('latest_build',{}); print('Workspace:', v.get('id')); print('Build:', b.get('id'))"
```

## Gotchas

- `user_variable_values` must be set at version creation — cannot be patched after. If wrong, create a new version.
- Terraform state persists across workspace rebuilds. If a build used a wrong namespace, **delete the workspace entirely** before rebuilding with a new version — otherwise state drives the old values.
- Template version `PATCH /templates/:id` with `active_version_id` silently ignores the change if the version was created without `user_variable_values` set correctly.
- `file_id` returned from upload is a UUID hash — reuse it for multiple version attempts.
