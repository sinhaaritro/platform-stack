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
*   [ ] **De-Velero Immich** — Immich is no longer backed up by Velero. Its data lives on the NAS (`immich` PVC, NFS, mounted at `/data`) and is covered by the NAS backup plan (local ZFS snapshots + offsite rclone). The DB is not on the NAS (PostgreSQL on Longhorn); the bridge is Immich's own in-app DB dump (Immich v3) written to `/data/backups/`. Reconcile `docs/backup/*` with `docs/runbooks/restore-immich.md` so no doc claims a `daily-immich` Velero schedule, a `pg_dump` pre-backup hook, or a Longhorn PVC fs-backup for Immich. Velero remains in use for Authentik, Obsidian, and SSL certs.
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
*   [ ] ...

## Bugs
