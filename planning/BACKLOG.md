# Project Backlog & Inbox

> **Purpose:** Catch-all for ideas, bugs, technical debt, and "nice-to-haves" discovered during other tasks.
> **AI Instruction:** If you find a bug or think of an improvement while working on a different task, ADD IT HERE. Do not get distracted.

## Feature Ideas
*   [ ] **Authentik SSO for Obsidian Web** — Add forward auth proxy via Authentik since linuxserver/obsidian has no OAuth. Required before exposing via Cloudflare Tunnel. Implement using Authentik blueprints-as-code.
*   [ ] **Immich postgress starts before postgress is ready** — Breaks the app, delete after postgress is ready fixes it.
*   [ ] **Split Package list of VM and LXC based on Host type in Ansible** — Right now ansible, install all packages, we dont want that
*   [ ] **Remove the extra line from the appset** - Kubernetes, in the appset ignore line, try to see if we can remove them
*   [ ] **Proper Backup schedule for all** — Get prod backup schedules for all things.
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
*   [ ] ...
