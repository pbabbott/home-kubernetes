# Secrets - Longhorn NAS Backup Credentials

THe purpose fo this document is to explain how one can rotate and manage the credentials for harbor to connect to my NAS for backups.

## Overview

Longhorn is configured to connect to my NAS via CIFS/SMB.  This is accomplished by using a secret called `cifs-secret`.  The secret is provisioned via a `OnePasswordItem` which pulls the entry from 1Password with the same name.

This is just the same credential that I use to log into my NAS.  That is, whenever I update the OnePasswordItem: `asustor.local.abbottland.io (Asustor NAS) - pabbott`, then I'll want to also update `cifs-secret`

### Rotation Instructions

This is pretty straight forward. I just need to log into my ASUSTOR NAS and then update my password.  Then I need to update both 1password items so that backups work, and so that i have a copy of my password stored for logging into the web ui.