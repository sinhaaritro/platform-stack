# Homelab GitOps Repository

This repository contains the **complete**, **end-to-end infrastructure**, **configuration**, and **application code** for a multi-site homelab. The entire platform is managed using **GitOps principles**, where this repository serves as the **single source of truth** for the desired state of all environments, from bare-metal Proxmox nodes to cloud resources and Kubernetes applications.

## Documentation

All project documentation is centralized in the [`/docs`](./docs/README.md) directory. Start here:

*   **[Documentation Hub](./docs/README.md)** — Master table of contents for all docs.
*   **[Architecture](./docs/ARCHITECTURE.md)** — High-level design, system overview diagram.
*   **[Getting Started](./docs/GETTING_STARTED.md)** — Complete developer setup guide.
*   **[Naming Convention](./docs/NAMING_CONVENTION.md)** — The single source of truth for naming all resources.
*   **[Secrets Policy](./docs/secrets/01-secrets-management-policy.md)** — Managing secrets with Ansible Vault.

For a detailed map of the repository structure, see **[CODEBASE.md](./CODEBASE.md)**.

---

## Directory Structure

```
platform-stack/
├── Makefile           # Automates common project setup and operational tasks.
├── docs/              # All project documentation (Starlight-ready).
│   ├── guides/        # How-to guides and setup procedures.
│   ├── layers/        # Per-layer tool docs (tofu, ansible, kubernetes).
│   ├── runbooks/      # Disaster recovery and restore procedures.
│   ├── reference/     # Technical specs, analysis, discussions.
│   ├── app_pattern/   # K8s app patterns (structure, overlays, lifecycle).
│   ├── secrets/       # Secrets management docs.
│   ├── storage/       # Storage architecture docs.
│   ├── networking/    # Network topology docs.
│   ├── backup/        # Backup strategy docs.
│   └── monitoring/    # Monitoring & observability docs.
├── planning/          # Layer 0: Roadmap and backlog.
├── scripts/           # Helper scripts for safety, automation, and CI/CD.
├── lxc-configs/       # Application-specific configs for standalone LXC containers.
├── tofu/              # Layer 1: Provisions core infrastructure (VMs, networks, LXCs).
├── ansible/           # Layer 2: Configures provisioned resources.
├── kubernetes/        # Layer 3: Production Kubernetes cluster (Kustomize).
└── compose/           # Layer 4: Local development services.
```

---

## Quick Start

**Stack:** `OpenTofu` → `Ansible` → `Kubernetes` (Traefik, Authentik, Prometheus/Grafana) → Podman Compose (local). Managed via `GitOps` with `Cloudflare Tunnels` and `Netbird` for external access.

### What to Edit

| Want to... | Edit this directory |
|---|---|
| Provision a new VM or change resources | `tofu/` |
| Install software or configure a server | `ansible/` |
| Deploy or update a Kubernetes app | `kubernetes/` (GitOps) or `k8s/` (legacy Kustomize) |
| Run services locally for development | `compose/` |

### Common Commands

This project uses **[Task](https://taskfile.dev)** as a command runner. See all available tasks with:

```sh
task --list
```

Frequently used examples:

```sh
task tofu:fmt        # Validate and format OpenTofu code
task tofu:plan       # Preview infrastructure changes
task ansible:playbook -- playbooks/configure-k8s-nodes.yml  # Run an Ansible playbook
```

For the complete setup (clone, Git hooks, vault password, tool installation), follow the **[Getting Started](./docs/GETTING_STARTED.md)** guide.
