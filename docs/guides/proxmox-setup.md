# Proxmox VE Setup Guide

This guide covers the host-level Proxmox VE (PVE) setup that `platform-stack` assumes: creating the
OpenTofu API user and token, and adding/declaring host storage disks (ZFS pools and plain data disks).

---

## 1. Prerequisites

You must have:
- An active Proxmox VE (PVE) node or cluster running.
- Access to the Proxmox Web UI with administrative privileges (e.g. logging in as `root@pam`).

---

## 2. API User & Token Creation

To follow best security practices, do not run automation scripts using the root PAM credentials directly. Instead, create a dedicated automation user and API token.

### 2.1. Create a Dedicated User
1. Log in to the Proxmox VE Web UI.
2. Select **Datacenter** from the left-side resource tree.
3. Under the **Permissions** section, click **Users**.
4. Click **Add**.
5. Configure the user details:
   - **User name**: `tofu-prov`
   - **Realm**: Select **pve** (Proxmox VE authentication realm).
   - **Password**: Enter a secure password (used primarily during user setup, though we will authenticate via token).
   - Click **Add**.

### 2.2. Assign Administrative Permissions
The automation user needs rights to create, delete, and configure VMs, storage, and networking on the cluster.
1. Still under **Datacenter**, click **Permissions** (directly under Users).
2. Click **Add** -> **User Permission**.
3. Configure the permission rule:
   - **Path**: Enter `/` (this grants permissions across the entire cluster).
   - **User**: Select `tofu-prov@pve`.
   - **Role**: Select **Administrator** (or a custom role with appropriate VM, storage, and SDN privileges).
   - **Propagate**: Ensure the checkbox is **checked** (so sub-paths like storage and nodes inherit these permissions).
4. Click **Add**.

### 2.3. Generate API Token
1. Under **Datacenter**, click **API Tokens**.
2. Click **Add**.
3. Configure the token settings:
   - **User**: Select `tofu-prov@pve`.
   - **Token ID**: Enter `tofu-token` (or a descriptive label).
   - **Privilege Separation**: **Uncheck** this box. *(If checked, you must assign permissions to the token itself. By unchecking it, the token automatically inherits all the permissions of the `tofu-prov@pve` user).*
4. Click **Add**.
5. **CRITICAL:** Copy the **Token ID** (formatted as `tofu-prov@pve!tofu-token`) and the **Secret** value. *The secret value is shown only once and will be hidden forever once you close the window.*

---

## 3. Required Permissions

OpenTofu coordinates PVE templates, clone procedures, CPU/RAM configuration, disk resizing, and VLAN setups.

> [!WARNING]
> If you choose to enable **Privilege Separation** on the API token, you must explicitly assign permissions directly to the token ID (e.g., `tofu-prov@pve!tofu-token`) under **Datacenter -> Permissions**. The token will need rights like:
> - `VM.Allocate`, `VM.Config.Disk`, `VM.Config.Network`, `VM.Config.HWType`, `VM.Config.Options`, `VM.PowerMgmt`
> - `Datastore.AllocateSpace`, `Datastore.Audit`
> - `SDN.Use` (if using Software Defined Networking VNets)
>
> Using a token with **Privilege Separation disabled** that inherits the **Administrator** role at `/` is the most reliable way to avoid API errors during infrastructure changes. Ensure the token secret is treated as a highly sensitive key.

---

## 4. Secrets Integration

The credentials generated in Step 2 must be written directly into the stack's encrypted secrets variable file:
`tofu/stacks/onprem/proxmox_atlas/schema.secret.tfvars`.

### Configuration Variables
The OpenTofu stack expects the connection endpoint and authentication details in the `proxmox_connection` object:

| Variable Path | Type | Description |
|---|---|---|
| `proxmox_connection.url` | String | The Proxmox API Endpoint URL (e.g., `https://192.168.1.10:8006/api2/json`) |
| `proxmox_connection.insecure_tls` | Boolean | Allow insecure SSL connections (set to `true` if utilizing self-signed certs) |
| `proxmox_connection.auth_method` | String | Authentication method, set to `"token"` |
| `proxmox_connection.token_auth.id` | String | The API Token ID (e.g., `tofu-prov@pve!tofu-token`) |
| `proxmox_connection.token_auth.secret` | String | The API Token Secret key |

### Step-by-Step Secrets Entry
1. Run the following command from the root of the repository to decrypt and edit the secrets file:
   ```bash
   task tofu:secrets:edit STACK_NAME=proxmox_atlas
   ```
2. Insert/update the `proxmox_connection` block:
   ```hcl
   proxmox_connection = {
     url          = "https://192.168.0.10:8006/api2/json" # Replace with your Proxmox node IP
     insecure_tls = true
     auth_method  = "token"
     token_auth = {
       id     = "tofu-prov@pve!tofu-token"
       secret = "your-proxmox-api-token-secret-here"
     }
   }
   ```
3. Save and close the editor. The file will be automatically re-encrypted.

---

## 5. Storage — Adding New Disks

Proxmox does not manage host disks for you. `platform-stack` declares them under
`topology.nodes.<node>.storage` in [`tofu/stacks/onprem/proxmox_atlas/schema.tfvars`](../../tofu/stacks/onprem/proxmox_atlas/schema.tfvars),
and the Ansible `nas_server` role realises them (pool/dataset, format, mount, export). Adding a disk is a
**data change** — no script edits.

There are two kinds of declared disk:

| Kind | Config key | Use for |
|---|---|---|
| **ZFS pool member** | `storage.pools[].disks` | Integrity, checksums, snapshots — the default for NAS data |
| **Plain (non-ZFS) disk** | `storage.data_disks[]` | Simple/fast volumes — an SSD scratch/cache disk, or a second bulk disk like `WD1TB` (formatted `ext4`) |

> [!WARNING]
> Never reference a disk by `sda`/`sdb` — enumeration order changes between boots. Always use
> `/dev/disk/by-id/…`.

### 5.1 Find the disk's stable ID

The `by-id` path is a udev symlink of the form `bus-model_serial`. It is **independent of whatever
filesystem already lives on the disk** — same path for a blank disk, exFAT, NTFS, or an old pool.

```bash
# whole disks only (drop -partN), with where each symlink points
ls -l /dev/disk/by-id/ | grep -v part

# resolve one device if you know its sdX
udevadm info --query=property --name=/dev/sdc | grep -E '^ID_(BUS|MODEL|SERIAL)'

# model + serial table for all disks (no sdX guessing)
lsblk -d -o NAME,MODEL,SERIAL,SIZE,TYPE
```

Copy the full path, e.g. `/dev/disk/by-id/ata-WDC_WD10EZRX-00L4HB0_WD-WCC4J2501696`.
Prefixes: `ata-…` (SATA/SAS), `nvme-…` (NVMe), `wwn-0x…` (also stable), `usb-…` (USB enclosures).

### 5.2 Check what's on it (optional)

The role creates/formats **only when the disk is blank**, unless you set `wipe = true` (§5.5). Inspect
existing signatures without touching them:

```bash
wipefs -n /dev/disk/by-id/ata-…     # dry run: list detectable signatures
lsblk -f /dev/sdX                   # FSTYPE / LABEL / UUID
zdb -l /dev/sdX                     # any ZFS labels?
```

### 5.3 Add it to the config

**A) New ZFS pool (its own vdev)**

```hcl
storage = {
  # …
  pools = [
    {
      name     = "HDD8TB"
      vdev     = "single"                 # or mirror / raidz1 / raidz2 …
      disks    = ["/dev/disk/by-id/ata-WDC_WD80EFAX-68LHPN0_JEKXXXXX"]
      props    = { ashift = 12, compression = "on", recordsize = "1M" }
      datasets = [{ name = "shared", mountpoint = "/HDD8TB/shared" }]
    }
  ]
}
```

**B) Join an existing pool** (mirror/raidz) — append to that pool's list:

```hcl
disks = ["/dev/disk/by-id/ata-existing…", "/dev/disk/by-id/ata-NEW…"]
```

**C) Plain (non-ZFS) data disk** — an SSD for speed, or a second bulk HDD like `WD1TB`:

```hcl
storage = {
  # …
  data_disks = [
    { interface = "sdb", by_id = "/dev/disk/by-id/ata-WDC_WD10EZRX-00L4HB0_WD-WCC4J2501696",
      fstype = "ext4", path = "/mnt/pve/WD1TB" }
  ]
}
```

Optionally expose it to Proxmox as a datastore under `storage.proxmox_storages`.

### 5.4 HDD vs SSD

Same fields; only the ZFS `props` (and intended role) differ:

| | HDD | SSD |
|---|---|---|
| `ashift` | `12` (4K) | `12` (occasionally `13`) |
| `recordsize` | `1M` (bulk) | `16K`–`128K` |
| Typical role | bulk/media pool | VM-disks pool, or a `special`/`cache` vdev |

### 5.5 Clearing a disk you don't need (`wipe`)

If the disk arrived pre-formatted (exFAT/NTFS) or holds an old pool and **you don't need its contents**,
set `wipe = true` on that pool/disk:

```hcl
pools      = [{ name = "HDD8TB", vdev = "single", disks = ["/dev/disk/by-id/…"], wipe = true, props = { … } }]
data_disks = [{ by_id = "/dev/disk/by-id/…", fstype = "ext4", path = "/mnt/pve/NEW", wipe = true }]
```

The role then runs `wipefs -a` (plus `zpool labelclear -f` if a ZFS label is found) on **only that
by-id**, before creating/formatting. `wipe = false`/absent keeps the safe default: blank-only, never
destructive. The OS/boot/LVM device is never in the declared list and is never touched.

### 5.6 Verify

```bash
zpool status                 # pools + vdevs (shows the by-id form in use)
zfs list                     # datasets + mountpoints
lsblk -f                     # non-ZFS disks: FSTYPE + mountpoint
findmnt /mnt/pve/WD1TB       # confirm a data disk mounted
```
