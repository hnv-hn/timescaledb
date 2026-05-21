# Development Deployment — timescaledb

Step-by-step guide to deploy the TimescaleDB CNPG stack in a **development** environment.

## What gets deployed (dev)

| Component        | Source                             | Notes                                  |
|------------------|------------------------------------|----------------------------------------|
| CNPG CRDs        | `k8s/base/crds`                    | 10 CRDs, CNPG 0.28                     |
| CNPG Operator    | Helm chart `cloudnative-pg` 0.28.0 | ArgoCD app `cnpg-operator`             |
| MinIO            | Helm chart                         | ArgoCD app `minio-dev`, backup target  |
| Postgres cluster | `k8s/overlays/dev`                 | 2 instances, 20Gi, 7d backup retention |
| Restore test     | `k8s/components/restore-test`      | CronJob daily 04:00 UTC                |

Dev uses **MinIO** for backups (`http://minio.minio-system.svc.cluster.local:9000`), not external S3.

## Important constraints

- Deploy **only dev OR prod** on the same cluster — both use namespace `hetida-platform-dev` and cluster name `timescaledb`.
- Do **not** sync `timescaledb-prod` on a dev cluster.
- Restore manifests under `k8s/recovery/` are applied **manually** (not via ArgoCD).

---

## Prerequisites

1. Kubernetes cluster (1.27+) with `kubectl` configured
2. StorageClass **`longhorn`** available:

   ```bash
   kubectl get storageclass longhorn
   ```

   Install Longhorn if missing: [Longhorn docs](https://longhorn.io/docs/latest/deploy/install/).

3. Optional (for monitoring CRDs): Prometheus Operator (`PodMonitor`, `PrometheusRule`)

4. For GitOps: ArgoCD installed in the cluster

---

## Path A — ArgoCD (GitOps)

Use when manifests are deployed from Git (`https://github.com/hnv-hn/timescaledb`).

### Step 1 — Push code

Commit and push your branch to `main` (or adjust `targetRevision` in ArgoCD apps).

### Step 2 — Create secrets (required before cluster sync)

`.env` files under `overlays/dev/secrets/` are **gitignored**. ArgoCD cannot build `secretGenerator` from the repo — create secrets manually:

```bash
kubectl create namespace hetida-platform-dev --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic s3-creds -n hetida-platform-dev \
  --from-literal=ACCESS_KEY_ID='<minio-access-key>' \
  --from-literal=SECRET_ACCESS_KEY='<minio-secret-key>' \
  --dry-run=client -o yaml | kubectl apply -f -

# eg.:
# MINIO_ROOT_USER=devstorage01
# MINIO_ROOT_PASSWORD=K9mZ4qX2vW8tR6yP1sH7cB3nL5dE0aFJ

kubectl create secret generic hetida-platform-secrets -n hetida-platform-dev \
  --from-literal=username=tsadmin \
  --from-literal=password='<app-db-password>' \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic cnpg-superuser-secret -n hetida-platform-dev \
  --from-literal=username=postgres \
  --from-literal=password='<postgres-superuser-password>' \
  --dry-run=client -o yaml | kubectl apply -f -
```

MinIO root credentials (before `minio-dev`):

```bash
kubectl create namespace minio-system --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic minio-root-credentials -n minio-system \
  --from-literal=rootUser=admin \
  --from-literal=rootPassword='<minio-root-password>' \
  --dry-run=client -o yaml | kubectl apply -f -
```

Use the same MinIO credentials in `s3-creds` if you use the default MinIO user for Barman.

### Step 3 — Apply individual Application manifests from `argocd/applications/`

| Wave | Application        | Wait for                              |
|------|--------------------|---------------------------------------|
| 0    | `timescaledb-crds` | CRDs `Established`                    |
| 0    | `minio-dev`        | MinIO pod `Running`                   |
| 1    | `cnpg-operator`    | Deployment available in `cnpg-system` |
| 2    | `timescaledb-dev`  | Cluster `Healthy`                     |

```bash
kubectl patch application timescaledb-crds -n argocd \
  --type merge \
  -p '{"operation":{"sync":{}}}'
  
kubectl wait --for=condition=Established crd/clusters.postgresql.cnpg.io --timeout=120s

kubectl patch application minio-dev -n argocd \
  --type merge \
  -p '{"operation":{"sync":{}}}'

kubectl wait --for=condition=Ready pod -l app=minio -n minio-system --timeout=300s

kubectl patch application cnpg-operator -n argocd \
  --type merge \
  -p '{"operation":{"sync":{}}}'
kubectl wait --for=condition=Available deployment -n cnpg-system \
  -l app.kubernetes.io/name=cloudnative-pg --timeout=300s

kubectl patch application timescaledb-dev -n argocd \
  --type merge \
  -p '{"operation":{"sync":{}}}'
```

### Step 5 — Verify

```bash
kubectl get cluster -n hetida-platform-dev
kubectl get pods -n hetida-platform-dev -l cnpg.io/cluster=timescaledb
kubectl get pods -n hetida-platform-dev -L cnpg.io/role
kubectl get scheduledbackup -n hetida-platform-dev
kubectl get backups -n hetida-platform-dev
kubectl get cronjob timescale-restore-test -n hetida-platform-dev
```

Expected:

- Cluster phase: `Cluster in healthy state` / `Healthy`
- 2 Postgres pods (dev patch)
- Daily backup at 02:00 UTC (`timescale-backup-daily`)
- Restore test CronJob at 04:00 UTC

---

## Path B — Local kubectl (no ArgoCD)

Use when deploying from your workstation with local secret files.

### Step 1 — Prepare secrets

```bash
cd k8s/overlays/dev/secrets
cp s3-credentials.env.example s3-credentials.env
cp hetida-platform-secrets.env.example hetida-platform-secrets.env
cp cnpg-superuser-secret.env.example cnpg-superuser-secret.env
# Edit all three files — never commit *.env
```

### Step 2 — Install MinIO

Via ArgoCD `minio-dev`, or Helm:

```bash
kubectl create namespace minio-system
kubectl create secret generic minio-root-credentials -n minio-system \
  --from-literal=rootUser=admin \
  --from-literal=rootPassword='change-me'

helm repo add minio https://charts.min.io/
helm install minio minio/minio -n minio-system \
  --set existingSecret=minio-root-credentials \
  --set buckets[0].name=backups
```

### Step 3 — Install CRDs and operator

```bash
kubectl apply -k k8s/base/crds
kubectl wait --for=condition=Established crd/clusters.postgresql.cnpg.io --timeout=120s

helm repo add cnpg https://cloudnative-pg.github.io/charts
helm repo update
helm install cnpg cnpg/cloudnative-pg -n cnpg-system --create-namespace \
  --version 0.28.0 \
  --set installCRDs=false \
  --set monitoring.podMonitorEnabled=true
```

See [CNPG_UPGRADE.md](CNPG_UPGRADE.md) for version alignment.

### Step 4 — Deploy dev overlay

```bash
# From repository root
kubectl kustomize k8s/overlays/dev   # optional preview
kubectl apply -k k8s/overlays/dev
```

### Step 5 — Verify

Same commands as Path A, Step 5.

---

## Connect to the database

| Setting  | Value                                             |
|----------|---------------------------------------------------|
| Host     | `timescaledb-rw.hetida-platform-dev.svc`          |
| Port     | `5432`                                            |
| Database | `hetida_ts`                                       |
| User     | `tsadmin`                                         |
| Password | Secret `hetida-platform-secrets` → key `password` |

```bash
kubectl get secret hetida-platform-secrets -n hetida-platform-dev \
  -o jsonpath='{.data.password}' | base64 -d
```

Port-forward for local access:

```bash
kubectl port-forward svc/timescaledb-rw -n hetida-platform-dev 5432:5432
```

---

## Backup and restore (dev)

### Check backups

```bash
kubectl get backups -n hetida-platform-dev --sort-by=.metadata.creationTimestamp
```

### MinIO bucket check

```bash
kubectl exec -it -n minio-system deploy/minio -- sh
mc alias set local http://localhost:9000 admin '<password>'
mc ls local/backups/timescaledb/
```

### Manual restore

Manifests live in `k8s/recovery/`. The script sets the namespace from `NAMESPACE` or reads the default from `k8s/overlays/<RESTORE_TARGET>/kustomization.yaml` (same as your dev/prod overlay).

From repository root:

```bash
cd scripts

# Default: RESTORE_TARGET=dev, namespace from overlays/dev/kustomization.yaml
./restore.sh latest

# Explicit namespace (overrides overlay default)
NAMESPACE=hetida-platform-dev ./restore.sh latest

# Prod backup manifest + prod overlay namespace
RESTORE_TARGET=prod ./restore.sh latest
# or
RESTORE_TARGET=prod NAMESPACE=hetida-platform-dev ./restore.sh latest

./restore.sh test
./restore.sh pitr '2026-05-06T14:30:00Z'
```

| Variable | Default | Purpose |
|----------|---------|---------|
| `NAMESPACE` | from `k8s/overlays/dev/kustomization.yaml` | Kubernetes namespace for restore cluster |
| `RESTORE_TARGET` | `dev` | Chooses overlay for namespace default and `latest` manifest (`dev` → MinIO, `prod` → S3) |

Delete restore clusters when done:

```bash
kubectl delete cluster timescale-restore-latest -n hetida-platform-dev
kubectl delete cluster timescale-restore-test -n hetida-platform-dev
kubectl delete cluster timescale-restore-pitr -n hetida-platform-dev
```

---

## Dev vs prod (quick reference)

|                 | Dev                              | Prod                      |
|-----------------|----------------------------------|---------------------------|
| ArgoCD app      | `timescaledb-dev`                | `timescaledb-prod`        |
| Overlay path    | `k8s/overlays/dev`               | `k8s/overlays/prod`       |
| Instances       | 2                                | 3                         |
| Storage         | 20Gi                             | 100Gi                     |
| Backup target   | MinIO                            | External S3               |
| Secrets         | `.env` / `kubectl create secret` | External Secrets Operator |
| Restore CronJob | yes                              | no                        |

Production: [PRODUCTION.md](PRODUCTION.md)

---

## Troubleshooting
Symptom -> Likely cause -> Action
---------------------------------
- PVC `Pending` -> No StorageClass `longhorn` -> Install Longhorn or change `storageClass` in base cluster
- ArgoCD kustomize error on secrets -> `.env` not in Git -> Create secrets manually (Path A, Step 2)
- Backup `Failed` -> MinIO down or wrong `s3-creds` -> Check MinIO pods and credential match
- Cluster `Unhealthy` -> Insufficient CPU/RAM -> Check events: `kubectl describe cluster -n hetida-platform-dev`
- PodMonitor not scraped -> No Prometheus Operator -> Install kube-prometheus-stack or disable `enablePodMonitor`
- Two clusters conflict -> dev + prod on same NS -> Remove one overlay deployment

---

## Related docs

- [k8s/README.md](../README.md) — repository layout
- [CNPG_UPGRADE.md](CNPG_UPGRADE.md) — operator and CRD upgrades
- [PRODUCTION.md](PRODUCTION.md) — production deployment
