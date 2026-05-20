# CloudNativePG Upgrade Runbook

Helm chart version **0.28.0** maps to operator **1.28.x** and CRDs from Git branch `release-1.28`.

## Architecture

| Layer    | Source                       | ArgoCD app         | Sync wave |
|----------|------------------------------|--------------------|-----------|
| CRDs     | `k8s/base/crds/` (Git)       | `timescaledb-crds` | 0         |
| Operator | Helm `cloudnative-pg` 0.28.0 | `cnpg-operator`    | 1         |
| Cluster  | `k8s/overlays/*`             | `timescaledb`      | 2+        |

CRDs are **not** installed via Helm (`installCRDs: false`).

## Upgrade procedure

### 1. Update CRD manifests

From repo root, refresh CRDs from the matching release branch:

```bash
CRD_DIR=k8s/base/crds
URL=https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/release-1.28/config/crd/bases

for f in \
  postgresql.cnpg.io_backups.yaml \
  postgresql.cnpg.io_clusterimagecatalogs.yaml \
  postgresql.cnpg.io_clusters.yaml \
  postgresql.cnpg.io_databases.yaml \
  postgresql.cnpg.io_failoverquorums.yaml \
  postgresql.cnpg.io_imagecatalogs.yaml \
  postgresql.cnpg.io_poolers.yaml \
  postgresql.cnpg.io_publications.yaml \
  postgresql.cnpg.io_scheduledbackups.yaml \
  postgresql.cnpg.io_subscriptions.yaml
do
  curl -fsSL "$URL/$f" -o "$CRD_DIR/$f"
done
```

Ensure `k8s/base/crds/kustomization.yaml` lists all 10 files.

### 2. Pin operator chart version

In `argocd/applications/cnpg-operator.yaml`:

```yaml
targetRevision: 0.28.0
```

Use the same minor version for CRDs and chart (e.g. 0.29.0 chart → `release-1.29` CRDs).

### 3. Commit and push

```bash
git add k8s/base/crds argocd/applications/
git commit -m "chore: upgrade CNPG CRDs to 0.28.0"
git push
```

### 4. Sync ArgoCD (order matters)

```bash
# Wave 0: CRDs first
argocd app sync timescaledb-crds --grpc-web

# Wait until CRDs are Established
kubectl wait --for condition=Established crd/clusters.postgresql.cnpg.io --timeout=120s

# Wave 1: Operator
argocd app sync cnpg-operator --grpc-web

# Wave 2+: Cluster workloads
argocd app sync timescaledb --grpc-web
```

### 5. Verify

```bash
kubectl get crd | grep postgresql.cnpg.io
# Expect 10 CRDs

kubectl get deployment -n cnpg-system
kubectl rollout status deployment -n cnpg-system

kubectl get cluster -n hetida-platform-dev
kubectl get pods -n hetida-platform-dev -l cnpg.io/cluster=timescaledb

kubectl get backups -n hetida-platform-dev
```

Check CRD version annotation:

```bash
kubectl get crd clusters.postgresql.cnpg.io -o jsonpath='{.metadata.annotations.app\.kubernetes\.io/version}{"\n"}'
# Expected: 0.28.0
```

## Rollback

CRD downgrades are not supported safely. Before upgrading:

1. Confirm recent backup exists (`kubectl get backups -n hetida-platform-dev`)
2. Document current operator image: `kubectl get deployment -n cnpg-system -o yaml | grep image:`

To rollback operator only, revert `targetRevision` in `cnpg-operator.yaml` and sync. Do **not** remove CRDs while clusters exist.

## Version matrix

| Helm chart | Git branch   | Operator |
|------------|--------------|----------|
| 0.28.0     | release-1.28 | 1.28.x   |
| 0.27.0     | release-1.27 | 1.27.x   |

See [CNPG releases](https://github.com/cloudnative-pg/cloudnative-pg/releases) for the full list.
