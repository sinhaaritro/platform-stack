# Project Backlog & Inbox

> **Purpose:** Catch-all for ideas, bugs, technical debt, and "nice-to-haves" discovered during other tasks.
> **AI Instruction:** If you find a bug or think of an improvement while working on a different task, ADD IT HERE. Do not get distracted.

## Feature Ideas
*   [ ] **Authentik SSO for Obsidian Web** — Add forward auth proxy via Authentik since linuxserver/obsidian has no OAuth. Required before exposing via Cloudflare Tunnel. Implement using Authentik blueprints-as-code.
*   [ ] **Add a TTL or Kyverno cleanup policy for Completed/Failed pods** — So completed ghost pods will be cleaded up. Also we will need to log this, so that alert manager and grfana can use this to show and alert me.
*   [ ] **Velero put up the certs, then certmanager comes in** — Try kubectl wait inside presync hook. Ensure argo cds resource tracking is configured so parents application considers child application healthy only whne thier child resources are healthy
*   [ ] **Immich postgress starts before postgress is ready** — Breaks the app, delete after postgress is ready fixes it. It is still not working properly, look in syncwav. Also postgress readyness probe. next sync starts as soon as the previous waves is healthy. So control the pg health state. Strict waves + strict readinessProbe
    *   **Solution:** Added ArgoCD hook annotations to `immich-init-db` job: `hook: PreSync` + `hook-delete-policy: HookSucceeded` (kubernetes/apps/services/immich/components/init-db/init-db-job.yaml).
    *   **Why needed:** Without hook, ArgoCD creates the job but doesn't wait for it to complete before syncing Immich deployment. Immich-server starts immediately and fails to connect to PostgreSQL if it's still initializing.
    *   **How it works:** Job runs in sync-wave -1 as PreSync hook → ArgoCD waits for completion → then syncs Immich deployment (wave 0) → job deleted after success (HookSucceeded).
    *   **Trial & error history:** Multiple attempts to fix race condition between init-db job and Immich deployment. User confirmed fresh install approach works, memory limit increased to 2Gi to prevent OOMKilled (Exit Code 137).
*   [ ] **Split Package list of VM and LXC based on Host type in Ansible** — Right now ansible, install all packages, we dont want that
*   [ ] **Remove the extra line from the appset** - Kubernetes, in the appset ignore line, try to see if we can remove them
*   [ ] **Proper Backup schedule for all** — Get prod backup schedules for all things.
*   [x] **De-Velero Immich** *(docs reconciled — `docs/backup/*` and `restore-immich.md` are consistent: no Immich Velero schedule / `pg_dump` hook / Longhorn fs-backup)* — Immich is no longer backed up by Velero. Its data lives on the NAS (`immich` PVC, NFS, mounted at `/data`) and is covered by the NAS backup plan (local ZFS snapshots + offsite rclone). The DB is not on the NAS (PostgreSQL on Longhorn); the bridge is Immich's own in-app DB dump (Immich v3) written to `/data/backups/`. Reconcile `docs/backup/*` with `docs/runbooks/restore-immich.md` so no doc claims a `daily-immich` Velero schedule, a `pg_dump` pre-backup hook, or a Longhorn PVC fs-backup for Immich. Velero remains in use for Authentik, Obsidian, and SSL certs.
*   [ ] **Remove Certamangers need 2nd api token** — Maybe we can remove the 2nd api token. and use tofu to create a token, then give it access
*   [ ] **Ansible role for dev vms** — Get new roles, for working vm like flutter, react
*   [ ] **Ansible Visualization** — Get the new ansible role visualization
*   [ ] **Opentofu Visualization** — Get the new opentofu infra visualization.
*   [ ] **Kubernets Visualization** — Get the new kubernetes cluster visualization.
*   [ ] **Doc cleaning** — make doc naming generic. no specific vm, lxc, etc names.
*   [ ] **Create checker for ansible to stop reapplying** - If kubernets of service is already running, then try to skip ahead with checks to know if something is missing or if we need to update. else don't apply
*   [ ] **Let us view the grafana website from anywhere in the world**
*   [ ] **All 4 zones**
*   [ ] **Let us view the proxmox website from anywhere in the world**
*   [ ] **Firewall**
*   [ ] **Internal VNets**
*   [ ] **Skip `image_builder` when there are no VM/LXC changes** — `proxmox_atlas` rebuilds/re-uploads OS images (`image_builder` → `image_upload`) whenever the upstream cloud-image checksum changes, even when no VM or LXC is being created/changed. A pure inventory/config change then drags a ~1 GB image rebuild into the plan. Investigate gating the build so it only runs when an image is actually missing (or when a VM/LXC is added/changed), instead of on every checksum drift. Feasibility TBD.
*   [ ] **NAS backup observability via the K8s stack (not healthchecks.io)** — the offsite rclone jobs (`nas_server`) have an optional `healthchecks_url` (healthchecks.io ping). We already run a full in-cluster observability stack (Prometheus + Alertmanager + Grafana + Loki), so route backup success/failure/staleness there instead: have the wrapper emit a metric (e.g. node-exporter textfile `nas_backup_last_success_timestamp` / `nas_backup_last_status{job=...}`), alert on staleness/failure in Alertmanager, display in Grafana. Then drop healthchecks.io entirely.
*   [ ] **Tofu state is local — decide where to store it (DR blocker)** — every stack (`proxmox_atlas`, `aws_kyoto`, `cloudflare_alexandria`, `netbird_samarkand`) uses a **local** `terraform.tfstate` (gitignored). On a fresh control machine, `tofu apply aws_kyoto` would try to *create* the bucket/user/policy/access-key that already exist in AWS → fails without an import. `proxmox_atlas` on a genuinely fresh host is fine (fresh state creates everything), but any stack managing pre-existing cloud resources needs the state. Decide: a **remote backend** (S3 + DynamoDB lock) per stack, or a documented `tofu import` runbook. Note: generated secrets (e.g. `aws_iam_access_key`) live only in state — losing it rotates keys.
*   [ ] ...

## Bugs

*   [ ] **`apply:node` / `apply:guest` are Proxmox-only; the Ansible half ignores `STACK_NAME`** — need to understand + decide behavior on non-Proxmox stacks. Three related problems:
    *   **Ansible runs on the whole inventory, not the named stack.** `ansible:apply:node` (`ansible-playbook -i inventory.d playbooks/10-node.yml`) and `ansible:apply:guest` (`... site.yml --skip-tags nas_server`) iterate the whole merged `inventory.d` directory with no `--limit` and no `-i inventory.d/<stack>.yml`. So `task apply:node STACK_NAME=aws_kyoto` still runs the NAS node layer against atlas (the `proxmox_node` group), and `apply:guest` runs `site.yml` on *every* host in the directory. `STACK_NAME` only affects the Tofu half. (`vm:build` already shows the fix — it passes `INVENTORY_FILE: inventory.d/{{.STACK_NAME}}.yml`.)
    *   **`tofu:apply:node` (`-target=module.inventory`) only works for `proxmox_atlas`.** It is the only stack that emits its inventory via the shared `ansible_inventory` module named `inventory`; the cloud stacks write theirs via `local_file`/`local_sensitive_file` (`aws_secrets`, `ansible_inventory`). A non-matching `-target` does **not** error — OpenTofu prints the "Resource targeting is in effect" warning and plans nothing (**exit 0**), so on a non-Proxmox stack `tofu:apply:node` is a silent no-op (it won't even refresh that stack's inventory fragment).
    *   **Group names are Proxmox-specific.** `tofu/modules/topology` hardcodes `type = "proxmox_node"` for every physical node, and the cluster layer targets `proxmox_primary`. A future TrueNAS node (`zunesha`) would land in the `proxmox_node` group; the `nas_server` role itself is already backend-aware (`storage.backend` → `proxmox.yml`/`truenas.yml`), so only the group naming/targeting needs generalizing.
    *   **Candidate fixes:** (A) neutral `nas_node` (backend-derived) group for physical nodes; (B) route every stack's inventory through the shared `ansible_inventory` module named `inventory` (or a stack-agnostic marker) so `-target=module.inventory` is uniform; (C) scope the Ansible half to `inventory.d/<STACK_NAME>.yml`. Decide how `apply:node`/`apply:guest` should behave on cloud stacks vs the on-prem Proxmox stack.

