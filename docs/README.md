# Documentation Hub

Welcome to the **platform-stack** documentation. This is the single entry point for understanding, operating, and contributing to the homelab infrastructure.

---

## Getting Started

| Document | Description |
|---|---|
| [Getting Started](./GETTING_STARTED.md) | Developer onboarding — clone, install, configure, contribute |
| [Architecture](./ARCHITECTURE.md) | System overview, guiding principles, and navigation hub |
| [Naming Convention](./NAMING_CONVENTION.md) | Standards for naming all resources across the platform |

---

## Infrastructure Layers

Each layer of the stack has dedicated documentation covering its tools, workflows, and operational procedures.

| Layer | Document | Description |
|---|---|---|
| **Layer 1 — IaC** | [OpenTofu](./layers/tofu.md) | Proxmox VM/LXC provisioning, state management, CI/CD workflow |
| **Layer 2 — Config** | [Ansible](./layers/ansible.md) | Server configuration, K8s cluster setup roles |
| **Layer 3 — Orchestration** | [Kubernetes](./layers/kubernetes.md) | Application deployment, Kustomize operations guide |

---

## Kubernetes Applications

Per-app documentation for services running on the cluster.

| App | Document | Description |
|---|---|---|
| External DNS | [external-dns.md](./layers/kubernetes/external-dns.md) | DNS record automation for Kubernetes |
| Longhorn | [longhorn.md](./layers/kubernetes/longhorn.md) | Distributed block storage for K8s |
| SeaweedFS | [seaweedfs.md](./layers/kubernetes/seaweedfs.md) | Distributed storage system (S3 + filesystem) |
| Podinfo | [podinfo.md](./layers/kubernetes/podinfo.md) | Test/demo application guide |

---

## Application Patterns

How to write, structure, debug, and validate Kubernetes applications in this repo.

| Document | Description |
|---|---|
| [01 — Directory Structure](./app_pattern/01-directory-structure.md) | K8s manifest folder hierarchy |
| [02 — Base, Patches & Overlays](./app_pattern/02-base-patches-overlays.md) | Kustomize layering strategy |
| [03 — Application Lifecycle](./app_pattern/03-application-lifecycle.md) | Deploy, update, rollback workflows |
| [04 — Debugging Guide](./app_pattern/04-debugging-guide.md) | Troubleshooting K8s apps |
| [05 — Validation & Tooling](./app_pattern/05-validation-and-tooling.md) | Linting, testing, CI checks |
| [06 — Kubernetes Architecture](./app_pattern/06-kubernetes-architecture.md) | Cluster design, GitOps workflow |
| [App Dependencies](./app_pattern/app-dependency.md) | Dependency graph between apps |

---

## Domain-Specific Documentation

### Secrets Management

| Document | Description |
|---|---|
| [01 — Policy](./secrets/01-secrets-management-policy.md) | Cardinal rule, Ansible Vault, Sealed Secrets |
| [02 — Sealed Secrets Architecture](./secrets/02-sealed-secrets-architecture.md) | Master key lifecycle for ephemeral clusters |
| [03 — Creating Secrets](./secrets/03-creating-kubernetes-secrets.md) | Developer instructions |
| [04 — Advanced Patterns](./secrets/04-advanced-secrets-pattern.md) | Advanced secret patterns |
| [05 — Key Rotation](./secrets/05-dynamic-key-rotation.md) | Rotation procedures |

### Storage

| Document | Description |
|---|---|
| [Overview](./storage/README.md) | 4-tier storage model |
| [Architecture](./storage/ARCHITECTURE.md) | Detailed storage architecture |
| [Longhorn](./storage/LONGHORN.md) | Longhorn-specific docs |
| [NFS](./storage/NFS.md) | NFS configuration |
| [SeaweedFS](./storage/SEAWEEDFS.md) | SeaweedFS configuration |
| [Capacity Planning](./storage/CAPACITY_PLANNING.md) | Storage capacity planning |

### Networking

| Document | Description |
|---|---|
| [Overview](./networking/README.md) | Topology, subnets, ingress flow |
| [Proxmox Subnets & VNet](./networking/proxmox-subnets-vnet.md) | Detailed subnet/VNet config |
| [Remote Access](./networking/remote-access-architecture.md) | Remote access architecture |

### Backup & Disaster Recovery

| Document | Description |
|---|---|
| [Overview](./backup/README.md) | Backup strategy overview |
| [Architecture](./backup/ARCHITECTURE.md) | Velero, rclone, recovery details |
| [Monitoring](./backup/MONITORING.md) | Backup monitoring |
| [Capacity Planning](./backup/CAPACITY_PLANNING.md) | Backup capacity planning |
| [Runbooks](./backup/RUNBOOKS.md) | Backup operational runbooks |

### Monitoring & Observability

| Document | Description |
|---|---|
| [Overview](./monitoring/README.md) | Monitoring hub — dashboards, tools |
| [Grafana Implementation](./monitoring/GRAFANA_IMPLEMENTATION.md) | Grafana setup details |
| **Developer** | [App Health](./monitoring/developer/D1-application-health.md) · [Log Explorer](./monitoring/developer/D2-log-explorer.md) · [Security & Auth](./monitoring/developer/D3-security-auth.md) |
| **Executive** | [Platform Overview](./monitoring/executive/E1-platform-overview.md) · [Capacity & Trends](./monitoring/executive/E2-capacity-and-trends.md) |
| **Portal** | [Public](./monitoring/portal/P1-home-public.md) · [Trusted](./monitoring/portal/P2-home-trusted.md) · [Admin](./monitoring/portal/P3-home-admin.md) |
| **DBA** | [PostgreSQL](./monitoring/dba/B1-postgresql.md) · [Cache & Doc Stores](./monitoring/dba/B2-cache-and-document-stores.md) |
| **SRE** | [Backup & DR](./monitoring/sre/S1-backup-and-disaster-recovery.md) · [Cluster Health](./monitoring/sre/S2-cluster-and-node-health.md) · [Networking](./monitoring/sre/S3-networking.md) · [Storage](./monitoring/sre/S4-storage.md) · [Self-Health](./monitoring/sre/S5-monitoring-self-health.md) · [External Infra](./monitoring/sre/S6-external-infrastructure.md) |

---

## Guides

How-to guides for specific tasks and setup procedures.

| Guide | Description |
|---|---|
| [AWS Setup](./guides/aws-setup.md) | AWS account signup, IAM user creation, API access keys, and scoped permissions |
| [Ansible VM Lifecycle](./guides/ansible-vm-lifecycle.md) | The journey of a VM from nothing to cluster integration |
| [Cloudflare Setup](./guides/cloudflare-setup.md) | Cloudflare account, Zero Trust tunnel editing permissions, API tokens |
| [NetBird Setup](./guides/netbird-setup.md) | NetBird PAT token generation and administration role setup |
| [Oracle Setup](./guides/oracle-setup.md) | OCI Free Tier, tenant/user OCID retrieval, PEM API key generation |
| [Proxmox Setup](./guides/proxmox-setup.md) | Proxmox administrative API user, unseparated token creation |
| [qBittorrent Proxy Setup](./guides/qbittorrent-proxy-setup.md) | Proxy configuration for qBittorrent |

---

## Runbooks

Disaster recovery and restore procedures.

| Runbook | Description |
|---|---|
| [Restore Authentik](./runbooks/restore-authentik.md) | Authentik database restore procedure |
| [Restore Immich](./runbooks/restore-immich.md) | Immich hybrid restore (DB + media) |
| [Restore Obsidian](./runbooks/restore-obsidian.md) | Obsidian data restore procedure |
| [Restore SSL Certificates](./runbooks/restore-ssl-cert.md) | SSL/TLS certificate restore procedure |

---

## Reference

Technical analysis, specifications, and architecture discussions.

| Document | Description |
|---|---|
| [Cluster Configuration Analysis](./reference/cluster-configuration-analysis.md) | K8s cluster config analysis |
| [Infrastructure Inventory](./reference/infrastructure-inventory.md) | Hardware and VM inventory |
| [Resource Planning](./reference/resource-planning.md) | Compute and storage resource planning |
| [SSH Agent Forwarding](./reference/ssh-agent-forwarding.md) | SSH agent forwarding chain details |
| [Storage Architecture Discussion](./reference/storage-architecture-discussion.md) | Storage architecture design discussion |
