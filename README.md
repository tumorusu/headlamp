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
- `templates/clusters.template.txt`
- `docs/kubescape-images-to-mirror-update-2026-04-30.txt`
- `docs/headlamp-public-summary-2026-04-30.txt`

## Usage

1. Copy `templates/clusters.template.txt` to a local working file such as `clusters.txt` and replace the sample names with your target clusters.
2. Review `templates/headlamp_refresh_generate_artifacts.template.sh` and set the required environment variables for your bastion host, jump host, service account, and binding.
3. Run the generate script with `CLUSTERS_FILE` pointing to your cluster list to produce a kubeconfig and ConfigMap artifact set.
4. Review `templates/headlamp_refresh_update_remote_repo.template.sh`, set the remote Git-managed repository path and connection variables, then copy the refreshed artifacts into that checkout.

Key inputs expected by the templates:

| Variable | Purpose |
| --- | --- |
| `CLUSTERS_FILE` | Path to the cluster list consumed by the generate script |
| `BASTION_HOST` | First SSH hop used to reach the environment |
| `JUMP_HOST` | Target host where `kubectl` and related tooling run |
| `TARGET_SERVICEACCOUNT` | Service account used for Headlamp access |
| `TARGET_BINDING` | ClusterRoleBinding inspected to discover the bound namespace |
| `TOKEN_DURATION` | Requested token lifetime for generated service-account tokens |
| `REPO_DIR` | Path to the Git-managed checkout updated by the sync script |
| `RAW_FILE_NAME` / `CONFIGMAP_FILE_NAME` | Local artifact names produced by the generate step |
| `REMOTE_RAW_FILE_NAME` / `REMOTE_CONFIGMAP_FILE_NAME` | Destination file names inside the remote Git-managed checkout |

The templates are intentionally generic. Replace placeholders and adjust file names and remote paths to match your environment before use. They now stop early if required placeholder values are still unchanged.
