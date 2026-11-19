# Immich Restore Runbook

**Use case**: disaster recovery, database corruption/deletion, or full rebuild.

> **Prerequisite**: Authentik must be running (Immich login goes through Authentik OAuth). On a freshly rebuilt cluster, wait for Longhorn CSI and the NFS mount to be ready before restoring.

---

## Data layout (Immich v3)

| Piece | Where | Backed up by |
|---|---|---|
| **Dataset** (media + dumps) | `immich` PVC — NFS, RWX, 50Gi, mounted at `/data` | In place on the NAS. Offsite: rclone → Cloud S3. Local ZFS snapshots are currently disabled. |
| — `upload/`, `library/` | originals + storage-template copies | as above |
| — `profile/`, `thumbs/`, `encoded-video/` | avatars / thumbnails / transcodes | `profile` yes; `thumbs` + `encoded-video` excluded (regenerable) |
| — `backups/` | app DB dumps (`immich-db-backup-<timestamp>-v<version>-pg<pg>.sql.gz`, keep 14, daily 02:00) | as above (**must** be included) |
| **Database** | PostgreSQL 18 on a **Longhorn** PVC (SSD) — *not* on the NAS | via the app dump in `/data/backups` |
| **K8s manifests / secrets** | Git (ArgoCD) | Git + SealedSecrets |

There is **no Velero schedule for Immich**. K8s state is recovered from Git; data is recovered from the dataset + the DB dump.

---

## Failure scenarios

Two independent halves. The **NAS half does not need Kubernetes** — never let a cluster drive a NAS rebuild. Do them in order.

| Scenario | NAS intact? | Authentik DB (OAuth) | Recovery |
|---|---|---|---|
| **A** — app/cluster lost | ✅ | Restore from the Velero `daily-security` backup **if the cluster/Authentik DB was lost**; required for OAuth | Rebuild cluster → **[2] Restore the app + database** |
| **B** — NAS/HDD lost | ❌ | Intact — the cluster survives; no Authentik restore is needed for OAuth | **[1] Restore the NAS dataset** → rebuild cluster → **[2] Restore the app + database** |

> **RPO**: Scenario A ≈ 1 day (newest local DB dump; no AWS restore). Scenario B = the offsite cadence (monthly until changed).

> **OAuth users:** Authentik's DB is a separate dependency from Immich. In Scenario A, if the whole cluster/Authentik DB was lost, restore Authentik first (`docs/runbooks/restore-authentik.md`). Immich's `user.oauthId` is only valid if Authentik is restored with the same user UUIDs; a fresh Authentik produces different `sub` values and OAuth login will fail. Scenario B leaves Authentik intact.

---

## 1. Restore the NAS dataset (from the S3 backup)

The dataset physically lives on the NAS, so restore it **on the NAS — no cluster required**. Rebuild the share first; the cluster comes later.

> **Run this on the Proxmox/NAS host `atlas` (`root@192.168.0.2`), not inside a pod.** The script lives at `/usr/local/sbin/nas-server-rclone-restore.sh` and uses `/root/.config/rclone/rclone.conf` plus the `/WD4TB/shared` ZFS/NFS export. This is why recovery still works when Kubernetes is down.

1. Ensure the target share exists and is empty. If Argo has already recreated the `immich` PVC, use its directory as-is — no separate share rebuild is needed.
2. **Thaw the archive copy, then pull the dataset back.** Thawing must target the `aws:` remote; the download goes through `vault:` so it is decrypted. The NAS role's wrapper does the whole cycle (request Bulk thaw → poll → copy → verify manifest):
   ```bash
   nas-server-rclone-restore.sh immich /WD4TB/shared/v1/personal/immich
   chown -R 1000:1000 /WD4TB/shared/v1/personal/immich
   ```
   Manual equivalent:
   ```bash
   rclone backend restore aws:atlas-homelab -o priority=Bulk -o lifetime=14
   rclone backend restore-status aws:atlas-homelab          # wait until no "IsRestoreInProgress": true
   rclone copy vault:v1/personal/immich /WD4TB/shared/v1/personal/immich \
     --transfers 4 --checkers 8 --verbose
   ```
   This restores `upload/`, `library/`, `profile/`, `backups/`. `thumbs/` and `encoded-video/` are regenerable and not in the backup — Immich regenerates them.
   > **Restore directly into the final dataset path** (`/WD4TB/shared/v1/personal/immich`), not a staging directory. In-place needs ~1× the data; a staging copy needs ~2× (old + restored), which will not fit on a nearly-full pool. The wrapper refuses to start if free space is insufficient: a populated/in-place destination needs 5 GiB of temp headroom; an empty destination needs ~110% of the remote dataset size. Stop Immich first **and pause the Argo controllers**; otherwise Argo recreates the Immich pods mid-copy. Resume Argo after the copy. `rclone copy` merges/overwrites and never deletes newer local files.
   > If a restore run is interrupted **after** the thaw finished, resume without waiting for AWS again: `SKIP_THAW=1 nas-server-rclone-restore.sh immich <dest>`.
   > The IAM policy must allow **`s3:RestoreObject`**. Without it every thaw request fails with `AccessDenied`, and Deep Archive objects cannot be downloaded at all. The thaw itself takes ~12 h (Standard) to ~48 h (Bulk).
   > The copy is ~335 MB but can take ~10 minutes depending on S3/network; plan the RTO accordingly.
---

## 2. Restore the app + database (from the app DB dump)

PostgreSQL lives on a Longhorn PVC (not the NAS), so a rebuilt cluster always starts with an **empty** DB. It is repopulated from Immich's own dump in `/data/backups/` (wherever those are — on the NAS share, and restored in step 1 if the NAS was lost).

> **Scenario A (NAS intact):** do not restore the NAS dataset and do not use AWS. Keep `/data` as-is; only the app and DB are rebuilt. If the whole cluster is lost, rebuild from Git and restore Authentik first. If only the Immich app/DB is lost, drop/recreate the DB and start the app — the PVC is already bound.

1. Rebuild/bring up the cluster from Git (or, if only the Immich app/DB was lost, recreate the DB and start the app); confirm the `immich` PVC binds to the (populated) share:
   ```bash
   kubectl -n personal get pvc immich
   kubectl -n personal exec deploy/immich-server -- ls /data   # upload library profile thumbs encoded-video backups
   ```
2. Restore the DB from the newest `/data/backups/*.sql.gz` via the maintenance UI (see **DB restore via the maintenance UI**). Use a dump taken after the OAuth link if you need the exact `oauthId`; a pre-link dump has `oauthId=""` and the first Authentik login links by email.
3. Log in and verify the timeline/albums.

---

## DB restore via the maintenance UI

Use the dump under `/data/backups/`. Immich v3 restores through its own maintenance UI/API.

1. If the app is running normally with an admin: **Administration → Maintenance → Restore database backup**.
2. If the DB is empty / no admin: the normal URL shows **“Server is restarting”** and will not show the restore menu. Get the maintenance URL from the logs:
   ```bash
   kubectl -n personal logs deploy/immich-server | grep -i maintenance
   ```
   Open the printed `/maintenance?token=...` URL (or the same path on either Immich host). The token expires in ~4 hours. Select the backup on that page.
3. Pick the newest `immich-db-backup-*.sql.gz`, not `restore-point-*`, and confirm.
4. Immich: creates a restore point → wipes the DB → restores the dump → runs migrations → health-checks. On failure it **auto-rolls back** to the restore point.

> The maintenance worker starts automatically when the DB has no admin. The normal UI stays on “Server is restarting” until the restore completes.

> **Lost the maintenance URL/token?** It is printed only when the maintenance worker starts. Check the current or previous container logs first:
> ```bash
> kubectl -n personal logs deploy/immich-server | grep -A1 -i "maintenance mode"
> kubectl -n personal logs deploy/immich-server --previous | grep -A1 -i "maintenance mode"
> ```
> If neither has it, restart the server and follow the logs; a fresh `/maintenance?token=...` URL is printed:
> ```bash
> kubectl -n personal rollout restart deploy/immich-server
> kubectl -n personal logs deploy/immich-server -f | grep -A1 -i "maintenance mode"
> ```
> The token expires in ~4 hours.
>
> You can also enable/regenerate maintenance mode directly:
> ```bash
> kubectl -n personal exec deploy/immich-server -- /usr/src/app/server/bin/immich-admin enable-maintenance-mode
> ```
> It prints the `/maintenance?token=...` URL, and regenerates the token if maintenance mode is already enabled.

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

- **Version pinning**: the dump filename embeds the Immich + PG version (`immich-db-backup-<timestamp>-v3.1.0-pg18.4.sql.gz`). Immich does not support downgrades — restore with the same or newer server version. The chart image is pinned in Git, so a rebuilt cluster boots the same version.
- **DB dump freshness**: daily at 02:00 UTC, keep 14. RPO for the DB = **1 day while the NAS survives**. The offsite copy syncs monthly, so a full NAS/site loss has a DB RPO of up to ~1 month.
- **Triggering a dump manually**: `POST /api/jobs` with `{"name":"backup-database"}` (admin session/API key). Logs show `Database Backup Starting/Success`.
- **The DB is not on the NAS**: a rebuilt cluster always starts with an empty Postgres — the dump in `backups/` is the bridge. The NAS ZFS snapshot (B) protects against data corruption/deletion while the HDD survives; it does not contain the DB. **ZFS snapshots are currently disabled** (`snapshots.enabled=false`), so there is no local rollback for accidental media deletion.
- **Offsite (C) is active on the NAS**: monthly rclone timer (`nas-server-rclone-immich.timer`). A NAS/site loss is recoverable, but only after a Deep Archive thaw (~12–48 h) and with an IAM policy that allows `s3:RestoreObject`.
- **`profile/` is cosmetic** (avatars) and *is* included offsite; `thumbs/` and `encoded-video/` are regenerable — deliberately excluded from the offsite sync.
- **OAuth dependency**: restore Authentik before Immich after a full rebuild.
- **OAuth linkage**: the DB dump includes `user.oauthId`. A dump taken after an OAuth login preserves the link; a pre-link dump has `oauthId=""` and the first Authentik login links by email. For the link to remain valid, Authentik must be restored with the same user UUIDs (`sub_mode=hashed_user_id`).
