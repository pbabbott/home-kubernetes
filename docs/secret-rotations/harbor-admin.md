# Secrets - Harbor Administration

The purpose of this document is to explain how one can rotate and manage the secrets for the habor application in my homelab.

## Overview

There are two secrets needed for Harbor.

The first is the harbor admin password which is needed in the `HelmRelease`.  There must exist a secret in the `harbor` namespace called `harbor-admin-secret` with a key of `password` inside.

The other secret is for harbor to connect to an external postgres sql database.  There must exist a secret in the `harbor` namespace called `harbor-db-secret` with a key of `password` inside.  The username is hard-coded in the config as a limitation of the the helm chart.

## Rotation instructions

#### Admin password

This one is easy. Just update the secret using harbor ui, and then update it in the 1password ui, and wait for things to sync!

The db password is just the admin password for postgres.  Rotation is presently handled via the same 1password process.  

TODO: Write a process document for updating postgres db password.
TODO: I should make each service use its own username/password for postgres.