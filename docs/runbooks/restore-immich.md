# Immich Database Restore Runbook

**Use Case**: Disaster recovery, database corruption, deletion, or full rebuild.

**Behavior**: The `daily-immich` Velero backup captures the Immich namespace **plus the app's own database dumps** (Immich v3 auto-dumps the DB daily at 02:00 UTC into `/data/backups` on the `immich-db-backup` PVC, keep-last-14). Restore = namespace-mapped Velero restore of the PVC, copy the newest dump onto the live PVC, then restore via the Immich web UI (Administration → Maintenance → Restore database backup).

> **Prerequisite**: Velero and Authentik must be running (Immich login goes through Authentik OAuth). On a freshly rebuilt cluster, wait for Longhorn CSI to be fully ready before restoring (see Gotchas).

---

## Runbook Steps

### 1. Identify Backup Name
```bash
kubectl get backups.velero.io -n backup -l velero.io/schedule-name=daily-immich --sort-by=.metadata.creationTimestamp
```
Use the newest `daily-immich-*` backup. Legacy `monthly-immich-*` backups contain the old plain-SQL `immich-db.sql` and are **not** restorable via the UI (they are deleted once the first `daily-immich` backup exists).

### 2. Restore (namespace-mapped)
```bash
kubectl create ns restore
```
Edit `kubernetes/clusters/hyperion/velero/components/schedules/immich/restore.yaml` — replace `BACKUP_NAME` with the backup name from Step 1 — then apply:
```bash
kubectl apply -f kubernetes/clusters/hyperion/velero/components/schedules/immich/restore.yaml
```
The template carries the namespace-mapped spec (`namespaceMapping: personal → restore`, PVCs only, `existingResourcePolicy: none`, `restorePVs: true`).

### 3. Verify Restore Completion
```bash
kubectl -n backup get restore immich-restore -o jsonpath='{.status.phase}' && echo ""
# Expected: Completed (inspect .status via `... -o jsonpath='{.status}' | python3 -m json.tool` if not)
kubectl -n backup get podvolumerestores.velero.io -l velero.io/restore-name=immich-restore
# Expected: all Completed
kubectl -n restore get pvc
# Expected: immich-db-backup Bound (1Gi)
```

To see the Errors/Warnings:
```bash
kubectl get restore immich-restore -n backup -o json | python3 -c "import sys,json; d=json.load(sys.stdin); [print(json.dumps(v,indent=2)) for k,v in d.get('status',{}).items() if 'error' in k.lower() or 'warning' in k.lower()]"
kubectl logs -n backup -l app.kubernetes.io/name=velero --tail=50 | grep -i "immich-restore"
```

### 4. Copy the Newest Dump to the Live PVC
The `immich-db-backup` PVC is `RWX`, so two pods can share it — but a pod can only mount claims from its own namespace, so the copy hops through your machine.

Spin up a reader pod on the restored PVC (`restore` ns):
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
kubectl -n restore wait pod/restore-temp --for=condition=Ready --timeout=120s
```

Download the newest app dump and push it onto the live PVC:
```bash
DUMP=$(kubectl exec -n restore restore-temp -- sh -c 'ls /data/immich-db-backup-*.sql.gz | tail -1')
kubectl cp restore/restore-temp:$DUMP /tmp/immich-dump.sql.gz
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: immich-live
  namespace: personal
spec:
  containers:
  - name: utils
    image: busybox
    command: ["sleep", "3600"]
    volumeMounts:
    - name: data
      mountPath: /data/backups
  volumes:
  - name: data
    persistentVolumeClaim:
      claimName: immich-db-backup
EOF
kubectl -n personal wait pod/immich-live --for=condition=Ready --timeout=120s
kubectl cp /tmp/immich-dump.sql.gz personal/immich-live:/data/backups/
kubectl -n personal exec immich-live -- ls -lh /data/backups/
```

**Verify the dump landed**:
```bash
kubectl -n personal exec deploy/immich-server -- ls -lh /data/backups/
# Expected: immich-db-backup-v<immich-version>-pg<pg-version>-<timestamp>.sql.gz
```

### 5. Restore via the Immich UI
1. Log in to Immich (via Authentik) and go to **Administration → Maintenance**.
2. Expand **Restore database backup** — the copied dump appears with its version and creation date.
3. Click **Restore** and confirm.
4. The server: creates a restore point of the current DB → wipes and restores the dump → runs any migrations → health-checks. On failure (e.g. corrupted dump), it rolls back to the restore point automatically.

### 6. Verify Data Restored
```bash
kubectl -n personal get deploy immich-server
# Expected: 1/1 Running
```
Log in with existing accounts and check the timeline/albums are present. The dump is only the database — media (photos/videos) is not in Velero backups.

### 7. Cleanup
```bash
kubectl -n backup delete restore immich-restore
kubectl -n restore delete pod restore-temp
kubectl delete ns restore
kubectl -n personal delete pod immich-live
sed -i 's/^  backupName: .*/  backupName: BACKUP_NAME # <-- REPLACE with actual backup name/' \
  kubernetes/clusters/hyperion/velero/components/schedules/immich/restore.yaml
```

---

## Notes & Gotchas

- **Version pinning**: the dump filename embeds the Immich version (`immich-db-backup-v3.1.0-pg18.1-...sql.gz`). Immich does not support downgrades — restore a dump with the same or newer server version. The chart image is pinned in git, so a rebuilt cluster boots the same version that wrote the dump.
- **Dump freshness**: the app dumps the DB daily at 02:00 UTC (keep last 14). `daily-immich` runs at 03:00 UTC — 1h after the dump — so every Velero backup captures a ≤1h-old dump. DB RPO = 1 day.
- **Triggering a dump manually**: Administration → Job Queues → **Create job** → **Create Database Dump** (API: `POST /api/jobs` with `{"name": "backup-database"}`). Logs show `Database Backup Starting/Success` in the `immich-server` pod.
- **Media is not in Velero backups** (library/upload/thumbs excluded by design; `immich-library` is NAS-backed). To restore media after a wipe: uncomment the maintenance component (`../../../apps/services/immich/components/maintenance` in `kubernetes/clusters/hyperion/immich/kustomization.yaml` — scales both deployments to 0), then run the rclone restore job (`kubernetes/clusters/hyperion/immich/components/rclone-archive/restore-job.yaml`) to copy `nas_backup/immich` → `/data`, then revert the maintenance component.
- **Maintenance mode**: optional for the DB restore — the UI restore happens on the running app and handles the wipe internally (restore point protects you). Only needed for the media rclone restore.
- **Freshly rebuilt cluster**: the restore can hang `InProgress` if Longhorn's CSI driver isn't registered yet (`CSINode <node> does not contain driver driver.longhorn.io`). It self-heals in ~4-5 min once `kubectl get csinodes` shows the driver.
- **OAuth dependency**: Immich login goes through Authentik — restore Authentik first after a full rebuild.
- **RWX PVC**: `immich-db-backup` is `ReadWriteMany`, so no multi-attach races (unlike the Authentik dump PVC).
- **In-place restore vs ArgoCD**: the namespace-mapped restore is the safe default (the live PVC carries the ArgoCD tracking annotation, so in-place restore races ArgoCD's self-heal). In-place is only safe when git matches the cluster (right after a full rebuild).

---

## Drill Log

| Date | Backup Used | Restore | Import | Result |
|---|---|---|---|---|
| _pending_ | `daily-immich-...` | Completed | UI restore | — |
