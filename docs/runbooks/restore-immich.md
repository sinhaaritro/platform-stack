# Immich Restore Runbook

**Use case**: disaster recovery, database corruption/deletion, or full rebuild.

> **Prerequisite**: Authentik must be running (Immich login goes through Authentik OAuth). On a freshly rebuilt cluster, wait for Longhorn CSI and the NFS mount to be ready before restoring.

---

## Data layout (Immich v3)

| Piece | Where | Backed up by |
|---|---|---|
| **Dataset** (media + dumps) | `immich` PVC — NFS, RWX, 50Gi, mounted at `/data` | Local: ZFS snapshots (NAS). Offsite: rclone → Cloud S3 |
| — `upload/`, `library/` | originals + storage-template copies | as above |
| — `profile/`, `thumbs/`, `encoded-video/` | avatars / thumbnails / transcodes | `profile` yes; `thumbs` + `encoded-video` excluded (regenerable) |
| — `backups/` | app DB dumps (`immich-db-backup-<immich>-pg<pg>-<ts>.sql.gz`, keep 14, daily 02:00) | as above (**must** be included) |
| **Database** | PostgreSQL 18 on a **Longhorn** PVC (SSD) — *not* on the NAS | via the app dump in `/data/backups` |
| **K8s manifests / secrets** | Git (ArgoCD) | Git + SealedSecrets |

There is **no Velero schedule for Immich**. K8s state is recovered from Git; data is recovered from the dataset + the DB dump.

---

## Failure scenarios

Two independent halves. The **NAS half does not need Kubernetes** — never let a cluster drive a NAS rebuild. Do them in order.

| Scenario | NAS intact? | Recovery |
|---|---|---|
| **A** — app/cluster lost | ✅ | Rebuild cluster → **[2] Restore the app + database** |
| **B** — NAS/HDD lost | ❌ | **[1] Restore the NAS dataset** → rebuild cluster → **[2] Restore the app + database** |

> **RPO**: Scenario A ≈ 1 day (last DB dump). Scenario B = the offsite cadence (monthly until changed).

---

## Enabling the offsite backup (once, when destination is decided)

The `rclone-backup` component ships **disabled** (`suspend: true`) with a dummy destination.

1. Set the destination in `kubernetes/clusters/hyperion/immich/components/rclone-backup/kustomization.yaml`:
   ```yaml
   configMapGenerator:
     - name: immich-backup-config
       behavior: replace
       literals:
         - DESTINATION=aws:<bucket>/immich
   ```
2. Uncomment **both** lines in `kubernetes/clusters/hyperion/immich/kustomization.yaml`:
   ```
   - ../../../apps/services/immich/components/rclone-backup
   - ./components/rclone-backup
   ```
3. Flip `suspend: true` → `false` in `kubernetes/apps/services/immich/components/rclone-backup/cronjob.yaml`.
4. Sync ArgoCD. Verify:
   ```bash
   kubectl -n personal get cronjob immich-rclone-backup      # SUSPEND should be False
   kubectl -n personal get secret immich-aws-creds           # creds decrypted
   kubectl -n personal get cm immich-backup-config -o jsonpath='{.data.DESTINATION}'
   ```
5. Dry-run it once:
   ```bash
   kubectl -n personal create job --from=cronjob/immich-rclone-backup immich-rclone-backup-manual
   kubectl -n personal logs -f job/immich-rclone-backup-manual
   ```

> This is the in-cluster option. It can equally be owned by the NAS itself (e.g. a TrueNAS Cloud Sync task on the share, which is rclone under the hood) — same destination, same restore commands below, but it also works when Kubernetes is down. Pick one owner; do not run both.

---

## 1. Restore the NAS dataset (from the S3 backup)

The dataset physically lives on the NAS, so restore it **on the NAS — no cluster required**. Rebuild the share first; the cluster comes later.

1. Rebuild the NAS share (empty).
2. On the NAS (or any host that can reach both S3 and the share), pull the dataset back from the offsite copy:
   ```bash
   rclone copy aws:<bucket>/immich /mnt/data/contents/private/immich \
     --transfers 4 --checkers 8 --verbose
   chown -R 1000:1000 /mnt/data/contents/private/immich
   ```
   This restores `upload/`, `library/`, `profile/`, `backups/`. `thumbs/` and `encoded-video/` are regenerable and not in the backup — Immich regenerates them.
3. **Alternate path — only if the cluster is already up** and the `immich` PVC is bindable: apply the manual Job, which runs the *same* `rclone copy` into `/data`:
   ```bash
   kubectl apply -f kubernetes/apps/services/immich/components/rclone-backup/restore-job.yaml
   kubectl -n personal logs -f job/immich-rclone-restore
   kubectl -n personal delete job immich-rclone-restore
   ```
   The Job is **not** referenced by kustomize on purpose — ArgoCD must never auto-run it.

> During a real NAS rebuild the Immich pods can't mount the `immich` PVC at all, so the Job is impossible — use the NAS-side copy.

---

## 2. Restore the app + database (from the app DB dump)

PostgreSQL lives on a Longhorn PVC (not the NAS), so a rebuilt cluster always starts with an **empty** DB. It is repopulated from Immich's own dump in `/data/backups/` (wherever those are — on the NAS share, and restored in step 1 if the NAS was lost).

1. Rebuild/bring up the cluster from Git; confirm the `immich` PVC binds to the (populated) share:
   ```bash
   kubectl -n personal get pvc immich
   kubectl -n personal exec deploy/immich-server -- ls /data   # upload library profile thumbs encoded-video backups
   ```
2. Restore the DB from the newest `/data/backups/*.sql.gz` via the maintenance UI (see **DB restore via the maintenance UI**).
3. Log in and verify the timeline/albums.

---

## DB restore via the maintenance UI

Use the dump under `/data/backups/`. Immich v3 restores through its own maintenance UI/API.

1. Open Immich. If it is in **maintenance mode** (unable to start normally, e.g. no admin), go to the maintenance URL printed in the server logs:
   ```bash
   kubectl -n personal logs deploy/immich-server | grep -i maintenance
   ```
2. Go to **Administration → Maintenance → Restore database backup**, pick the newest dump, and confirm.
3. Immich: creates a restore point → wipes the DB → restores the dump → runs migrations → health-checks. On failure it **auto-rolls back** to the restore point.

**Pick the right file.** `restore-point-immich-db-backup-*.sql.gz` files are snapshots Immich takes *immediately before* each restore — they reflect the **current (often empty) DB**, not your data. Always pick `immich-db-backup-*.sql.gz`.

**"Server health check failed, no admin exists"** = the restored DB had no active admin. It is a *database* check — unrelated to the `profile/` folder (which only holds avatars). Verify the dump actually has an admin:

```bash
# in the immich-server pod
zcat /data/backups/<dump>.sql.gz | \
  awk '/^COPY public."user" /{f=1;next} f&&/^\\\.$/{exit} f{print}' | cut -f1,2,6,8,15
# cols: id, email, isAdmin, deletedAt, status
```

---

## Notes & Gotchas

- **Version pinning**: the dump filename embeds the Immich + PG version (`immich-db-backup-v3.1.0-pg18.4-...sql.gz`). Immich does not support downgrades — restore with the same or newer server version. The chart image is pinned in Git, so a rebuilt cluster boots the same version.
- **DB dump freshness**: daily at 02:00 UTC, keep 14. RPO for the DB = 1 day.
- **Triggering a dump manually**: `POST /api/jobs` with `{"name":"backup-database"}` (admin session/API key). Logs show `Database Backup Starting/Success`.
- **The DB is not on the NAS**: a rebuilt cluster always starts with an empty Postgres — the dump in `backups/` is the bridge. The NAS ZFS snapshot (B) protects against data corruption/deletion while the HDD survives; it does not contain the DB.
- **Offsite (C) is opt-in**: until the offsite job is enabled/owned, a NAS/site loss is unrecoverable. Treat NAS recovery as unavailable until then.
- **`profile/` is cosmetic** (avatars); `thumbs/` and `encoded-video/` are regenerable — deliberately excluded from the offsite sync.
- **OAuth dependency**: restore Authentik before Immich after a full rebuild.

---

## Drill Log

| Date | Backup Used | Restore | Result |
|---|---|---|---|
| _pending_ | `immich-db-backup-...` | UI restore | — |
