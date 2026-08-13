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
**Namespace-mapped restore (recommended):** restores into a scratch `restore` namespace that ArgoCD does NOT manage. This is important: an *in-place* restore of the `authentik-db-backup` PVC races ArgoCD's prune/self-heal (the PVC carries the ArgoCD tracking annotation; if git and cluster drift, ArgoCD deletes the restored volume). The mapped restore avoids that entirely.

```bash
kubectl create ns restore
kubectl -n storage get secret postgres-18-admin -o json \
  | jq 'del(.metadata.resourceVersion,.metadata.uid,.metadata.creationTimestamp,.metadata.ownerReferences) | .metadata.namespace="restore"' \
  | kubectl apply -f -

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
  namespaceMapping:
    security: restore
  existingResourcePolicy: none
  restorePVs: true
EOF
```

**In-place restore** (same-namespace, when the app is in maintenance and git is aligned): use the manifest above *without* `namespaceMapping`. Only do this when the cluster git state matches what will be restored (e.g. after a full rebuild) — otherwise ArgoCD may prune the restored PVC.

Wait for completion:
```bash
kubectl -n backup get restore security-restore -o jsonpath='{.status.phase}' && echo ""
# Expected: Completed
```

> The restore brings back the `authentik-db-backup` PVC (in `restore` when mapped) with the dump file on it, plus the `authentik-db-credentials` secret. Verify the dump: mount the PVC or run the import job and check `/backup/authentik-db.sql` (should be ~8 MB and contain `COPY public.authentik_core_user`).

### 3. Import the Database Dump
Apply the import job (kept in git but intentionally **not** applied by ArgoCD — it is destructive). With a namespace-mapped restore, apply it in the `restore` namespace (and adjust the PVC claim reference — the job mounts `authentik-db-backup`, which exists there too):

```bash
sed 's/namespace: security/namespace: restore/' \
  kubernetes/clusters/hyperion/velero/components/schedules/authentik/restore-import-job.yaml \
  | kubectl apply -f -
```

The job will, in order:
1. Wait for PostgreSQL to be reachable.
2. Terminate connections to the `authentik` database.
3. Drop the `authentik` database.
4. Recreate it with the app user as owner.
5. Import the dump from `/backup/authentik-db.sql`, filtering out the pg_dump 18 `\restrict`/`\unrestrict`/`DROP DATABASE`/`CREATE DATABASE`/`\connect` lines (psql mis-handles them mid-script).

Watch it:
```bash
kubectl -n restore wait --for=condition=complete job/authentik-db-restore-import --timeout=10m
kubectl -n restore logs job/authentik-db-restore-import
# Expected: "Restore complete."
```

### 4. Verify
```bash
# Authentik deployments should be running
kubectl -n security get deploy authentik-server authentik-worker

# Login to the Authentik UI with a known user (e.g. the drill test user)
# Or check directly in the DB (note: the users table is authentik_core_user):
kubectl -n restore run verify-user --rm -i --restart=Never --image=postgres:18-alpine \
  --overrides='{"spec":{"securityContext":{"runAsNonRoot":true,"runAsUser":999,"runAsGroup":999,"seccompProfile":{"type":"RuntimeDefault"}},"containers":[{"name":"verify-user","image":"postgres:18-alpine","command":["sh","-c","export PGPASSWORD=$DB_PASSWORD; psql -h postgresql-18.storage.svc.cluster.local -U $DB_USERNAME -d $DB_DATABASE_NAME -c \"select username from authentik_core_user order by date_joined desc limit 5;\""],"securityContext":{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]}},"envFrom":[{"secretRef":{"name":"authentik-db-credentials"}}]}]}}'
```

### 5. Cleanup
```bash
kubectl -n backup delete restore security-restore
kubectl -n restore delete job authentik-db-restore-import
kubectl delete ns restore
```

---

## How the Backup Works (for reference)

- `authentik-db-dump` Deployment (always running, `postgres:18-alpine`, non-root) keeps the `authentik-db-backup` PVC mounted and holds the DB credentials.
- The Velero pre-hook (`pre.hook.backup.velero.io/*` annotations on that pod) runs `pg_dump` into `/backup/authentik-db.sql` at the start of every `daily-security` backup.
- Velero then captures the volume with the fresh dump (PodVolumeBackup) and uploads everything to the `aws` storage location — visible in the S1 backup dashboard.
- The old standalone `authentik-db-backup` CronJob was removed: the dump is produced at backup time, so there is no separate schedule to keep in sync.
- The manual DR manifests (Velero Restore template + DB import job) live together as unapplied templates in `kubernetes/clusters/hyperion/velero/components/schedules/authentik/`.

---

## Drill Log

### 2026-08-13 — Storage-wipe drill (first full DR exercise)

**Scope:** Delete the dump PVC (destroying the volume) + drop the live database, then restore from the `aws` S3 backup (kopia) and verify the web-UI test user `aritro` survives.

**Result: PASS** — `aritro` restored (verified in `authentik_core_user` and by authentik serving API/health checks afterwards).

**Sequence used:**
1. On-demand backup `authentik-drill` (label `velero.io/schedule-name: daily-security`, `storageLocation: aws`, `defaultVolumesToFsBackup: true`) — Completed, 0 errors, 197 items, dump refreshed by pre-hook.
2. Maintenance mode via the git maintenance component (extended to also scale `authentik-db-dump` to 0).
3. PVC `authentik-db-backup` deleted (Longhorn volume destroyed) — done via a temporary git commit removing `pvc.yaml` from the backup-job component (ArgoCD prune); `DROP DATABASE` executed against PostgreSQL.
4. **Namespace-mapped restore** `security -> restore` (existingResourcePolicy: none, restorePVs: true) — Completed, 0 errors; PVC recreated + PodVolumeRestore populated the dump from S3/kopia.
5. Import job applied in the `restore` namespace — Completed; `aritro` verified in DB.
6. Maintenance disabled (git), ArgoCD sync via `operation.sync` patch — deployments back to 1/1/1, app healthy.

**Learnings (already applied to this runbook / templates):**
- In-place velero restores of ArgoCD-tracked PVCs race the app controller's prune/self-heal (restored PVC carries the ArgoCD tracking annotation → pruned if git doesn't expect it). **Use namespace-mapped restores.**
- pg_dump 18 dumps contain `\restrict`/`\unrestrict` + `DROP DATABASE`/`CREATE DATABASE`/`\connect` lines that break `psql -f`; the import job now filters them and creates the database up front with the app user as owner (import runs as the app user, so object ownership is correct — PG15+ `public` schema is owned by `pg_database_owner`).
- The users table is `authentik_core_user` (not `authentik_user`) in current authentik versions.
- ArgoCD poll-based sync takes minutes; triggering `{"operation":{"sync":{...}}}` on the Application syncs immediately.
- ArgoCD self-heal recreates deleted PVCs that are in git within seconds — deleting a git-managed PVC requires a temporary git removal commit (prune) instead.
- Drilling with the maintenance component only: remember the maintenance patch must cover every deployment holding the PVC being wiped.
