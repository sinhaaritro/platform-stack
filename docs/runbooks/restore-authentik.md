# Authentik Database Restore Runbook

**Use Case**: Disaster recovery, database corruption, deletion, or full rebuild.

**Behavior**: The `daily-security` Velero backup captures the Authentik namespace **plus a fresh DB dump** (written by a pre-hook in the always-running `authentik-db-dump` pod, captured as a file-system backup of the `authentik-db-backup` PVC). Restore is **one procedure**: restore the dump PVC from Velero only if it is gone, then import the dump into PostgreSQL.

> **Prerequisite**: PostgreSQL must be running. For the full DR path, Velero must be running and Longhorn CSI must be ready (see Gotchas). The **fast path** only needs the live `authentik-db-backup` PVC and the `authentik-db-dump` pod.

---

## Restore procedure

> **Fast path:** check first:
> ```bash
> kubectl -n security get pvc authentik-db-backup
> kubectl -n security exec deploy/authentik-db-dump -- ls -lh /backup/authentik-db.sql
> ```
> If both exist, **skip Step 1** and go directly to Step 2, using the `security` job variant. If the PVC/dump is gone, start with Step 1.

### 1. Full DR — restore the dump PVC from Velero (only if the live PVC is gone)

Skip this step entirely for the fast path.

#### 1a. Identify the backup
```bash
kubectl get backups.velero.io -n backup -l velero.io/schedule-name=daily-security --sort-by=.metadata.creationTimestamp
```

#### 1b. Create the `restore` namespace and copy the admin secret
```bash
kubectl create ns restore
kubectl -n storage get secret postgres-18-admin -o json \
  | jq 'del(.metadata.resourceVersion,.metadata.uid,.metadata.creationTimestamp,.metadata.ownerReferences) | .metadata.namespace="restore"' \
  | kubectl apply -f -
```
The import job needs `postgres-18-admin` in the `restore` namespace. If `jq` is unavailable, use Python instead:

```bash
kubectl -n storage get secret postgres-18-admin -o json \
  | python3 -c 'import json,sys; d=json.load(sys.stdin); d["metadata"]={"name":"postgres-18-admin","namespace":"restore"}; print(json.dumps(d))' \
  | kubectl apply -f -
```

> **Fast path:** skip this entire step. The live `security` namespace already has `postgres-18-admin` and `authentik-db-credentials`, which the import job uses.

#### 1c. Apply the namespace-mapped restore
Edit `kubernetes/clusters/hyperion/velero/components/schedules/authentik/restore.yaml` — replace `BACKUP_NAME` with the backup name from 1a — then apply:
```bash
kubectl apply -f kubernetes/clusters/hyperion/velero/components/schedules/authentik/restore.yaml
```
The template carries `namespaceMapping: security → restore`, `existingResourcePolicy: none`, `restorePVs: true`.

#### 1d. Verify the restore, then scale down duplicates
```bash
kubectl -n backup get restore security-restore -o jsonpath='{.status.phase}' && echo ""
# Expected: Completed
kubectl -n backup get podvolumerestores.velero.io -l velero.io/restore-name=security-restore
# Expected: all Completed
kubectl -n restore get pods | grep authentik-db-dump
# Expected: 1/1 Running (dump PVC mounted)
```

> **Important — the namespace-mapped restore clones the entire `security` namespace** into `restore`, including duplicate `authentik-server`, `authentik-worker`, `external-secrets`, and `kyverno` deployments. Some will crash-loop. Keep `authentik-db-dump` (the import job uses its pod affinity), but scale the restored Authentik server/worker and the duplicate controllers to 0 so they don't touch the live DB:
> ```bash
> kubectl -n restore scale deploy/authentik-server --replicas=0
> kubectl -n restore scale deploy/authentik-worker --replicas=0
> kubectl -n restore get deploy   # also scale/delete external-secrets and kyverno-* copies
> ```

If the restore is PartiallyFailed/Failed, inspect:
```bash
kubectl get restore security-restore -n backup -o jsonpath='{.status}' | python3 -m json.tool
kubectl get restore security-restore -n backup -o json | python3 -c "import sys,json; d=json.load(sys.stdin); [print(json.dumps(v,indent=2)) for k,v in d.get('status',{}).items() if 'error' in k.lower() or 'warning' in k.lower()]"
kubectl logs -n backup -l app.kubernetes.io/name=velero --tail=50 | grep -i "security-restore"
```

### 2. Import the database dump

> **Before the import, pause Argo and stop the live Authentik** so it doesn't hold connections or rewrite the DB while the dump is imported:
> ```bash
> kubectl -n argocd scale statefulset/argocd-application-controller --replicas=0
> kubectl -n argocd scale deploy/argocd-applicationset-controller --replicas=0
> kubectl -n security scale deploy/authentik-server --replicas=0
> kubectl -n security scale deploy/authentik-worker --replicas=0
> ```
> Keep `authentik-db-dump` running.

Choose the variant that matches where the dump PVC is:

- **Full DR — dump restored into `restore`:**
  ```bash
  sed 's/namespace: security/namespace: restore/' \
    kubernetes/clusters/hyperion/velero/components/schedules/authentik/restore-import-job.yaml \
    | kubectl apply -f -
  kubectl -n restore wait --for=condition=complete job/authentik-db-restore-import --timeout=10m
  kubectl -n restore logs job/authentik-db-restore-import --tail=20
  ```

- **Fast path — live dump PVC in `security`:**
  ```bash
  kubectl apply -f kubernetes/clusters/hyperion/velero/components/schedules/authentik/restore-import-job.yaml
  kubectl -n security wait --for=condition=complete job/authentik-db-restore-import --timeout=10m
  kubectl -n security logs job/authentik-db-restore-import --tail=20
  ```

The job: waits for PostgreSQL → terminates connections → drops the `authentik` database → recreates it (app user as owner) → imports `/backup/authentik-db.sql` (pg_dump 18 control lines filtered).

### 3. Verify data restored

```bash
kubectl -n storage exec postgresql-18-0 -- psql -U postgres -d authentik -c \
  'select id, uuid, username, email from authentik_core_user order by id;'
# Expected: the original users/UUIDs, e.g. akadmin and aritrosinha

kubectl -n security get deploy authentik-server authentik-worker
# Expected: 1/1 Running after the restart in Step 4
```

Also log in to the Authentik UI with a known user.

### 4. Cleanup and restart

```bash
# remove the import job (one of these exists)
kubectl -n security delete job authentik-db-restore-import --ignore-not-found || true
kubectl -n restore delete job authentik-db-restore-import --ignore-not-found || true

# only if you did the namespace-mapped restore
kubectl -n backup delete restore security-restore --ignore-not-found || true
kubectl delete ns restore --ignore-not-found || true

# bring Authentik and Argo back
kubectl -n security scale deploy/authentik-server --replicas=1
kubectl -n security scale deploy/authentik-worker --replicas=1
kubectl -n argocd scale statefulset/argocd-application-controller --replicas=1
kubectl -n argocd scale deploy/argocd-applicationset-controller --replicas=1
kubectl -n security rollout status deploy/authentik-server --timeout=300s
kubectl -n security rollout status deploy/authentik-worker --timeout=300s
```

If you edited `restore.yaml`, reset the backup name placeholder:
```bash
sed -i 's/^  backupName: .*/  backupName: BACKUP_NAME # <-- REPLACE with actual backup name/' \
  kubernetes/clusters/hyperion/velero/components/schedules/authentik/restore.yaml
```

---

## Notes & Gotchas

- **Fast path**: if the live `authentik-db-backup` PVC exists, skip Step 1 and run the import in `security`. This is the validated path for drills, DB corruption, and app rebuilds; it avoids cloning the namespace.
- **Namespace-mapped restore clones everything**: it recreates all `security` resources in `restore` (authentik-server/worker, external-secrets, kyverno). Keep only `authentik-db-dump`; scale the rest to 0, and delete the `restore` namespace after the import. A restored Authentik server/worker can otherwise connect to the live DB.
- **Maintenance mode**: the procedure explicitly pauses Argo and scales `authentik-server`/`authentik-worker` to 0 before the import. The chart's `maintenance` component is an alternative if you prefer a Git-driven scale-down.
- **pg_dump 18**: dumps contain `\restrict`/`\unrestrict`/`DROP DATABASE`/`CREATE DATABASE`/`\connect` lines that break `psql -f` — the import job filters them. The users table is `authentik_core_user` (not `authentik_user`).
- **Import job stuck at `ContainerCreating`**: the dump PVC is `RWO` (one node at a time). If the job pod is scheduled on a different node than the `authentik-db-dump` pod, it hangs with `Multi-Attach error` — the template's `podAffinity` prevents this, but if it still happens, free the volume with `kubectl -n restore scale deployment authentik-db-dump --replicas=0` (the attach retries automatically; cleanup deletes the ns anyway).
- **Freshly rebuilt cluster**: the restore can hang `InProgress` at 129/129 items if Longhorn's CSI driver isn't registered yet (`FailedAttachVolume ... CSINode <node> does not contain driver driver.longhorn.io`). It self-heals in ~4-5 min once `kubectl get csinodes` shows the driver; wait for Longhorn CSI before starting the restore.
