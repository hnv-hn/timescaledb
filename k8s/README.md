# TimescaleDB on CloudNativePG

## Layout

- `base/hetida-platform-cnpg/` — cluster, backups, monitoring, restore test (no credentials in Git)
- `overlays/dev/` — 2 instances, 20Gi, 7d backup retention
- `overlays/prod/` — 3 instances, 100Gi, 30d retention, higher resources
- `recovery/` — manual restore manifests (apply after secrets exist in namespace)

## Deploy

```bash
# 1. Create secrets from examples (see overlays/*/secrets/README.md)
# 2. Apply overlay
kubectl apply -k k8s/overlays/dev
# or
kubectl apply -k k8s/overlays/prod
```

Base alone is incomplete without overlay `secretGenerator` entries.

## Backup

- Barman → MinIO at `s3://backups/timescale-cluster/`
- Daily `ScheduledBackup` at 02:00 UTC
- WAL + data compression: gzip
- Backups run on standby when possible (`prefer-standby`)
