# Secrets (dev overlay)

```bash
cp s3-credentials.env.example s3-credentials.env
cp hetida-platform-secrets.env.example hetida-platform-secrets.env
cp cnpg-superuser-secret.env.example cnpg-superuser-secret.env
# edit files — never commit *.env
```

## MinIO (dev backup target)

Create MinIO root credentials before syncing `minio-dev` ArgoCD app:

```bash
kubectl create namespace minio-system --dry-run=client -o yaml | kubectl apply -f -
kubectl create secret generic minio-root-credentials -n minio-system \
  --from-literal=rootUser=admin \
  --from-literal=rootPassword='change-me'
```

Backup endpoint: `http://minio.minio-system.svc.cluster.local:9000`

Deploy:

```bash
kubectl apply -k k8s/overlays/dev
```

Full guide: [DEV_DEPLOY.md](../../docs/DEV_DEPLOY.md)

Restore test CronJob runs daily at 04:00 UTC (dev only).
