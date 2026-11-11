# Secrets - GH PAT

The purpose of this document is to explain how access to GitHub is managed.

## Overview

A GH PAT (personal access token) is used to connect ARC `actions-runner-controller` to github.

A secret must exist in the `arc` namespace with the name `controller-manager` with the key `github_token`

>[!TIP]
> Following [this documentation](https://github.com/actions/actions-runner-controller/blob/master/docs/authenticating-to-the-github-api.md#deploying-using-pat-authentication) you can see the recommended command to create a secret and the required scopes!

In this cluster, I am using 1Password to manage this secret so that rotating it will be easy!

Tokens can be setup here: https://github.com/settings/tokens