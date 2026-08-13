# Authentik Database Restore Runbook

**Use Case**: Disaster recovery, database corruption, deletion, or full rebuild.

**Behavior**: The `daily-security` Velero backup captures the Authentik namespace metadata **plus a fresh database dump** (written by a pre-hook in the always-running `authentik-db-dump` pod, captured as a file-system backup of the `authentik-db-backup` PVC). Restoring the database = Velero restore of the PVC, then importing the dump into PostgreSQL.

---

## Runbook Steps

### 1. Identify Backup Name
Find the latest backup name for Authentik:
```bash
kubectl get backups.velero.io -n backup -l velero.io/schedule-name=daily-security --sort-by=.metadata.creationTimestamp
```

### 2. Restore the Namespace + Dump Volume
**In-place restore (recommended for the drill, no namespace wipe):**

```bash
cat <<'EOF' | kubectl -n backup apply -f -
apiVersion: velero.io/v1
kind: Restore
metadata:
  name: security-restore
  namespace: backup
spec:
  backupName: <BACKUP_NAME>   # <-- replace
  includedNamespaces:
    - security
  existingResourcePolicy: none
  restorePVs: true
EOF
```

**If the whole namespace was deleted**, use a fresh restore of the full backup (same manifest above after recreating the namespace, or map into a new namespace with `namespaceMapping: security -> restore` and adjust the PVC references below accordingly).

Wait for completion:
```bash
kubectl -n backup get restore security-restore -o jsonpath='{.status.phase}' && echo ""
# Expected: Completed
```

> The restore brings back the `authentik-db-backup` PVC with the dump file on it. The `authentik-db-dump` deployment also comes back with it, so the dump pod is ready to serve the file.

### 3. Import the Database Dump
Apply the import job (kept in git but intentionally **not** applied by ArgoCD — it is destructive):

```bash
kubectl -n security apply -f \
  kubernetes/clusters/hyperion/velero/components/schedules/authentik/restore-import-job.yaml
```

The job will, in order:
1. Wait for PostgreSQL to be reachable.
2. Terminate connections to the `authentik` database.
3. Drop the `authentik` database.
4. Import the dump from `/backup/authentik-db.sql` (recreates the DB and all data).

Watch it:
```bash
kubectl -n security wait --for=condition=complete job/authentik-db-restore-import --timeout=10m
kubectl -n security logs job/authentik-db-restore-import
# Expected: "Restore complete."
```

### 4. Verify
```bash
# Authentik deployments should be running
kubectl -n security get deploy authentik-server authentik-worker

# Login to the Authentik UI with a known user (e.g. the drill test user)
# Or check directly in the DB:
kubectl -n security run verify-user --rm -i --restart=Never --image=postgres:18-alpine \
  --overrides='{"spec":{"securityContext":{"runAsNonRoot":true,"runAsUser":999,"runAsGroup":999,"seccompProfile":{"type":"RuntimeDefault"}},"containers":[{"name":"verify-user","image":"postgres:18-alpine","command":["sh","-c","export PGPASSWORD=$DB_PASSWORD; psql -h postgresql-18.storage.svc.cluster.local -U $DB_USERNAME -d $DB_DATABASE_NAME -c \"select username from authentik_user order by date_joined desc limit 5;\""],"securityContext":{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]}},"envFrom":[{"secretRef":{"name":"authentik-db-credentials"}}]}]}}'
```

### 5. Cleanup
```bash
kubectl -n backup delete restore security-restore
kubectl -n security delete job authentik-db-restore-import
```

---

## How the Backup Works (for reference)

- `authentik-db-dump` Deployment (always running, `postgres:18-alpine`, non-root) keeps the `authentik-db-backup` PVC mounted and holds the DB credentials.
- The Velero pre-hook (`pre.hook.backup.velero.io/*` annotations on that pod) runs `pg_dump` into `/backup/authentik-db.sql` at the start of every `daily-security` backup.
- Velero then captures the volume with the fresh dump (PodVolumeBackup) and uploads everything to the `aws` storage location — visible in the S1 backup dashboard.
- The old standalone `authentik-db-backup` CronJob was removed: the dump is produced at backup time, so there is no separate schedule to keep in sync.
- The manual DR manifests (Velero Restore template + DB import job) live together as unapplied templates in `kubernetes/clusters/hyperion/velero/components/schedules/authentik/`.
