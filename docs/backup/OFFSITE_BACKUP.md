# Homelab Offsite Backup: Encrypted User Data to AWS S3 Deep Archive

_Written 15 Oct 2026. AWS pricing, storage-class rules, rclone flags and Immich 3.0 folder layout should be re-verified against current docs before you rely on this._

> **Scope:** This is the **C (offsite) plane for Tier-4 user data** only. It complements — and does not replace — the Velero/Longhorn/K8s side of the ABC strategy documented in [README.md](./README.md) and [ARCHITECTURE.md](./ARCHITECTURE.md). Velero keeps handling Authentik's PostgreSQL (via a `pg_dump` hook), Obsidian, SSL certs, and any future cluster resources. Immich is deliberately **not** a Velero app — this plan is its backup.

---

## 1. Goals and constraints

- Back up only data that is **irreplaceable** (photos, notes, documents, rare media).
- **AWS must not be able to read anything**: contents and filenames are encrypted on my machine before upload.
- **No duplicate uploads**: unchanged files are never re-sent.
- **One tool only**: rclone (with its `crypt` layer).
- **Cheapest storage**: S3 Glacier Deep Archive. A restore taking 1 to 2 weeks end to end is acceptable.
- Out of scope: VM disks, Kubernetes volumes, Authentik, **Authentik's** PostgreSQL, and certificates. Those are handled separately by Velero.

> **Immich's database is *not* a Velero concern.** Velero only backs up Authentik's PostgreSQL (pg_dump hook). Immich's PostgreSQL runs on a Longhorn PVC with no Velero schedule; it is recovered from Immich's **own in-app DB dump**, which is written into `/data/backups/` and therefore *is* included in this offsite plan.

---

## 2. What gets backed up

The offsite selection is **per-folder (app-wise), not whole-NAS**. A whole-NAS copy would push re-downloadable arr media into Deep Archive (slow, expensive) and can't apply different modes/frequencies per data set. This mirrors the "per-app rclone, not whole-NFS" principle in [ARCHITECTURE.md](./ARCHITECTURE.md#rclone--tier-4-nfs-user-data).

All folders live under a **single** `vault:` crypt remote; each job's target mirrors the share tree (`vault:v1/personal/<app>`), so the bucket reproduces the NAS layout under one bucket — no need for multiple crypt remotes. Use **one job per folder whose policy differs**; group folders only when mode + frequency + exclusions are identical.

| Data | Local folder (example) | Mode | Frequency |
|---|---|---|---|
| Immich (library, upload, profile, **DB dumps**) | `/data/immich/{library,upload,profile,backups}` | `sync` | Monthly |
| Obsidian vault | `/data/obsidian` | `sync` | Weekly |
| Personal documents | `/data/docs` | `sync` | Weekly |
| Personal projects (Blender, UE5, Photoshop, …) | `/data/projects/<app>` | `sync` | Weekly |
| Home videos | `/data/home-videos` | `copy` | Monthly |
| Rare/special movies, rare music | `/data/rare-media` | `copy` | Monthly |
| Books / audiobooks | `/data/books` | `copy` | Monthly |
| arr stack (whole) | `/data/media` | TBD | Deferred — scope later |

**Not backed up (offsite)**

- Immich `thumbs/` and `encoded-video/`: Immich regenerates them.
- Regenerable project caches (e.g. UE5 `DerivedDataCache`, Blender temp) — keep sources/assets, drop the caches.
- Everything that lives in Kubernetes or on VMs (Velero's job).
- **VM/LXC data disks that live on the NAS pool.** Proxmox attaches these as ZFS **zvols** (e.g. `WD4TB/vm-1050-disk-*`), which are *not* files under the exported share tree — so the folder-scoped rclone jobs never include them, and the NFS export (`/WD4TB/shared`) doesn't expose them. Co-locating guest disks on the NAS pool does **not** pull them into the offsite copy.

> **arr stack — deferred.** Keep the arr stack as one item for now; don't split it into movies/TV/books or decide what within it is offsite. That scoping happens later, when we actually get to it.

> **Local vs offsite:** the NAS's own **ZFS snapshots** are per-dataset and cover *everything* (including arr media) — that's the fast, daily, local "B" layer. This offsite rclone selection is the narrower, expensive part, so it takes only the irreplaceable folders.

**Tips**

- Keep rare media in its **own folder outside anything Sonarr or Radarr manages**, so the arrs never rename or delete it and the backup rule stays "this folder".
- `sync` mirrors my current state, with an undo window from S3 versioning.
- `copy` never deletes anything remotely, so an accidental local delete can't propagate. Use it for write-once data.
- **Small-file economics:** Deep Archive charges a per-object overhead and a 180-day minimum per object, so very frequent syncs of thousands of tiny files are wasteful. This is why Immich is monthly and notes/docs are weekly rather than daily. *(In Phase 1, before the local NAS has redundancy, see §8 — you may temporarily want daily for the jobs whose only second copy is AWS.)*

---

## 3. Architecture

```
Local disk / NAS  ->  rclone (crypt: encrypts contents + filenames)  ->  S3 bucket (<aws-region>)
                                                                        storage class: DEEP_ARCHIVE
                                                                        versioning ON + lifecycle rules
```

- The `crypt` layer maps each local file to one encrypted S3 object, with encrypted filenames and directory names.
- restic and Kopia were considered and rejected: they need to read their own index and pack files, which isn't possible on Deep Archive.
- Trade-off accepted: no chunk-level dedup and no snapshot history. S3 versioning provides the undo window instead.

**Single owner.** The offsite job runs **once, from the NAS/Proxmox host** (a host-level cron/systemd timer running rclone). It is **not** run by an in-cluster CronJob. The in-cluster `immich-rclone-backup` component is retired (disabled/commented) so there is exactly one owner. When TrueNAS (or another NAS OS) is in place, the same sync can be moved to a NAS-native rclone/Cloud Sync task.

**Where this lives (IaC).** The host side is the `nas_server` role (target `proxmox_node`). Its toggles come from `topology.nodes.<node>.storage.backup`, with minimal-by-default fallbacks:

| Toggle | Default | Meaning |
|---|---|---|
| `snapshots.enabled` | `false` | local ZFS snapshots + prune (systemd timer) |
| `scrub.enabled` | `false` | scheduled `zpool scrub` |
| `smart.enabled` | `true` | `smartd` monitoring (no self-tests) |
| `rclone.enabled` | `false` (now set `true`) | offsite rclone to the **`atlas-homelab`** bucket — implemented; per-job systemd timers (obsidian weekly, immich monthly) |

The offsite `[aws]`/`[vault]` remote, per-app jobs and timers are written by `nas_server` from the inventory AWS vars (`aws_velero_*`, delivered by the `aws_kyoto` stack). One IAM user (`velero-backup`) covers both Velero and this offsite copy.

---

## 4. What happens when files change (with versioning on)

| Action on my side | Result in AWS |
|---|---|
| File unchanged | Skipped. Nothing uploaded. |
| File edited | New version uploaded. Old version kept as a hidden version until the retention window ends. |
| File deleted (`sync` jobs) | Disappears from the current backup. Hidden version kept until the window ends, then removed. |
| File deleted (`copy` jobs) | Stays in AWS permanently, because `copy` never deletes. |
| File moved or renamed | Same as delete plus new file: uploaded again under the new path, old path kept as a hidden version until the window ends. |
| Folder renamed | Every file inside is re-uploaded, and the old copies are kept for the window. Expensive for large folders. |

The retention clock starts when a version stops being current (deleted, replaced or renamed), not when it was first uploaded.

**Consequences**

- Don't reorganize large backed-up folders casually.
- Don't change Immich's storage template after the library is backed up: it moves every file and re-uploads everything.
- Run a `--dry-run` before any big reorganization to see exactly what would be uploaded or deleted.

---

## 5. AWS setup

- [ ] Enable MFA on the AWS root account.
- [ ] Create an **AWS Budgets** alert so a surprise bill can't sneak up on me.
- [ ] Create the bucket in your AWS account's region (`<aws-region>`) with **Block Public Access** fully on. The region is determined by the AWS account/connection — keep it **identical** across the bucket, the rclone `aws` remote, and the IAM policy.
- [ ] Turn on **bucket versioning**.
- [ ] Lifecycle rule: **expire noncurrent versions after 180 days**. Deep Archive has a **180-day minimum storage charge per object**, so 180 days is the cost-optimal noncurrent retention: you cannot save money by expiring versions earlier (the remaining days are still billed), and you don't want to pay for them beyond 180 days either.
- [ ] Lifecycle rule: remove expired delete markers.
- [ ] Lifecycle rule: abort incomplete multipart uploads after about 7 days.
- [ ] Create a **dedicated IAM user** with permissions limited to this one bucket (list, get, put, delete on that bucket only). Save its access key somewhere safe.

> **Why not special-case `backups/`?** With `directory_name_encryption = true`, S3 only sees encrypted key names, so a lifecycle rule cannot match the plaintext `backups/` prefix. It doesn't matter: the 180-day minimum applies to every noncurrent version anyway, so one bucket-wide noncurrent rule of 180 days is both the simplest and the cheapest option. (See §9 for how `backups/` retention actually behaves.)

---

## 6. rclone setup

Two remotes, configured with `rclone config`:

1. **`aws`**: an S3 remote for the bucket, matching `<aws-region>`, storage class `DEEP_ARCHIVE`, using the IAM user's keys.
2. **`vault`**: a crypt remote wrapping `aws:<bucket>`, with standard filename encryption and directory name encryption on. rclone generates and stores the password and salt.

**Safety rules for jobs**

- Use `sync` only for notes, docs and Immich. Use `copy` for videos and rare media.
- Add a delete limit (`--max-delete`) to every `sync` job. If the source disk fails to mount and looks empty, the limit stops it from wiping the remote.
- Run jobs through a small wrapper script that first checks the source disk is actually mounted.
- Skip Immich's `thumbs/` and `encoded-video/`.
- **Run from the NAS/Proxmox host only** (see §3). Don't also run the in-cluster job.

---

## 7. Schedule

| Time | Job |
|---|---|
| 02:00 daily | Immich creates its automatic DB dump (default schedule; verify in Immich settings) |
| 04:00, 1st of the month | `sync`: Immich (library, upload, profile, backups) |
| Sunday 05:00 | `sync`: obsidian, docs, projects |
| Sunday 06:00 | `copy`: home-videos, rare-media, books |

Run everything via cron or systemd timers **on the NAS/Proxmox host**. Log output to files, and ping a healthchecks.io URL on success so a silently failing backup gets noticed.

> Immich is monthly because of the small-file/Deep-Archive cost profile. Its *local* ZFS snapshots still run daily, so day-to-day recovery does not depend on this offsite copy — this copy covers site/hardware loss.

---

## 8. Phases

### Phase 1: bare HDD (now)

- A single disk with no redundancy means **AWS is my only second copy**, so the jobs whose data exists nowhere else should run more often than the schedule above until local redundancy exists (e.g. daily for notes/docs and Immich while the HDD is the only copy).
- Enable SMART monitoring (`smartd`) with email alerts.
- First upload is slow: roughly 2 days per TB at about 50 Mbps. Run it in `tmux`. If interrupted, just re-run it, since rclone skips what's already uploaded.

### Phase 2: TrueNAS Community Edition

- **Datasets:** one per category (`immich`, `notes`, `docs`, `home-videos`, `rare-media`, and `media` for the replaceable stuff). Only the first five go offsite.
- **Local protection:** start with at least a mirrored pool. Add periodic snapshots, scheduled scrubs and SMART tests. This covers disk failure and accidental deletion, and AWS covers everything else. Once this exists, the offsite cadence can relax to the monthly/weekly schedule in §7.
- **Where the job runs:** a container on TrueNAS with the datasets mounted read-only, or a small host over NFS. Avoid installing tools on the TrueNAS host itself. The job is owned by the NAS — not by Kubernetes.
- **Use rclone directly, not the TrueNAS Cloud Sync GUI.** TrueNAS docs advise against enabling filename encryption on new Cloud Sync tasks, which would expose filenames to AWS.
- **Back up the live dataset paths**, not `.zfs/snapshot` directories.
- **Migration without re-uploads:** rclone compares by relative path, size and modification time. When copying data to TrueNAS, **preserve timestamps** (for example `rsync -a`) and keep the same folder structure. Before the first real run, do a `--dry-run` and confirm it wants to upload nothing.
- Export the TrueNAS config after any major change and store it with my other secrets.

---

## 9. Checking what is backed up

All from my side, with rclone:

- **Browse the backup** with decrypted names: listing commands or `rclone ncdu` on the `vault:` remote.
- **Compare local against AWS** with `rclone check` (use `--one-way` and the `--missing-on-dst` style flags to list gaps). It compares existence and size, not content hashes, because encryption hides them. It's good for "is everything there?" but isn't bit-for-bit verification. **Don't use its download mode on Deep Archive.**
- **Preview a run** with `--dry-run`.
- **See old versions and delete markers** with rclone's S3 versions flags on the `aws:` remote.

### Content (hash) verification

`rclone check` on a crypt remote compares **size only** — crypt deliberately stores no plaintext hash, so there is no native "hash both sides" check. Options for real content verification:

1. **Hash manifest (recommended).** Keep a plaintext checksum manifest alongside the backup: generate `rclone hashsum sha256 /data/obsidian > obsidian.sha256` on the host and store the manifest locally (ZFS) *and* upload it (a tiny file). On restore, hash the restored files and diff against the manifest. This gives true end-to-end plaintext verification without touching Deep Archive.
2. **`rclone cryptcheck`.** This is the crypt-aware equivalent of `check`: it encrypts the *local* file with the nonce stored in the remote object and compares the underlying checksum, so it verifies the remote object decrypts to exactly the local file — without downloading. **Caveat:** it must read the object header (the nonce), so it does not work against cold Deep Archive objects; run it after a restore, or against a hot/standard copy. It also requires the underlying remote to expose a checksum.
3. **Authenticated encryption.** crypt uses NaCl SecretBox (XSalsa20 + Poly1305), so a corrupted object fails to decrypt loudly rather than silently returning bad bytes. This detects corruption at restore time, but it is not a "verify now" mechanism.

> Net: keep `rclone check` for existence/size, store a **SHA-256 manifest** for real verification, and trust Poly1305 to make corruption loud.

### Removing specific files

- Current copy: delete through the `vault:` remote. In a versioned bucket this only adds a delete marker, and the old version stays.
- Old versions: rclone has a cleanup command for hidden versions, but availability has varied between rclone versions. Otherwise use the AWS CLI or console. Names in the bucket are encrypted, so use rclone's name-decoding helper to translate.
- Rarely needed. The lifecycle rule removes old versions automatically, and deleting early doesn't refund the 180-day minimum. Only bother for privacy (permanently remove a sensitive file) or a huge accidental rename combined with a very long retention window.

### `backups/` retention, concretely

Immich keeps 14 DB dumps locally and rotates them. Under `sync` + bucket versioning, each rotated-out dump becomes a noncurrent version and is retained for the 180-day window. In steady state you keep on the order of ~180 dumps in Deep Archive. Each is billed at ~$0.00099/GB-month, so this is cents per month for typical dumps — acceptable, and it means you never have to think about special-casing it. If it ever becomes material, the only real lever is to stop versioning; but versioning is your only `sync` undo window, so keep it.

---

## 10. Restoring

> **RTO exception:** this offsite plane does **not** meet the platform's 12-hour RTO. Deep Archive retrieval is roughly **12 h (standard) to 48 h (bulk)**, and restoring multiple TB can take **1–2 weeks end to end**. That is an accepted exception for irreplaceable user data kept at the cheapest tier. The 12-hour RTO in [README.md](./README.md) still applies to cluster rebuild / Velero-managed restores, not to this cold offsite copy.

1. Ask AWS to **restore** the needed objects from Deep Archive to a temporary readable state (rclone's `backend restore` command, bulk priority, with a lifetime of about 2 weeks). In recent rclone versions this works through the crypt remote. Otherwise target the encrypted path on the `aws:` remote. Verify on my installed version.
2. **Wait.** Standard retrieval takes roughly 12 hours and bulk up to about 48 hours (verify current AWS docs).
3. `rclone copy` the restored data down from `vault:`. rclone decrypts as it goes.
4. Verify against the stored SHA-256 manifest (§9).
5. For Immich: restore the library folders and the latest DB dump from `backups/`, then follow Immich's own restore procedure ([`docs/runbooks/restore-immich.md`](../runbooks/restore-immich.md)).

**Costs:** retrieval and data-transfer-out are billed per GB. For a multi-TB restore, check the AWS pricing calculator first.

**Restore drill:** back up a small test folder, then do the full request, wait, download, decrypt and manifest-verify cycle once now, so the process isn't new during a real emergency. Repeat every few months with one photo, one note and the latest Immich DB dump.

---

## 11. Secrets to store (password manager + offline copy)

- **`rclone.conf`**: it holds the crypt password and salt. **Losing it makes every backup permanently unreadable.**
- The AWS IAM access key and secret.
- The healthchecks.io URL (optional).
- A one-page recovery runbook: AWS login, where `rclone.conf` is stored, the restore steps above.

Don't keep these only on the NAS or Immich server.

---

## 12. Pitfalls

- Renaming or moving large folders means a full re-upload plus double storage for the whole retention window.
- Deep Archive adds a small fixed overhead per object and charges a 180-day minimum **per object/version**, so very frequent syncs of thousands of tiny files are wasteful. Daily would be fine only for small, low-churn sets.
- `sync` with a missing or unmounted source can wipe the current backup. The delete limit and mount check guard against this.
- `copy`-mode folders never shrink in AWS: deleted or renamed files linger forever and keep costing money.
- Deleting or overwriting objects before 180 days still bills the remaining days — early deletion is **not** a refund.

---

## 13. Open items

- [x] Local paths + schedules — **done**: `storage.backup.rclone.jobs` (obsidian weekly, immich monthly); sources `/WD4TB/shared/v1/personal/<app>`.
- [x] Host-level systemd wrapper — **done**: `nas_server` installs a per-job wrapper (mount check → `--max-delete` → SHA-256 manifest) + systemd timers.
- [x] SHA-256 manifest generation — **done** (uploaded to `vault:manifests/<job>.sha256`).
- [x] Retire the in-cluster `immich-rclone-backup` — **done** (host is the single owner).
- [ ] **Alerting** — the healthchecks.io ping is wired but unused; route backup status to the in-cluster stack (Alertmanager/Grafana) instead — see `planning/BACKLOG.md`.
- [ ] Estimate the size of the rare-media set to forecast monthly cost.
- [ ] Scope the arr stack later (what, if anything, within `/data/media` goes offsite).
- [ ] Do the first restore drill (request → wait → download → decrypt → verify).

---

## Appendix: reference snippets

**`rclone.conf` skeleton**

```ini
[aws]
type = s3
provider = AWS
region = ap-southeast-1
access_key_id = <IAM key>
secret_access_key = <IAM secret>
storage_class = DEEP_ARCHIVE

[vault]
type = crypt
remote = aws:atlas-homelab
filename_encryption = standard
directory_name_encryption = true
password = <set via rclone config>
password2 = <set via rclone config>
```

**Jobs (run on the NAS/Proxmox host)**

```bash
# Immich (monthly): sync only the folders that matter
for d in library upload profile backups; do
  rclone sync /WD4TB/shared/v1/personal/immich/$d vault:v1/personal/immich/$d \
    --exclude "/thumbs/**" --exclude "/encoded-video/**" \
    --max-delete 100 --log-file /var/log/rclone/immich-$d.log
done

# notes + docs + projects (weekly)
rclone sync /WD4TB/shared/v1/personal/obsidian vault:v1/personal/obsidian --max-delete 50
rclone sync /WD4TB/shared/v1/personal/docs     vault:v1/personal/docs     --max-delete 50
for p in /WD4TB/shared/v1/personal/projects/*; do
  rclone sync "$p" "vault:v1/personal/projects/$(basename "$p")" \
    --exclude "**/DerivedDataCache/**" --exclude "**/Intermediate/**" \
    --max-delete 50
done

# videos + rare media + books (monthly, never delete remotely)
rclone copy /WD4TB/shared/v1/personal/home-videos vault:v1/personal/home-videos
rclone copy /WD4TB/shared/v1/personal/rare-media  vault:v1/personal/rare-media
rclone copy /WD4TB/shared/v1/personal/books       vault:v1/personal/books
```

**Checks, verification and restore**

```bash
rclone sync /WD4TB/shared/v1/personal/obsidian vault:v1/personal/obsidian --dry-run     # preview
rclone check /WD4TB/shared/v1/personal/obsidian vault:v1/personal/obsidian --one-way    # existence + size
rclone ncdu vault:                                      # browse backup (decrypted names)

# plaintext hash manifest (true content verification)
rclone hashsum sha256 /WD4TB/shared/v1/personal/obsidian > /var/log/rclone/obsidian.sha256
rclone copyto /var/log/rclone/obsidian.sha256 vault:manifests/obsidian.sha256

rclone backend restore vault:v1/personal/obsidian -o priority=Bulk -o lifetime=14   # request restore
rclone copy vault:v1/personal/obsidian /restore/obsidian            # after the wait
rclone hashsum sha256 /restore/obsidian | diff - /var/log/rclone/obsidian.sha256  # verify
```
