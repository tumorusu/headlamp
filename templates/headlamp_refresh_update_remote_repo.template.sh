#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ARTIFACT_DIR="${1:-$SCRIPT_DIR/refresh-output/latest}"
REPO_DIR="${REPO_DIR:-<gitops-repo-path>}"
BASTION_HOST="${BASTION_HOST:-<bastion-host>}"
JUMP_HOST="${JUMP_HOST:-<jump-host>}"
RAW_FILE_NAME="${RAW_FILE_NAME:-headlamp-kubeconfig.yaml}"
CONFIGMAP_FILE_NAME="${CONFIGMAP_FILE_NAME:-headlamp-configmap.yaml}"
REMOTE_RAW_FILE_NAME="${REMOTE_RAW_FILE_NAME:-headlamp-kubeconfig.yaml}"
REMOTE_CONFIGMAP_FILE_NAME="${REMOTE_CONFIGMAP_FILE_NAME:-headlamp-configmap.yaml}"

require_real_value() {
  local name="$1"
  local value="$2"

  if [[ -z "$value" || "$value" == \<* ]]; then
    echo "Set $name to a real value before running this template." >&2
    exit 1
  fi
}

if [[ ! -d "$ARTIFACT_DIR" ]]; then
  echo "Artifact directory not found: $ARTIFACT_DIR" >&2
  exit 1
fi

RAW_FILE="$ARTIFACT_DIR/$RAW_FILE_NAME"
CONFIGMAP_FILE="$ARTIFACT_DIR/$CONFIGMAP_FILE_NAME"

for file in "$RAW_FILE" "$CONFIGMAP_FILE"; do
  if [[ ! -f "$file" ]]; then
    echo "Required artifact missing: $file" >&2
    exit 1
  fi
done

require_real_value "REPO_DIR" "$REPO_DIR"
require_real_value "BASTION_HOST" "$BASTION_HOST"
require_real_value "JUMP_HOST" "$JUMP_HOST"
require_real_value "REMOTE_RAW_FILE_NAME" "$REMOTE_RAW_FILE_NAME"
require_real_value "REMOTE_CONFIGMAP_FILE_NAME" "$REMOTE_CONFIGMAP_FILE_NAME"

timestamp="$(date +%Y%m%d-%H%M%S)"

ssh -o ClearAllForwardings=yes "$BASTION_HOST" \
  "ssh $JUMP_HOST 'bash -s -- $(printf '%q' "$REPO_DIR") $(printf '%q' "$timestamp") $(printf '%q' "$REMOTE_CONFIGMAP_FILE_NAME") $(printf '%q' "$REMOTE_RAW_FILE_NAME")'" <<'REMOTE'
set -euo pipefail

repo_dir="$1"
timestamp="$2"
remote_configmap_file="$3"
remote_raw_file="$4"

cd "$repo_dir"
if [[ -f "$remote_configmap_file" ]]; then
  cp "$remote_configmap_file" "$remote_configmap_file.bak-$timestamp"
fi

if [[ -f "$remote_raw_file" ]]; then
  cp "$remote_raw_file" "$remote_raw_file.bak-$timestamp"
fi
REMOTE

ssh -o ClearAllForwardings=yes "$BASTION_HOST" \
  "ssh $JUMP_HOST 'cat > $(printf '%q' "$REPO_DIR/$REMOTE_CONFIGMAP_FILE_NAME")'" < "$CONFIGMAP_FILE"

ssh -o ClearAllForwardings=yes "$BASTION_HOST" \
  "ssh $JUMP_HOST 'cat > $(printf '%q' "$REPO_DIR/$REMOTE_RAW_FILE_NAME")'" < "$RAW_FILE"

echo "Remote repo files updated under: $REPO_DIR"
echo "Review, commit, and push from the Git-managed checkout."
