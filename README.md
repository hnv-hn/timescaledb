# Recovery

⚠️ Restore NICHT über Argo deployen

Use:

kubectl apply -f restore-latest.yaml

## TODOS

- Prometheus Stack integrieren
- Alerts an Teams schicken
- Dashboard für Backups in Grafana bauen
- ONE Click restore
- PITR (Restore auf exakten Zeitpunkt)
- Backup Rentention Strategie (wichtig)
- Longhorn anstatt minio
- open telemetrie, java agent
- metric von datenbank für monitoring
  - gesund
  - deadlock

## Manuel test

### DB Backup

MinIO Passwort auslesen

```bash
kubectl get secret minio -n minio-system -o jsonpath="{.data.rootPassword}" | base64 -d
```
MinIO User auslesen

```bash
kubectl get secret minio -n minio-system -o jsonpath="{.data.rootUser}" | base64 -d
```

Liste MinIO Pod-Liste

```bash
kubectl get pod -n minio-system
```

Erwarten:

```Code
NAME                     READY   STATUS    RESTARTS   AGE
minio-64b9f6bccd-5mnqb   1/1     Running   0          72m
```

In den MinIP Pod gehen

```bash
kubectl exec -it -n minio-system <MINIO-POD> -- sh
```

Mc alias setzen

```bash
mc alias set local http://localhost:9000 <USER> <PASSWORD>
```

Testen:

```bash
mc ls local
```

Erwarten:

```Code
[2026-05-06 12:00:17 UTC]     0B backups/
```

### DB Daten anlegen

Test direkt auf VM

```bash
kubectl exec -it -n database timescale-cluster-1 -- psql -U postgres
\c app
```

Testtabelle erstellen

```psql
CREATE TABLE test (id INT, value TEXT);
INSERT INTO test VALUES(1, 'before restore');
```

Prüfen:

```psql
SELECT * FROM test;
```

Backup erstellen

```bash
kubectl apply -f - <<EOF
apiVersion: postgresql.cnpg.io/v1
kind: Backup
metadata:
  name: restore-test-backup
  namespace: database
spec:
  cluster:
    name: timescale-cluster
EOF
```

Warten:

```bash
kubectl get backups -n database
```

Erwarten:

```Code
restore-test-backup   3m52s   timescale-cluster   barmanObjectStore   completed
```

### Daten ändern

```qsql
DELETE FROM test;
SELECT * FROM test
```

Restore Cluster erstellen

*Zeitpunkte einsetzen*

```bash
kubectl apply -f - <<EOF
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: timescale-restore-test
  namespace: database
spec:
  instances: 1

  imageName: ghcr.io/cloudnative-pg/postgresql:15

  bootstrap:
    recovery:
    source: minio-backup
        recoveryTarget:
        targetTime: "2026-05-06T14:11:00Z"


  storage:
    size: 10Gi

  externalClusters:
    - name: timescale-cluster
      barmanObjectStore:
        destinationPath: "s3://backups/"
        endpointURL: "http://minio.minio-system.svc.cluster.local:9000"
        s3Credentials:
          accessKeyId:
            name: s3-creds
            key: ACCESS_KEY_ID
          secretAccessKey:
            name: s3-creds
            key: SECRET_ACCESS_KEY
EOF
```

