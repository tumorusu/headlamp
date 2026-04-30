#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ARTIFACT_DIR="${1:-$SCRIPT_DIR/refresh-output/latest}"
REPO_DIR="${REPO_DIR:-<gitops-repo-path>}"
BASTION_HOST="${BASTION_HOST:-<bastion-host>}"
JUMP_HOST="${JUMP_HOST:-<jump-host>}"
RAW_FILE_NAME="${RAW_FILE_NAME:-headlamp-kubeconfig.yaml}"
CONFIGMAP_FILE_NAME="${CONFIGMAP_FILE_NAME:-headlamp-configmap.yaml}"

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

timestamp="$(date +%Y%m%d-%H%M%S)"

ssh -o ClearAllForwardings=yes "$BASTION_HOST" \
  "ssh $JUMP_HOST 'bash -s -- $(printf '%q' "$REPO_DIR") $(printf '%q' "$timestamp")'" <<'REMOTE'
set -euo pipefail

repo_dir="$1"
timestamp="$2"

cd "$repo_dir"
cp headlamp-configmap.yaml "headlamp-configmap.yaml.bak-$timestamp"
cp "$(basename "$repo_dir")-kubeconfig" "$(basename "$repo_dir")-kubeconfig.bak-$timestamp" 2>/dev/null || true
REMOTE

ssh -o ClearAllForwardings=yes "$BASTION_HOST" \
  "ssh $JUMP_HOST 'cat > $REPO_DIR/headlamp-configmap.yaml'" < "$CONFIGMAP_FILE"

ssh -o ClearAllForwardings=yes "$BASTION_HOST" \
  "ssh $JUMP_HOST 'cat > $REPO_DIR/$(basename "$REPO_DIR")-kubeconfig'" < "$RAW_FILE"

echo "Remote repo files updated under: $REPO_DIR"
echo "Review, commit, and push from the Git-managed checkout."
