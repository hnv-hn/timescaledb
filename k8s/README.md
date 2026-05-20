# TimescaleDB on CloudNativePG

## Layout

- `base/crds/` — CNPG 0.28 CRDs (10 resources)
- `base/hetida-platform-dev/` — cluster, backups, monitoring
- `overlays/dev/` — MinIO backup, restore test CronJob, local secrets
- `overlays/prod/` — external S3, External Secrets, pooler, network policy
- `recovery/` — manual restore manifests
- `docs/DEV_DEPLOY.md` — development deployment (step-by-step)
- `docs/PRODUCTION.md` — production runbook
- `docs/CNPG_UPGRADE.md` — operator/CRD upgrades

## ArgoCD

| App                | Overlay             |
|--------------------|---------------------|
| `timescaledb-prod` | `k8s/overlays/prod` |
| `timescaledb-dev`  | `k8s/overlays/dev`  |
| `minio-dev`        | dev only            |

## Deploy

- **Dev:** [docs/DEV_DEPLOY.md](docs/DEV_DEPLOY.md) (ArgoCD or `kubectl apply -k k8s/overlays/dev`)
- **Prod:** [docs/PRODUCTION.md](docs/PRODUCTION.md) (AWS Secrets Manager + external S3)

## Docs

- [Development deployment](docs/DEV_DEPLOY.md)
- [Production runbook](docs/PRODUCTION.md)
- [CNPG upgrade](docs/CNPG_UPGRADE.md)
