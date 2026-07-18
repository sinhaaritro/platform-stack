# Authentik Database Restore Runbook

**Use Case**: Disaster recovery, database corruption, deletion, or full rebuild.

**Behavior**: Restores the Authentik resources into the shared, unmanaged `restore` namespace, then imports the database dump.

---

## Runbook Steps

### 1. Identify Backup Name
Find the latest backup name for Authentik:
```bash
kubectl get backups.velero.io -n backup -l velero.io/schedule-name=daily-security --sort-by=.metadata.creationTimestamp
```

### 2. Update Restore Configuration
1. Replace `BACKUP_NAME` in `restore.yaml` with the identified backup name.
2. Apply the restore manifest:
   ```bash
   kubectl apply -f restore.yaml
   ```

### 3. Verify Velero Restore Completion
Check the restore status:
```bash
kubectl get restore security-restore -n backup -o jsonpath='{.status.phase}' && echo ""
```
**Expected output**:
```text
Completed
```

### 4. Restore Database from Dump
Deploy a temporary Postgres pod in the `restore` namespace mounting the restored `authentik-db-backup` volume, then run the database import command:

1. Deploy the temporary DB tool:
   ```bash
   cat <<'EOF' | kubectl apply -f -
   apiVersion: v1
   kind: Pod
   metadata:
     name: restore-temp
     namespace: restore
   spec:
     containers:
     - name: utils
       image: postgres:14-alpine
       command: ["sleep", "3600"]
       volumeMounts:
       - name: backup-data
         mountPath: /backup
     volumes:
     - name: backup-data
       persistentVolumeClaim:
         claimName: authentik-db-backup
   EOF
   ```
2. Wait for the pod to be Ready:
   ```bash
   kubectl wait pod/restore-temp -n restore --for=condition=Ready --timeout=120s
   ```
3. Extract DB credentials from Authentik configuration secrets:
   ```bash
   DB_USER=$(kubectl get secret authentik-db -n security -o jsonpath='{.data.username}' | base64 -d)
   DB_PASSWORD=$(kubectl get secret authentik-db -n security -o jsonpath='{.data.password}' | base64 -d)
   DB_NAME=$(kubectl get secret authentik-db -n security -o jsonpath='{.data.database}' | base64 -d)
   ```
4. Run the database import as postgres user:
   ```bash
   kubectl exec -i -n restore restore-temp -- sh -c 'PGPASSWORD="$DB_PASSWORD" psql -h postgresql-14.storage.svc.cluster.local -U "$DB_USER" -d "$DB_NAME" -f /backup/authentik-db.sql'
   ```
   **Expected output**:
   ```text
   Many lines of CREATE TABLE, ALTER TABLE, COPY, etc., ending with no errors.
   ```

### 5. Cleanup
Once verified, clean up temporary resources:
```bash
kubectl delete pod restore-temp -n restore
kubectl delete ns restore
kubectl delete restore security-restore -n backup
```
