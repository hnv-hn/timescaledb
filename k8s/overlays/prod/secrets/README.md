# Secrets (prod overlay)

```bash
cp s3-credentials.env.example s3-credentials.env
cp hetida-platform-secrets.env.example hetida-platform-secrets.env
cp cnpg-superuser-secret.env.example cnpg-superuser-secret.env
```

Use strong, unique credentials. Deploy with `kubectl apply -k k8s/overlays/prod`.
