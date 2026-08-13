# Authentik Database Restore Runbook

**Use Case**: Disaster recovery, database corruption, deletion, or full rebuild.

**Behavior**: The `daily-security` Velero backup captures the Authentik namespace **plus a fresh DB dump** (written by a pre-hook in the always-running `authentik-db-dump` pod, captured as a file-system backup of the `authentik-db-backup` PVC). Restore = namespace-mapped Velero restore of the PVC, then import the dump into PostgreSQL.

> **Prerequisite**: Velero and PostgreSQL must be running. On a freshly rebuilt cluster, wait for Longhorn CSI to be fully ready before restoring (see Gotchas).

---

## Runbook Steps

### 1. Identify Backup Name
```bash
kubectl get backups.velero.io -n backup -l velero.io/schedule-name=daily-security --sort-by=.metadata.creationTimestamp
```

### 2. Restore (namespace-mapped)
```bash
kubectl create ns restore
kubectl -n storage get secret postgres-18-admin -o json \
  | jq 'del(.metadata.resourceVersion,.metadata.uid,.metadata.creationTimestamp,.metadata.ownerReferences) | .metadata.namespace="restore"' \
  | kubectl apply -f -
```

Edit `kubernetes/clusters/hyperion/velero/components/schedules/authentik/restore.yaml` — replace `BACKUP_NAME` with the backup name from Step 1 — then apply:
```bash
kubectl apply -f kubernetes/clusters/hyperion/velero/components/schedules/authentik/restore.yaml
```
The template already carries the namespace-mapped spec (`namespaceMapping: security → restore`, `existingResourcePolicy: none`, `restorePVs: true`).

### 3. Verify Restore Completion
```bash
kubectl -n backup get restore security-restore -o jsonpath='{.status.phase}' && echo ""
# Expected: Completed (inspect .status via `... -o jsonpath='{.status}' | python3 -m json.tool` if not)
kubectl -n backup get podvolumerestores.velero.io -l velero.io/restore-name=security-restore
# Expected: all Completed
kubectl -n restore get pods | grep authentik-db-dump
# Expected: 1/1 Running (dump PVC mounted)
```

To inspect details if PartiallyFailed or Failed:
```bash
kubectl get restore security-restore -n backup -o jsonpath='{.status}' | python3 -m json.tool
```

To see the Errors
```bash
kubectl get restore security-restore -n backup -o json | python3 -c "import sys,json; d=json.load(sys.stdin); [print(json.dumps(v,indent=2)) for k,v in d.get('status',{}).items() if 'error' in k.lower() or 'warning' in k.lower()]"
kubectl logs -n backup -l app.kubernetes.io/name=velero --tail=50 | grep -i "security-restore"
```

### 4. Import the Database Dump
```bash
sed 's/namespace: security/namespace: restore/' \
  kubernetes/clusters/hyperion/velero/components/schedules/authentik/restore-import-job.yaml \
  | kubectl apply -f -
kubectl -n restore wait --for=condition=complete job/authentik-db-restore-import --timeout=10m
```
The job: waits for PostgreSQL → terminates connections → drops the `authentik` database → recreates it (app user as owner) → imports `/backup/authentik-db.sql` (pg_dump 18 control lines filtered).

### 5. Verify Data Restored
```bash
kubectl -n security get deploy authentik-server authentik-worker
# Expected: 1/1 Running

kubectl -n restore run verify-user --rm -i --restart=Never --image=postgres:18-alpine \
  --overrides='{"spec":{"securityContext":{"runAsNonRoot":true,"runAsUser":999,"runAsGroup":999,"seccompProfile":{"type":"RuntimeDefault"}},"containers":[{"name":"verify-user","image":"postgres:18-alpine","command":["sh","-c","export PGPASSWORD=$DB_PASSWORD; psql -h postgresql-18.storage.svc.cluster.local -U $DB_USERNAME -d $DB_DATABASE_NAME -c \"select username from authentik_core_user order by date_joined desc limit 5;\""],"securityContext":{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]}},"envFrom":[{"secretRef":{"name":"authentik-db-credentials"}}]}]}}'
# Expected: the backup's users, e.g. aritro (the drill test user)
```
Also log in to the Authentik UI with a known user.

### 6. Cleanup
```bash
kubectl -n backup delete restore security-restore
kubectl -n restore delete job authentik-db-restore-import
kubectl delete ns restore
sed -i 's/^  backupName: .*/  backupName: BACKUP_NAME # <-- REPLACE with actual backup name/' \
  kubernetes/clusters/hyperion/velero/components/schedules/authentik/restore.yaml
```

---

## Notes & Gotchas

- **Maintenance mode**: not needed for the Velero restore (namespace-mapped restore never touches the live `security` namespace). Recommended before the import job: uncomment `../../../apps/infrastructure/authentik/components/maintenance` in `kubernetes/clusters/hyperion/authentik/kustomization.yaml` (scales `authentik-server`/`authentik-worker` to 0), sync, run Step 4, then revert and sync. This avoids app errors/retries and migration races while the DB is dropped and recreated.
- **In-place restore vs ArgoCD**: an in-place restore of the `authentik-db-backup` PVC races ArgoCD's prune/self-heal (the PVC carries the ArgoCD tracking annotation → pruned if git and cluster drift). Use the namespace-mapped restore; in-place is only safe when git matches the cluster (e.g. right after a full rebuild) — remove the `namespaceMapping` block from `restore.yaml`.
- **pg_dump 18**: dumps contain `\restrict`/`\unrestrict`/`DROP DATABASE`/`CREATE DATABASE`/`\connect` lines that break `psql -f` — the import job filters them. The users table is `authentik_core_user` (not `authentik_user`).
- **Import job stuck at `ContainerCreating`**: the dump PVC is `RWO` (one node at a time). If the job pod is scheduled on a different node than the `authentik-db-dump` pod, it hangs with `Multi-Attach error` — the template's `podAffinity` prevents this, but if it still happens, free the volume with `kubectl -n restore scale deployment authentik-db-dump --replicas=0` (the attach retries automatically; cleanup deletes the ns anyway).
- **Freshly rebuilt cluster**: the restore can hang `InProgress` at 129/129 items if Longhorn's CSI driver isn't registered yet (`FailedAttachVolume ... CSINode <node> does not contain driver driver.longhorn.io`). It self-heals in ~4-5 min once `kubectl get csinodes` shows the driver; wait for Longhorn CSI before starting the restore.

---
