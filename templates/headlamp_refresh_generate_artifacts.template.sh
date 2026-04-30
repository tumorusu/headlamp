#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_ROOT="${OUTPUT_ROOT:-$SCRIPT_DIR/refresh-output}"
CLUSTERS_FILE="${CLUSTERS_FILE:-$SCRIPT_DIR/clusters.txt}"
BASTION_HOST="${BASTION_HOST:-<bastion-host>}"
JUMP_HOST="${JUMP_HOST:-<jump-host>}"
TARGET_SERVICEACCOUNT="${TARGET_SERVICEACCOUNT:-headlamp}"
TARGET_BINDING="${TARGET_BINDING:-headlamp-readonly-binding}"
TOKEN_DURATION="${TOKEN_DURATION:-8760h}"

read_passcode() {
  if [[ -n "${REMOTE_LOGIN_PASSCODE:-}" ]]; then
    return
  fi

  read -rsp "Enter remote login passcode: " REMOTE_LOGIN_PASSCODE
  echo
}

fetch_remote_file() {
  local remote_file="$1"
  local local_file="$2"
  local raw

  raw="$(
    ssh -o ClearAllForwardings=yes "$BASTION_HOST" \
      "ssh $JUMP_HOST 'printf \"__BEGIN__\\n\"; base64 -w0 \"$remote_file\"; printf \"\\n__END__\\n\"'" \
      2>/dev/null
  )"

  printf '%s\n' "$raw" \
    | awk '/^__BEGIN__$/ {capture=1; next} /^__END__$/ {capture=0} capture {print}' \
    | tr -d '\n' \
    | base64 -d > "$local_file"
}

if [[ ! -f "$CLUSTERS_FILE" ]]; then
  echo "Missing cluster list: $CLUSTERS_FILE" >&2
  exit 1
fi

mapfile -t CLUSTERS < <(grep -vE '^\s*($|#)' "$CLUSTERS_FILE")
if [[ "${#CLUSTERS[@]}" -eq 0 ]]; then
  echo "No clusters defined in $CLUSTERS_FILE" >&2
  exit 1
fi

read_passcode

timestamp="$(date +%Y%m%d-%H%M%S)"
output_dir="$OUTPUT_ROOT/headlamp-refresh-$timestamp"
mkdir -p "$output_dir"

cluster_args=""
for cluster in "${CLUSTERS[@]}"; do
  cluster_args+=" $(printf '%q' "$cluster")"
done

remote_output="$(
  ssh -o ClearAllForwardings=yes "$BASTION_HOST" \
    "ssh $JUMP_HOST 'bash -s -- $(printf '%q' "$REMOTE_LOGIN_PASSCODE") $(printf '%q' "$TARGET_BINDING") $(printf '%q' "$TARGET_SERVICEACCOUNT") $(printf '%q' "$TOKEN_DURATION")$cluster_args'" <<'REMOTE'
set -euo pipefail

REMOTE_LOGIN_PASSCODE="$1"
TARGET_BINDING="$2"
TARGET_SERVICEACCOUNT="$3"
TOKEN_DURATION="$4"
shift 4
CLUSTERS=("$@")

remote_dir="$(mktemp -d "/tmp/headlamp-refresh-${USER}-XXXXXX")"
data_tsv="$remote_dir/cluster-data.tsv"
token_meta_tsv="$remote_dir/token-metadata.tsv"
validation_txt="$remote_dir/validation.txt"
raw_cfg="$remote_dir/headlamp-kubeconfig.yaml"
configmap_cfg="$remote_dir/headlamp-configmap.yaml"

: > "$data_tsv"
printf 'cluster\tserviceaccount_namespace\tissued_at_utc\texpires_at_utc\n' > "$token_meta_tsv"

login_cluster() {
  local cluster="$1"
  printf '%s\n' "$REMOTE_LOGIN_PASSCODE" | k8s-login -c "$cluster" >/dev/null
}

for cluster in "${CLUSTERS[@]}"; do
  login_cluster "$cluster"

  sa_namespace="$(
    kubectl get clusterrolebinding "$TARGET_BINDING" -o yaml | awk -v sa="$TARGET_SERVICEACCOUNT" '
      $1=="-" && $2=="kind:" && $3=="ServiceAccount" {in_sa=1; name=""; ns=""; next}
      in_sa && $1=="name:" {name=$2}
      in_sa && $1=="namespace:" {ns=$2}
      in_sa && name==sa && ns!="" {print ns; exit}
    '
  )"

  if [[ -z "$sa_namespace" ]]; then
    echo "Could not find bound service-account namespace for $cluster" >&2
    exit 1
  fi

  server="$(kubectl config view --minify --raw -o jsonpath='{.clusters[0].cluster.server}')"
  ca_data="$(kubectl config view --minify --raw -o jsonpath='{.clusters[0].cluster.certificate-authority-data}')"
  token="$(kubectl -n "$sa_namespace" create token "$TARGET_SERVICEACCOUNT" --duration="$TOKEN_DURATION")"

  printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$cluster" \
    "$server" \
    "$ca_data" \
    "$TARGET_SERVICEACCOUNT-$cluster" \
    "$sa_namespace" \
    "$token" >> "$data_tsv"

  CLUSTER_NAME="$cluster" SA_NAMESPACE="$sa_namespace" TOKEN_VALUE="$token" python3 - <<'PY' >> "$token_meta_tsv"
import base64
import json
import os
from datetime import datetime, timezone

cluster = os.environ["CLUSTER_NAME"]
sa_namespace = os.environ["SA_NAMESPACE"]
token = os.environ["TOKEN_VALUE"]
payload = token.split(".")[1]
payload += "=" * (-len(payload) % 4)
claims = json.loads(base64.urlsafe_b64decode(payload))

def fmt(ts):
    return datetime.fromtimestamp(ts, tz=timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

print(f"{cluster}\t{sa_namespace}\t{fmt(claims['iat'])}\t{fmt(claims['exp'])}")
PY
done

python3 - "$data_tsv" "$raw_cfg" "$configmap_cfg" <<'PY'
import sys

data_tsv, raw_out, configmap_out = sys.argv[1:]
entries = []

with open(data_tsv, encoding="utf-8") as handle:
    for line in handle:
        cluster, server, ca_data, user, namespace, token = line.rstrip("\n").split("\t")
        entries.append(
            {
                "cluster": cluster,
                "server": server,
                "ca_data": ca_data,
                "user": user,
                "namespace": namespace,
                "token": token,
            }
        )

lines = [
    "apiVersion: v1",
    "kind: Config",
    "preferences: {}",
    "",
    "clusters:",
]

for item in entries:
    lines.extend(
        [
            f"- name: {item['cluster']}",
            "  cluster:",
            f"    server: {item['server']}",
            f"    certificate-authority-data: {item['ca_data']}",
        ]
    )

lines.extend(["", "users:"])

for item in entries:
    lines.extend(
        [
            f"- name: {item['user']}",
            "  user:",
            f"    token: {item['token']}",
        ]
    )

lines.extend(["", "contexts:"])

for item in entries:
    lines.extend(
        [
            f"- name: {item['cluster']}",
            "  context:",
            f"    cluster: {item['cluster']}",
            f"    user: {item['user']}",
            f"    namespace: {item['namespace']}",
        ]
    )

if entries:
    lines.extend(["", f"current-context: {entries[0]['cluster']}"])

raw_text = "\n".join(lines) + "\n"

with open(raw_out, "w", encoding="utf-8") as handle:
    handle.write(raw_text)

with open(configmap_out, "w", encoding="utf-8") as handle:
    handle.write(
        "apiVersion: v1\n"
        "kind: ConfigMap\n"
        "metadata:\n"
        "  name: headlamp-kubeconfig\n"
        "  namespace: headlamp\n"
        "data:\n"
        "  config: |\n"
    )
    for line in raw_text.splitlines():
        handle.write(f"    {line}\n")
PY

for cluster in "${CLUSTERS[@]}"; do
  kubectl --kubeconfig "$raw_cfg" --context "$cluster" get namespace default --no-headers >/dev/null
  printf '%s ok\n' "$cluster" >> "$validation_txt"
done

printf 'REMOTE_DIR=%s\n' "$remote_dir"
REMOTE
)"

printf '%s\n' "$remote_output"

remote_dir="$(printf '%s\n' "$remote_output" | sed -n 's/^REMOTE_DIR=//p' | tail -1)"
if [[ -z "$remote_dir" ]]; then
  echo "Failed to determine remote output directory." >&2
  exit 1
fi

fetch_remote_file "$remote_dir/headlamp-kubeconfig.yaml" "$output_dir/headlamp-kubeconfig.yaml"
fetch_remote_file "$remote_dir/headlamp-configmap.yaml" "$output_dir/headlamp-configmap.yaml"
fetch_remote_file "$remote_dir/token-metadata.tsv" "$output_dir/token-metadata.tsv"
fetch_remote_file "$remote_dir/validation.txt" "$output_dir/validation.txt"

ln -sfn "$output_dir" "$OUTPUT_ROOT/latest"

echo "Local refresh artifacts written to: $output_dir"
