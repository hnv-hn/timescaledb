# Secrets (prod overlay)

Credentials are synced via **External Secrets Operator** from AWS Secrets Manager.
Do not commit `.env` files for production.

## Required Secrets Manager entries

| Key                          | Properties                           |
|------------------------------|--------------------------------------|
| `timescaledb/prod/s3`        | `access_key_id`, `secret_access_key` |
| `timescaledb/prod/database`  | `username`, `password`               |
| `timescaledb/prod/superuser` | `username`, `password`               |

## IAM

Bind IRSA to ServiceAccount `external-secrets-sa` in namespace `hetida-platform-dev`.

## Deploy

```bash
kubectl apply -k k8s/overlays/prod
```

See [PRODUCTION.md](../../docs/PRODUCTION.md).
