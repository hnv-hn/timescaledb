# Production Deployment — timescaledb

## Prerequisites

- Kubernetes 1.27+
- CloudNativePG 0.28 (CRDs wave 0, operator wave 1)
- Longhorn with 3+ worker nodes
- External Secrets Operator + AWS Secrets Manager (or adapt `SecretStore`)
- IRSA / workload identity for `external-secrets-sa` (recommended)
- Alertmanager with Teams webhook (see `alertmanager-teams-config.yaml`)

## ArgoCD applications

| App                | Path                | Environment  |
|--------------------|---------------------|--------------|
| `timescaledb-crds` | `k8s/base/crds`     | all          |
| `cnpg-operator`    | Helm 0.28.0         | all          |
| `timescaledb-prod` | `k8s/overlays/prod` | production   |
| `timescaledb-dev`  | `k8s/overlays/dev`  | development  |
| `minio-dev`        | Helm MinIO          | **dev only** |

Deploy order: CRDs → operator → database overlay.

## AWS Secrets Manager

Create these secrets before syncing prod:

| Secret key                   | JSON properties                      |
|------------------------------|--------------------------------------|
| `timescaledb/prod/s3`        | `access_key_id`, `secret_access_key` |
| `timescaledb/prod/database`  | `username` (tsadmin), `password`     |
| `timescaledb/prod/superuser` | `username` (postgres), `password`    |

ExternalSecret manifests: [`overlays/prod/external-secrets/`](../overlays/prod/external-secrets/).

Grant the `external-secrets-sa` ServiceAccount IAM policy `secretsmanager:GetSecretValue` on the keys above.

## S3 backup (production)

Configured in [`cluster-backup-patch.yaml`](../overlays/prod/cluster-backup-patch.yaml):

- Bucket: `s3://hetida-timescaledb-prod/timescaledb/` (adjust name/region)
- Endpoint: `https://s3.eu-central-1.amazonaws.com`
- TLS via HTTPS (no MinIO in prod)
- Retention: 30 days (Barman) + optional S3 lifecycle (Glacier after 90d)

Recommended S3 bucket policy: dedicated IAM user, no public access, versioning enabled.

## Storage

Longhorn StorageClass in prod overlay uses **3 replicas** and `reclaimPolicy: Retain`.

PVC size: 100Gi (see `cluster-patch.yaml`).

## High availability

- 3 Postgres instances, sync replication (`minSyncReplicas: 1`)
- Pod anti-affinity across nodes
- `enablePDB: true` — minimum 1 pod available during disruptions
- PgBouncer pooler (`timescaledb-pooler-rw`) for app connections

## TLS

- Postgres: `ssl=on` in cluster parameters — apps must use `sslmode=require`
- CNPG manages server certificates automatically
- Backup path uses HTTPS to AWS S3

## Network policy

[`network-policy.yaml`](../overlays/prod/network-policy.yaml) allows:

- Ingress: app namespace `hetida-platform-app`, monitoring namespace
- Egress: replication, HTTPS (443), DNS

Adjust namespace labels before deploy.

## Monitoring and alerts

- PodMonitor enabled on cluster and operator
- PrometheusRules with `team=platform` labels route to Teams via Alertmanager
- Grafana dashboards: `grafana-cnpg-db-dashboard`, `grafana-cnpg-backup-dashboard`

Configure Alertmanager receiver using [`alertmanager-teams-config.yaml`](../overlays/prod/alertmanager-teams-config.yaml).

## Restore (production)

Do **not** use the automated restore CronJob (dev only).

Manual PITR:

```bash
cd scripts
./restore.sh pitr '2026-05-06T14:30:00Z'
```

Ensure recovery manifests point to the prod S3 bucket (update `k8s/recovery/*.yaml` endpoint/bucket if needed).

Monthly restore drill: restore to isolated namespace, run `SELECT 1`, delete cluster.

## Upgrade CNPG

See [CNPG_UPGRADE.md](CNPG_UPGRADE.md).

## Dev vs prod

| Feature              | Dev                      | Prod                      |
|----------------------|--------------------------|---------------------------|
| Backup target        | MinIO in-cluster         | External S3               |
| Secrets              | `.env` + secretGenerator | External Secrets Operator |
| Restore test CronJob | yes                      | no                        |
| MinIO ArgoCD app     | yes                      | no                        |
| Instances / RAM      | 2 / 1–2Gi                | 3 / 4–8Gi                 |
| Pooler               | no                       | yes                       |
