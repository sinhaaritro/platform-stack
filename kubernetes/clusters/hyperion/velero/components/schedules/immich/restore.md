# Immich Hybrid Restore Runbook

**Use Case**: Disaster recovery, corruption, or database rollback.

**Behavior**: Restores the database dump into a temporary namespace and syncs the media library directly via Rclone.

---

## Runbook Steps

### 1. Enable Maintenance Mode
Scales Immich to `0` replicas via Git config to prevent database modifications during restore.
1. In `kubernetes/clusters/ruth/immich/kustomization.yaml`, uncomment the maintenance component:
   ```yaml
   components:
     - ../../../apps/services/immich/components/maintenance
   ```
2. Commit and push. Wait for ArgoCD to sync.
3. **Verify**:
   ```bash
   kubectl get deploy -n personal -l app.kubernetes.io/instance=immich
   ```
   **Expected output**:
   ```text
   NAME                      READY   UP-TO-DATE   AVAILABLE   AGE
   immich-machine-learning   0/0     0            0           30d
   immich-server             0/0     0            0           30d
   ```
   *(Ensure READY shows `0/0`)*

### 2. Run Rclone Restore
Syncs media files directly to the live PVC in the `personal` namespace:
```bash
kubectl create job --from=cronjob/immich-rclone-backup immich-rclone-restore -n personal --dry-run=client -o yaml \
  | sed 's/rclone sync \/data/rclone copy/g; s/aws:aritro-homelab\/nas_backup\/immich/aws:aritro-homelab\/nas_backup\/immich \/data/g' \
  | kubectl apply -f -
```

### 3. Wait for Rclone Completion
```bash
kubectl wait --for=condition=complete job/immich-rclone-restore -n personal --timeout=1h
```
**Expected output**:
```text
job.batch/immich-rclone-restore condition met
```

### 4. Prepare target namespace and trigger Velero restore
1. Find the latest backup name:
   ```bash
   kubectl get backups.velero.io -n backup --sort-by=.metadata.creationTimestamp
   ```
2. Replace `BACKUP_NAME` in `restore.yaml` (at the bottom of this directory).
3. Create the target restore namespace:
   ```bash
   kubectl create ns restore
   ```
4. Copy credentials/config secrets from `personal` to `restore` namespace (required by Velero/Kopia volume restore helper pods):
   ```bash
   kubectl get secret immich-config -n personal -o json | jq 'del(.metadata.ownerReferences, .metadata.uid, .metadata.resourceVersion, .metadata.creationTimestamp) | .metadata.namespace="restore"' | kubectl apply -f -
   kubectl get secret immich-db-credentials -n personal -o json | jq 'del(.metadata.ownerReferences, .metadata.uid, .metadata.resourceVersion, .metadata.creationTimestamp) | .metadata.namespace="restore"' | kubectl apply -f -
   ```
   **Verify**:
   ```bash
   kubectl get secret -n restore
   ```
   **Expected output**:
   ```text
   NAME                    TYPE     DATA   AGE
   immich-config           Opaque   1      10s
   immich-db-credentials   Opaque   3      10s
   ```
5. Pre-create mock `1Gi` PVCs in the `restore` namespace (this prevents duplicate 50Gi allocations in Longhorn):
   ```bash
   cat <<'EOF' | kubectl apply -f -
   apiVersion: v1
   kind: PersistentVolumeClaim
   metadata:
     name: immich-library
     namespace: restore
   spec:
     accessModes:
       - ReadWriteMany
     resources:
       requests:
         storage: 1Gi
     storageClassName: longhorn
   ---
   apiVersion: v1
   kind: PersistentVolumeClaim
   metadata:
     name: immich-machine-learning-cache
     namespace: restore
   spec:
     accessModes:
       - ReadWriteMany
     resources:
       requests:
         storage: 1Gi
     storageClassName: longhorn
   EOF
   ```
   **Verify**:
   ```bash
   kubectl get pvc -n restore
   ```
   **Expected output**:
   ```text
   NAME                            STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS   AGE
   immich-library                  Bound    pvc-4204a190-994c-4f63-b78c-ea89f35df873   1Gi        RWX            longhorn       10s
   immich-machine-learning-cache   Bound    pvc-d9a38a5f-ef5a-4bc4-aa0e-2a90234040ae   1Gi        RWX            longhorn       10s
   ```
6. Apply the Velero restore configuration:
   ```bash
   kubectl apply -f restore.yaml
   ```
7. Verify restore completion status:
   ```bash
   kubectl get restore immich-restore -n backup -o jsonpath='{.status.phase}' && echo ""
   ```
   **Expected output**:
   ```text
   Completed
   ```

### 5. Spin up temporary pod to mount restored volume
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
    image: busybox
    command: ["sleep", "3600"]
    volumeMounts:
    - name: data
      mountPath: /data
  volumes:
  - name: data
    persistentVolumeClaim:
      claimName: immich-db-backup
EOF
```
**Verify pod readiness**:
```bash
kubectl wait pod/restore-temp -n restore --for=condition=Ready --timeout=120s
```
**Expected output**:
```text
pod/restore-temp condition met
```

**Verify DB dump exists on the pod**:
```bash
kubectl exec -n restore restore-temp -- ls -lh /data
```
**Expected output**:
```text
total 43M    
-rw-r--r--    1 1000     1000       42.7M Jun 13 01:44 immich-db.sql
```

### 6. Import Database Dump directly into Postgres
1. Extract DB credentials from the secret:
   ```bash
   DB_USER=$(kubectl get secret immich-db-credentials -n restore -o jsonpath='{.data.DB_USERNAME}' | base64 -d)
   DB_PASSWORD=$(kubectl get secret immich-db-credentials -n restore -o jsonpath='{.data.DB_PASSWORD}' | base64 -d)
   DB_NAME=$(kubectl get secret immich-db-credentials -n restore -o jsonpath='{.data.DB_DATABASE_NAME}' | base64 -d)
   ```
2. Re-create the database `immich` owned by user `immich` and enable Postgres extensions:
   ```bash
   kubectl exec -i -n storage postgresql-14-0 -- psql -U postgres -c "DROP DATABASE IF EXISTS \"$DB_NAME\";"
   kubectl exec -i -n storage postgresql-14-0 -- psql -U postgres -c "CREATE USER \"$DB_USER\" WITH PASSWORD '$DB_PASSWORD';" || echo "User already exists, continuing..."
   ```
   ```bash
   kubectl exec -i -n storage postgresql-14-0 -- psql -U postgres -c "CREATE DATABASE \"$DB_NAME\" OWNER \"$DB_USER\";"
   kubectl exec -i -n storage postgresql-14-0 -- psql -U postgres -d "$DB_NAME" -c "CREATE EXTENSION IF NOT EXISTS vectors; GRANT ALL PRIVILEGES ON SCHEMA vectors TO \"$DB_USER\"; CREATE EXTENSION IF NOT EXISTS cube; CREATE EXTENSION IF NOT EXISTS earthdistance;"
   ```
   **Expected output**:
   ```text
   DROP DATABASE
   CREATE DATABASE
   CREATE EXTENSION
   ```
3. Stream the DB dump, filtering out incompatible DB-creation statements:
   ```bash
   kubectl exec -n restore restore-temp -- cat /data/immich-db.sql | \
     sed -E '/^(DROP DATABASE|CREATE DATABASE|ALTER DATABASE|\\connect postgres)/Id' | \
     kubectl exec -i -n storage postgresql-14-0 -- psql -U postgres -d "$DB_NAME"
   ```
   **Expected output**:
   Many lines of CREATE TABLE, COPY, ALTER TABLE, CREATE INDEX, etc., ending with no connection errors.
4. Fix object ownership in the `immich` database (changes owner of tables/sequences/views created as superuser `postgres` back to `immich`):
   ```bash
   kubectl exec -i -n storage postgresql-14-0 -- psql -U postgres -d "$DB_NAME" -c '
   DO $$
   DECLARE
       r RECORD;
   BEGIN
       IF (SELECT pg_catalog.pg_get_userbyid(nspowner) FROM pg_catalog.pg_namespace WHERE nspname = '\''public'\'') = '\''postgres'\'' THEN
           EXECUTE '\''ALTER SCHEMA public OWNER TO immich'\'';
       END IF;
       FOR r IN (
           SELECT tablename FROM pg_tables 
           WHERE schemaname = '\''public'\'' 
             AND (SELECT pg_catalog.pg_get_userbyid(relowner) FROM pg_catalog.pg_class WHERE relname = tablename AND relnamespace = (SELECT oid FROM pg_namespace WHERE nspname = '\''public'\'')) = '\''postgres'\''
       ) LOOP
           EXECUTE '\''ALTER TABLE public.'\'' || quote_ident(r.tablename) || '\'' OWNER TO immich'\'';
       END LOOP;
       FOR r IN (
           SELECT sequencename FROM pg_sequences 
           WHERE schemaname = '\''public'\'' 
             AND (SELECT pg_catalog.pg_get_userbyid(relowner) FROM pg_catalog.pg_class WHERE relname = sequencename AND relnamespace = (SELECT oid FROM pg_namespace WHERE nspname = '\''public'\'')) = '\''postgres'\''
       ) LOOP
           EXECUTE '\''ALTER SEQUENCE public.'\'' || quote_ident(r.sequencename) || '\'' OWNER TO immich'\'';
       END LOOP;
       FOR r IN (
           SELECT viewname FROM pg_views 
           WHERE schemaname = '\''public'\'' 
             AND (SELECT pg_catalog.pg_get_userbyid(relowner) FROM pg_catalog.pg_class WHERE relname = viewname AND relnamespace = (SELECT oid FROM pg_namespace WHERE nspname = '\''public'\'')) = '\''postgres'\''
       ) LOOP
           EXECUTE '\''ALTER VIEW public.'\'' || quote_ident(r.viewname) || '\'' OWNER TO immich'\'';
       END LOOP;
       FOR r IN (
           SELECT matviewname FROM pg_matviews 
           WHERE schemaname = '\''public'\'' 
             AND (SELECT pg_catalog.pg_get_userbyid(relowner) FROM pg_catalog.pg_class WHERE relname = matviewname AND relnamespace = (SELECT oid FROM pg_namespace WHERE nspname = '\''public'\'')) = '\''postgres'\''
       ) LOOP
           EXECUTE '\''ALTER MATERIALIZED VIEW public.'\'' || quote_ident(r.matviewname) || '\'' OWNER TO immich'\'';
       END LOOP;
   END
   $$;
   '
   ```
   **Expected output**:
   ```text
   DO
   ```
   **Verify table owner is now `immich`**:
   ```bash
   kubectl exec -i -n storage postgresql-14-0 -- psql -U postgres -d immich -c "SELECT c.relname, pg_catalog.pg_get_userbyid(c.relowner) as owner FROM pg_catalog.pg_class c JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace WHERE c.relname = 'kysely_migrations_lock' AND n.nspname = 'public';"
   ```
   **Expected output**:
   ```text
   relname                 | owner  
   ------------------------+--------
   kysely_migrations_lock | immich
   ```

### 7. Disable Maintenance Mode
1. In `kubernetes/clusters/ruth/immich/kustomization.yaml`, comment out the maintenance component:
   ```yaml
   components:
     # - ../../../apps/services/immich/components/maintenance
   ```
2. Commit and push. ArgoCD will scale Immich replicas back to `1`.
3. To trigger DB migrations instantly, delete the Immich server pod to recreate it:
   ```bash
   kubectl delete pod -n personal -l app.kubernetes.io/name=immich,app.kubernetes.io/component=server
   ```
4. **Verify**:
   ```bash
   kubectl get pods -n personal -l app.kubernetes.io/instance=immich
   ```
   **Expected output**:
   Both server and machine-learning pods showing `Running` status and `1/1 READY`.

### 8. Cleanup
Once verified, clean up temporary resources:
```bash
kubectl delete pod restore-temp -n restore
kubectl delete ns restore
kubectl delete restore immich-restore -n backup
kubectl delete job immich-rclone-restore -n personal
```
