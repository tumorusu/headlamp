# Kubescape rollout across clusters with centralized Headlamp

A repeatable procedure to install the Kubescape operator on a fleet of
Kubernetes clusters and surface its results through a single, centralized
Headlamp deployment.

> This document is intentionally generic. Supply your own cluster list in
> `templates/clusters.template.txt` (one cluster context per line) and replace
> every `<placeholder>` with values for your environment. Do not commit real
> cluster names, kubeconfigs, tokens, or internal paths.

## Purpose

- One repeatable procedure to install Kubescape on all target clusters.
- Keep Headlamp centralized and install the Kubescape Headlamp plugin only once
  on the central Headlamp deployment.
- Use only approved internal registry images in policy-restricted clusters.

## Scope

- Per-cluster Kubescape operator installation on each target cluster.
- Centralized Headlamp plugin install after per-cluster Kubescape validation.
- Namespace creation managed through your GitOps/infra repo where Git-managed
  namespace creation is required.

## Target clusters

List the clusters to roll out to in `templates/clusters.template.txt`:

```
cluster-a
cluster-b
cluster-c
```

Blank lines and `#` comments are ignored by the generate script. Keep the real
list out of version control for any public repository.

## Architecture summary

1. The Kubescape operator must run inside every cluster that should produce
   security and compliance data.
2. Headlamp remains centralized; do not install another Headlamp instance on
   every cluster unless separately required.
3. The Kubescape Headlamp plugin is installed only once on the centralized
   Headlamp deployment.
4. Headlamp shows Kubescape data only for clusters where Kubescape is installed
   and healthy.

## Git and ownership model

1. Namespace creation is owned by your infrastructure (GitOps) repo.
2. Example Flux layout (adjust to your repo):
   - Flux object: `<infra-repo>/post-installation/namespace-create-kustomization.yaml`
   - Resolved overlay path: `./overlays/<environment>/namespaces`
3. The kubescape namespace manifest lives in:
   - `<infra-repo>/post-installation/base/namespaces/kubescape-ns.yaml`
4. The environment overlay references it in:
   - `<infra-repo>/overlays/<environment>/namespaces/kustomization.yaml`

## Prerequisites

1. Mirror all required public images into the approved internal registry.
2. Prepare one Kubescape operator values file that uses only internal registry
   image paths (for example `kubescape-operator-values.yaml`).
3. Confirm access to every target cluster context with `kubectl` and Helm.
4. Confirm the kubescape namespace exists if you rely on Git-managed namespace
   creation.

## Version validation notes

1. Validate the image list below against the current upstream
   `kubescape-operator` Helm chart and plugin repository before each rollout.
2. `host-scanner` may not be present in current upstream charts; do not mirror
   it unless your chart still references it.
3. `grype-offline-db` ships upstream as a blank-tag plus digest-pinned image;
   pin the internal mirror explicitly if you enable it.

## Policy-restricted clusters

1. Policy-restricted clusters may not allow the privileged host-scanning path
   required by `node-agent`.
2. A working rollout keeps `KS_ENABLE_HOST_SCANNER=false` and removes
   `node-agent` from the static manifest.
3. If `kubectl get ds -n kubescape node-agent` shows non-zero `DESIRED` with
   `CURRENT=0` and `READY=0`, treat it as a policy-incompatible host-scanning
   path and apply the same fix in Git.

## Required images to mirror

```
quay.io/kubescape/headlamp-plugin:v0.11.0
quay.io/kubescape/kubescape:v4.0.6
quay.io/kubescape/operator:v0.2.141
quay.io/kubescape/kubevuln:v0.3.137
quay.io/kubescape/storage:v0.0.274
quay.io/kubescape/klamav:1.3.1-34_alpha
quay.io/kubescape/synchronizer:v0.0.141
quay.io/kubescape/http-request:v0.2.19
quay.io/kubescape/kubectl:1.30.3
ghcr.io/jkroepke/kube-webhook-certgen:1.8.1
```

Optional images depending on enabled features:

```
quay.io/kubescape/opentelemetry-collector:0.108.0
quay.io/kubescape/grype-offline-db
quay.io/kubescape/prometheus-exporter:v0.2.18
quay.io/kubescape/helm-release-upgrader:v0.1.0
busybox:latest
```

## Values file pattern

Create a local file (for example `kubescape-operator-values.yaml`) and replace
every public image repository with the approved internal registry path. At
minimum validate these references in the values file or rendered chart:

1. operator image
2. kubescape image
3. kubevuln image
4. storage image
5. synchronizer image
6. http-request image
7. kubectl image
8. kube-webhook-certgen image
9. any optional feature images you enable

## Conservative rollout recommendation

1. Start with a pilot on a single non-production cluster.
2. Verify namespace, pods, CRDs, and report generation.
3. Only then continue cluster by cluster through the remaining clusters.
4. Install the Headlamp plugin only after the operator is confirmed healthy on
   the clusters you want visible in Headlamp.
5. Roll out production-named clusters last, only after policy and change
   approval.

## Per-cluster installation procedure

Run the same steps for each target cluster.

### Step 1 — switch to the target cluster

```
kubectl config use-context <cluster-context>
kubectl config current-context
```

### Step 2 — verify namespace readiness

```
kubectl get ns kubescape
```

- If it does not exist and Git/Flux is expected to create it, reconcile the
  namespace path first through your infra flow.
- If a live install is needed before Git reconciliation:
  ```
  kubectl create ns kubescape
  ```
- Confirm labels if the namespace came from Git:
  ```
  kubectl get ns kubescape --show-labels
  ```

### Step 3 — prepare the Helm source

```
helm repo add kubescape https://kubescape.github.io/helm-charts/
helm repo update
```

### Step 4 — install or upgrade the Kubescape operator

```
helm upgrade --install kubescape kubescape/kubescape-operator \
  --namespace kubescape \
  --create-namespace \
  -f kubescape-operator-values.yaml
```

### Step 5 — wait for workload readiness

```
kubectl get pods -n kubescape
kubectl get deploy -n kubescape
```

- On restricted clusters, do not expect `node-agent` to come up; the validated
  rollout disables host scanning and omits that DaemonSet.
- If `node-agent` shows `DESIRED>0` but `CURRENT=0`/`READY=0`, set
  `KS_ENABLE_HOST_SCANNER=false` and remove `node-agent` in Git, then let Flux
  reconcile.
- If pods fail:
  ```
  kubectl get events -n kubescape --sort-by=.lastTimestamp
  kubectl describe pod -n kubescape <pod-name>
  ```

### Step 6 — verify CRDs and data generation

```
kubectl get crd | grep -i kubescape
kubectl get crd | grep -i vulnerability
kubectl get workloadconfigurationscans -A
kubectl get vulnerabilitymanifests -A
```

If your feature set differs, also inspect:

```
kubectl get vulnerabilityreports -A
kubectl get configauditreports -A
kubectl get clustercompliancereports -A
```

### Step 7 — record the cluster as complete

Mark a cluster complete only when:

1. the kubescape namespace exists,
2. kubescape pods are healthy,
3. CRDs are present,
4. report resources are being created.

## Centralized Headlamp plugin procedure

Run this only once, after the desired clusters are producing Kubescape data.

### Assumptions

1. Centralized Headlamp remains the existing multicluster deployment.
2. The Headlamp plugin image must come from the approved internal registry.
3. Do not reference public registries directly in Git-managed manifests if
   policy blocks them.

### Plugin pattern

1. Add an `emptyDir` volume named `headlamp-plugins`.
2. Add an initContainer:
   - name: `kubescape-plugin`
   - image: `<internal-registry>/headlamp-plugin:<approved-tag>`
   - copy files from `/plugins` to `/headlamp/plugins`
3. Mount `/headlamp/plugins` into the Headlamp container.
4. Keep the policy-required securityContext:
   - `runAsNonRoot: true`
   - `runAsUser: 1000`
   - `allowPrivilegeEscalation: false`
   - drop ALL capabilities
   - `seccompProfile: RuntimeDefault`

### Verification

```
kubectl -n headlamp get deploy headlamp -o yaml
```

1. Confirm `initContainers` contains `kubescape-plugin`.
2. Confirm Headlamp mounts `/headlamp/plugins`.
3. Confirm pods roll successfully.
4. Open Headlamp and switch cluster contexts.
5. Confirm Kubescape views appear only for clusters where Kubescape is installed
   and healthy.

## Common failure points

1. **Public image references still present** — use only approved internal
   registry paths.
2. **Missing namespace** — reconcile the infra namespace path, or create the
   namespace before the Helm install.
3. **Policy rejection (Kyverno or another admission controller)** — inspect the
   denied field and update manifest security settings or image source. If the
   denied/stalled component is `node-agent`, disable host scanning and remove
   `node-agent`.
4. **CRDs present but no reports** — inspect Kubescape pods, controller logs, and
   enabled feature configuration.
5. **Headlamp plugin not visible** — verify plugin image path, initContainer
   copy logic, volume mount, and a successful pod restart.

## Per-cluster verification checklist

```
kubectl config current-context
kubectl get ns kubescape
kubectl get pods -n kubescape
kubectl get crd | grep -i kubescape
kubectl get workloadconfigurationscans -A
kubectl get vulnerabilitymanifests -A
```

## Final verification in Headlamp

1. Open a completed cluster in Headlamp and confirm Kubescape views appear.
2. Open additional completed cluster contexts and confirm data appears.
3. Open a cluster where Kubescape is not installed and confirm no data appears.
