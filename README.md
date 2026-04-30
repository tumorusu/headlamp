# headlamp

Sanitized public Headlamp operational toolkit.

This repository contains only **safe-to-publish** material derived from a larger internal operational effort:

- generic automation templates for refreshing a shared Headlamp kubeconfig
- generic automation templates for updating Git-managed manifests
- a public Kubescape image mirror list
- implementation notes that are useful outside the original environment

Excluded from this public repo:

- internal hostnames and jump-host details
- internal cluster names and URLs
- internal registry names
- kubeconfigs, tokens, logs, and backups
- environment-specific procedures that would expose operational details

## Contents

- `templates/headlamp_refresh_generate_artifacts.template.sh`
- `templates/headlamp_refresh_update_remote_repo.template.sh`
- `docs/kubescape-images-to-mirror-update-2026-04-30.txt`
- `docs/headlamp-public-summary-2026-04-30.txt`

## Usage

Review the template scripts and replace the placeholder variables with values appropriate for your environment before use.
