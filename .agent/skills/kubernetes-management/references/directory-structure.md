# Directory Structure Standards

> **Source of Truth:** Defines the mandatory folder hierarchy for the Kubernetes platform.

## 1. The Core Hierarchy

The AI must strictly adhere to this folder hierarchy.

```text
root/
├── ansible/                                 # REMOTE EXECUTION CONTEXT
│   ├── inventory.yml                        # Host list
│   ├── Taskfile.yml                         # Remote execution wrappers
│   └── ansible.cfg
├── kubernetes/
│   ├── apps/                                # REUSABLE DEFINITIONS
│   │   ├── infrastructure/                  # (System: cert-manager, ingress)
│   │   │   └── [APP_NAME]/
│   │   │       ├── base/                    # 1. BASE (Helm + Values)
│   │   │       ├── patches/                 # 2. PATCHES (Atomic Features)
│   │   │       └── overlays/                # 3. OVERLAYS (Profiles: dev, prod)
│   │   ├── services/                        # (User: immich, plex)
│   │   │   └── [APP_NAME]/
│   │   │       ├── base/
│   │   │       ├── patches/
│   │   │       └── overlays/
│   │                       
│   ├── clusters/                            # 4. CLUSTER IMPLEMENTATIONS
│   │   └── [CLUSTER_NAME]/
│   │       └── [APP_NAME]/
│   │           ├── kustomization.yaml       # Consumes Overlay/Base
│   │           └── patch-[local].yaml       # Cluster-specific overrides
│   │
│   └── bootstrap/                           # MANAGEMENT LAYER (ArgoCD)
│       └── [MGMT_CLUSTER]/                  # e.g., CLS1 (The Hub)
│           ├── appset-core.yaml             # Apps installed everywhere
│           └── appset-apps-[CLUSTER].yaml   # Apps specific to a cluster
```

## 2. Structural Logic

There is a deliberate structural difference between the **Apps Catalog** (`kubernetes/apps`) and the **Cluster Inventory** (`kubernetes/clusters`).

### A. The Apps Catalog (`kubernetes/apps/`)
This is organized by **Category**. It contains the reusable definitions.
*   `infrastructure/` (System level: cert-manager, ingress, monitoring, etc.)
*   `services/` (User level: immich, plex, etc.)

### B. The Cluster Inventory (`kubernetes/clusters/`)
This is organized by **Target**. It contains the specific implementations.
*   **Flat Structure:** Inside a cluster folder (e.g., `CLS1`), we do **not** mirror the `infrastructure/` or `services/` folders.
*   **Single Tenant Model:** Currently, we assume **1 Tenant = 1 Cluster**. All apps for that tenant sit directly under the cluster folder.
*   **Future Multi-Tenant:** If needed, we will use `clusters/[CLUSTER]/tenants/[TENANT]/[APP]`.

## 3. File Naming Conventions

*   **Patches Folder:** `/patches/` (Plural).
*   **Patch Files:**
    *   *Shared:* Descriptive names (e.g., `scale-to-zero.yaml`, `high-availability.yaml`).
    *   *Local:* `patch-[logic].yaml` (e.g., `patch-ingress.yaml`).
*   **Resources:** `resource-[kind]-[name].yaml` (e.g., `resource-cm-dashboard.yaml`).
*   **SecretGenerators:** Suffix with purpose (e.g., `podinfo-auth`).
