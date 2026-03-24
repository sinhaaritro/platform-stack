# Directory Structure

This document defines the mandatory folder hierarchy and organizational logic for all Kubernetes applications managed in this repository. It is the single source of truth for where files belong and why.

## Table of Contents

1. [The Core Hierarchy](#1-the-core-hierarchy)
2. [Structural Logic](#2-structural-logic)
3. [Hub-and-Spoke Topology](#3-hub-and-spoke-topology)
4. [File Naming Conventions](#4-file-naming-conventions)

---

## 1. The Core Hierarchy

All Kubernetes manifests live under the `kubernetes/` directory, split into three top-level concerns:

```text
kubernetes/
├── apps/                                 # REUSABLE DEFINITIONS (The Catalog)
│   ├── infrastructure/                   # System-level: cert-manager, ingress, monitoring
│   │   └── [APP_NAME]/
│   │       ├── base/                     # Helm Chart + default values
│           ├── components/               # Reusable modules (secrets, storage, jobs)
│   │       ├── patches/                  # Atomic, reusable feature patches
│   │       └── overlays/                 # Environment profiles (dev, prod, maintenance)
│   └── services/                         # User-level: immich, plex, radarr
│       └── [APP_NAME]/
│           ├── base/
│           ├── components/               # Reusable modules (secrets, storage, jobs)
│           ├── patches/
│           └── overlays/
│
├── clusters/                             # CLUSTER IMPLEMENTATIONS (The Inventory)
│   └── [CLUSTER_NAME]/
│       └── [APP_NAME]/
│           ├── kustomization.yaml        # Consumes an overlay or base
│           └── patch-[local].yaml        # Cluster-specific overrides
│
└── bootstrap/                            # MANAGEMENT LAYER (ArgoCD)
    └── [MGMT_CLUSTER]/                   # e.g., CLS1 (The Hub)
        ├── appset-core.yaml              # Core apps deployed to ALL clusters
        └── appset-apps-[CLUSTER].yaml    # Workload apps for a specific cluster
```

---

## 2. Structural Logic

There is a deliberate structural difference between the **Apps Catalog** and the **Cluster Inventory**.

### A. The Apps Catalog (`kubernetes/apps/`)

Organized by **category**. Contains reusable, environment-agnostic definitions.

| Category | Purpose | Examples |
|---|---|---|
| `infrastructure/` | System-level platform services | cert-manager, ingress-nginx, monitoring |
| `services/` | User-facing application workloads | immich, plex, radarr |

Each app follows the **Base + Patches + Overlays** pattern (see [02-base-patches-overlays.md](./02-base-patches-overlays.md) for details).

### B. The Components Folder (`components/`)

- **Location:** Inside `apps/[category]/[app]/components/`
- **Role:** Reusable modules that encapsulate a feature, configuration, or operational concern.
- **Examples:**
  - `components/secrets` — SealedSecrets + environment variable patches
  - `components/s3-config` — Jobs and scripts for S3 bucket setup
  - `components/replicas-1` — Replica count configuration
  - `components/storage-longhorn` — StorageClass overrides
  - `components/maintenance` — Scale-to-zero configuration
- **Usage:** Imported in overlays or cluster-level `kustomization.yaml` files.

### C. The Cluster Inventory (`kubernetes/clusters/`)

Organized by **target**. Contains cluster-specific implementations.

- **Flat Structure:** Inside a cluster folder (e.g., `CLS1`), we do **not** mirror the `infrastructure/` or `services/` sub-folders. All apps sit directly under the cluster folder.
- **Single Tenant Model:** Currently, we assume **1 Tenant = 1 Cluster**.
- **Future Multi-Tenant:** If needed, the structure will extend to `clusters/[CLUSTER]/tenants/[TENANT]/[APP]`.

---

## 3. Hub-and-Spoke Topology

Our clusters follow a **Hub-and-Spoke** model for GitOps management.

### Roles

| Role | Description |
|---|---|
| **Hub** (Management Cluster) | Runs ArgoCD. Manages itself and all spoke clusters. |
| **Spoke** (Target Cluster) | Registered to the Hub. Does *not* run its own ArgoCD. |

### Bootstrapping

All ApplicationSets live in `kubernetes/bootstrap/[HUB]/`. Spoke clusters do **not** have their own bootstrap folder.

### Core Apps vs. Workload Apps

| Type | ApplicationSet | Scope | Generator |
|---|---|---|---|
| **Core** | `appset-core.yaml` | Deployed to **all** clusters | Matrix Generator (clusters × app list) |
| **Workload** | `appset-apps-[CLUSTER].yaml` | Deployed to **one** cluster | Git Generator (scans `clusters/[CLUSTER]/*`) |

> **The Exclusion Principle:** If promoting an app from a cluster-specific AppSet to the core AppSet, you **must** remove it from the cluster AppSet to avoid duplicate management conflicts.

---

## 4. File Naming Conventions

| Element | Convention | Example |
|---|---|---|
| Patches folder | `/patches/` (plural) | `apps/services/immich/patches/` |
| Shared patch files | Descriptive name | `scale-to-zero.yaml`, `high-availability.yaml` |
| Local patch files | `patch-[logic].yaml` | `patch-ingress.yaml`, `patch-storage.yaml` |
| Extra resources | `resource-[kind]-[name].yaml` | `resource-cm-dashboard.yaml` |
| SecretGenerators | Suffix with purpose | `podinfo-auth` |
