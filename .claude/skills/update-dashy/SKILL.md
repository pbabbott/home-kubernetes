---
name: update-dashy
description: Update dashy dashboard configuration 
---

A new item has been added to the dashy configmap (applications/dashy/templates/configmap.yaml)

> [!IMPORTANT]
> Do NOT make https://dashy.local.non-prod.abbottland.io or https://dashy.local.abbottland.io into template strings as they are meant to be static

Now we must accomplish the following:

- [ ] Ensure the new item added to the configmap uses a templatized value (something like {{ .Values.urls.prometheus }})\
- [ ] Make sure a value for it exists in applications/base/dashy/values.yaml
- [ ] Make sure a value exists for non-prod-gen2 (applications/non-prod-gen2/dashy/helmrelease.yaml)
- [ ] Make sure a value exists for prod-gen2 (applications/prod-gen2/dashy/helmrelease.yaml)

