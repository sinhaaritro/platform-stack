# Rebuild from Scratch (Disaster Recovery)

> **Scope:** rebuild the on-prem platform — Proxmox VMs/LXCs, the host-level NAS, k3s, and the apps — from **Git** (schema + config) plus the **offsite backup** (rclone crypt on S3).
> **Related:** [NFS](../storage/NFS.md) · [OFFSITE_BACKUP](../backup/OFFSITE_BACKUP.md) · [NAS Platform Matrix](../storage/NAS_PLATFORM_MATRIX.md) · [restore-immich](restore-immich.md) · [restore-obsidian](restore-obsidian.md) · [restore-ssl-cert](restore-ssl-cert.md)

---

## What you need beforehand
- The **repo** (schema, roles, k8s manifests) and **`ANSIBLE_VAULT_PASSWORD`**.
  You do **not** retype the rclone crypt password/salt or the AWS key during a normal
  rebuild — they live in the ansible-vault (`schema.secret.tfvars` / the `aws_kyoto`
  secret) and Tofu bridges them into the inventory (`rclone.conf`).
- **Break-glass copies, held OUTSIDE the vault** — because a normal rebuild relies on
  the vault being readable:
  - the **rclone crypt password + salt** (password manager **and** offline copy). This is
    the *only* key that decrypts the offsite backup; if the vault or its password is lost,
    the backups are permanently unreadable (`docs/backup/OFFSITE_BACKUP.md` §11);
  - the **AWS IAM `velero-backup` key** (also present in AWS itself).
- The **`aws_kyoto` Tofu state** (restore/import it — see [Known gaps](#known-gaps)) so the
  AWS keys reach `ansible/inventory.d/aws_kyoto.yml`.
- A Proxmox VE install ISO.

## The golden rule
**Restore the NAS data BEFORE the apps start.** Apps that load their data at startup must find it already in place; running them against an empty share first, then restoring on top, causes conflicts.

---

## Steps

### 0. Bootstrap the host + repo
1. Install Proxmox VE: root password, hostname, static IP.
2. Add the control-plane SSH key (see [proxmox-setup](../guides/proxmox-setup.md)).
3. On the control machine: clone the repo, then `export ANSIBLE_VAULT_PASSWORD="…"`.
4. **Enable the OS-SSD image/template datastore.** Tofu uploads OS images (`import`) and LXC templates (`vztmpl`) to `local` (on the OS SSD), and guest disks live on `local-lvm`. So the NODE phase (step 1) needs **no** data datastore; the GUEST phase (step 3) needs `WD4TB`, which the NODE phase creates:
   ```bash
   pvesm set local --content snippets,rootdir,import,vztmpl,iso
   ```

### 1. NODE phase — inventory + NAS storage (Tofu → Ansible)
```bash
task apply:node STACK_NAME=proxmox_atlas
```
The combined form of two per-tool tasks (run them separately if you prefer):
- **`tofu:apply:node`** — writes `ansible/inventory.d/proxmox_atlas.yml` (the NAS `storage` contract on the provider + `nas_mounts` on clients). Creates **no VM/LXC** — the inventory is built from the schema's static IPs, not from created-guest output — so it runs before any guest exists.
- **`ansible:apply:node`** — creates the ZFS pool + `WD4TB/shared` dataset + share roots + `/etc/exports` + Samba, and registers the `WD4TB` datastore with Proxmox (needed by the GUEST phase).

The share now exists (empty).

### 2. Restore the NAS data (rclone) — runs ON `atlas`; decoupled; hours–days
The `vault:` remote (`rclone.conf`) is written to `atlas` by the role in step 1, and the
target `/WD4TB/shared/…` is `atlas`'s local pool — so run rclone **on the node** (trigger it
from here over SSH; there is no point downloading to the control machine first).

Run it **detached** (so closing your SSH window doesn't kill it) and watch progress:

```bash
ssh root@192.168.0.2
tmux new -s restore

# 1. Deep Archive first: request retrieval, then wait 12–48 h
rclone backend restore vault:v1/personal/immich   -o priority=Bulk -o lifetime=14
rclone backend restore vault:v1/personal/obsidian -o priority=Bulk -o lifetime=14

# 2. Copy down (decrypts on the fly; `copy` never deletes locally)
rclone copy vault:v1/personal/obsidian /WD4TB/shared/v1/personal/obsidian --progress --stats 30s
rclone copy vault:v1/personal/immich   /WD4TB/shared/v1/personal/immich   --progress --stats 30s

# detach with Ctrl-b then d; close the window freely.
# Reconnect later:  ssh root@192.168.0.2 -t 'tmux attach -t restore'
```

- **Interrupted?** Just re-run the same command — rclone skips files already present.
- **Prefer systemd over tmux** (survives even a node reboot):
  ```bash
  systemd-run --unit=rclone-restore --collect \
    rclone copy vault:v1/personal/obsidian /WD4TB/shared/v1/personal/obsidian --log-file /var/log/rclone/restore.log --stats 30s
  journalctl -u rclone-restore -f      # watch;  systemctl status rclone-restore
  ```
- Verify content against the stored SHA-256 manifest (`vault:manifests/<job>.sha256`) afterwards.

This step is not Ansible — take as long as needed before proceeding.

### 3. GUEST phase — VMs/LXCs + k3s/services/apps (Tofu → Ansible)
```bash
task apply:guest STACK_NAME=proxmox_atlas
```
The combined form of:
- **`tofu:apply:guest`** — full apply; creates the VMs/LXCs now that `WD4TB`/`local-lvm` exist (incl. the 250G/64G hyperion data disks), and re-renders the inventory (unchanged content).
- **`ansible:apply:guest`** — base/hardening/runtimes/k8s/services + NAS client; k3s + ArgoCD come up and the apps' NFS PVCs mount the **already-restored** dirs (the provisioner's `MkdirAll` tolerates the pre-existing `v1/<ns>/<pvc>` dirs).

### 4. App-level restores
- **Immich** — library already restored (step 3); load its **DB** via Immich's own restore, from `/data/backups/`. See [restore-immich](restore-immich.md).
- **Obsidian** — files restored; see [restore-obsidian](restore-obsidian.md).
- **Authentik** — Velero (separate S3 BSL).
- **SSL certs** — cert-manager re-issues automatically; see [restore-ssl-cert](restore-ssl-cert.md).

---

## Why this order
- **The host must come up before guests** → the NODE phase (step 1) runs before any VM exists. The inventory no longer depends on created guests, so it renders standalone.
- **The share must exist before you download into it** → NODE phase (step 1) before the restore (step 2).
- **Guest disks need `WD4TB`** → the GUEST phase (step 3) runs *after* the NODE phase created the pool/datastore.
- The **apps must not start before the data is in place** → restore (step 2) before the GUEST phase (step 3).
- The **restore is decoupled** from Ansible → you can pause at step 2 indefinitely.

---

## Known gaps
- **AWS OpenTofu state is local** (`*.tfstate` gitignored). On a fresh control machine, `tofu apply aws_kyoto` would try to *create* resources that already exist in AWS → fails without an import. Needs a remote backend or an import runbook (tracked in `planning/BACKLOG.md`).
- **The offsite backup must exist** — the first backup must have run before a DR restore is possible.
- **The crypt password must be recoverable** (vault **and** a password manager).
