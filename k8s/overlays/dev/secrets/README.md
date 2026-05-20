# Secrets (dev overlay)

Copy the example files and fill in real values before deploy:

```bash
cp s3-credentials.env.example s3-credentials.env
cp hetida-platform-secrets.env.example hetida-platform-secrets.env
cp cnpg-superuser-secret.env.example cnpg-superuser-secret.env
# edit both files — never commit *.env (see k8s/.gitignore)
```

Deploy:

```bash
kubectl apply -k k8s/overlays/dev
```
