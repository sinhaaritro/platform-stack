# Authoritative Kubernetes Architecture Guide for AI Agent
**Version:** 5.1 (Restored & Refined)

**Author:** Aritro Sinha

**Scope:** Architecture, Coding Standards, Directory Structure, Operational Protocols.

---

## 1. Architectural Philosophy: "The Lego Model"

We utilize a flexible **Composition Pattern** (Base + Patches + Overlays). Instead of deep linear inheritance, we prefer composing functionality from atomic pieces.

### The 4 Structural Components

1.  **Base (The Foundation)**
    *   **Location:** `apps/[category]/[app]/base/`
    *   **Role:** The raw Helm Chart + Default `values.yaml`.
    *   **Constraint:** Pure installation. No environment specifics.

2.  **Patches (The Features)**
    *   **Location:** `apps/[category]/[app]/patches/`
    *   **Role:** Atomic, reusable units of change.
    *   **Examples:** `scale-to-zero.yaml` (Maintenance), `high-availability.yaml` (3 replicas), `ingress-internal.yaml`.
    *   **Constraint:** Must be self-contained Kustomize patches.

3.  **Overlays (The Profiles)**
    *   **Location:** `apps/[category]/[app]/overlays/`
    *   **Role:** Pre-packaged compositions for standard scenarios.
    *   **Logic:** `Base` + `Select Patches`.
    *   **Examples:** `dev` (Base), `prod` (Base + HA), `maintenance` (Base + Zero Replicas).

4.  **Cluster Implementation (The Deployment)**
    *   **Location:** `clusters/[cluster]/[app]/`
    *   **Role:** The final binding to a specific cluster.
    *   **Logic:** Can consume **Process A** (Direct Base) or **Process B** (Overlay).
    *   **Flexibility:** Can apply *additional* cluster-specific patches on top.

---

## 2. Directory Structure Standards

The AI must strictly adhere to this folder hierarchy.

There is a deliberate structural difference between the **Apps Catalog** (`kubernetes/apps`) and the **Cluster Inventory** (`kubernetes/clusters`).

### 1. The Apps Catalog (`kubernetes/apps/`)
This is organized by **Category**. It contains the reusable definitions.
*   `infrastructure/` (System level: cert-manager, ingress, monitoring, etc.)
*   `services/` (User level: immich, plex, etc.)

### 2. The Cluster Inventory (`kubernetes/clusters/`)
This is organized by **Target**. It contains the specific implementations.
*   **Flat Structure:** Inside a cluster folder (e.g., `CLS1`), we do **not** mirror the `infrastructure/` or `services/` folders.
*   **Single Tenant Model:** Currently, we assume **1 Tenant = 1 Cluster**. All apps for that tenant sit directly under the cluster folder or within the `tenants/` folder if separation is needed in the future.

```text
root/
├── ansible/                                 # REMOTE EXECUTION CONTEXT
│   ├── inventory.yml                        # Host list
│   ├── Taskfile.yml                         # Remote execution wrappers
│   └── ansible.cfg
├── kubernetes/
│   ├── apps/                                # REUSABLE DEFINITIONS
│   │   ├── infrastructure/
│   │   │   └── [APP_NAME]/
│   │   │       ├── base/                    # 1. BASE
│   │   │       │   ├── kustomization.yaml   # HelmRelease / Core Resources
│   │   │       │   └── values.yaml
│   │   │       ├── patches/                 # 2. PATCHES (Atomic Features)
│   │   │       │   ├── scale-to-zero.yaml
│   │   │       │   ├── high-availability.yaml
│   │   │       │   └── ingress-traefik.yaml
│   │   │       └── overlays/                # 3. OVERLAYS (Profiles)
│   │   │           ├── dev/                 # (Base + Simple)
│   │   │           ├── prod/                # (Base + HA Patch)
│   │   │           └── maintenance/         # (Base + Zero Replicas)
│   │   ├── services/
│   │   │   └── [APP_NAME]/
│   │   │       ├── base/                    # 1. BASE
│   │   │       │   ├── kustomization.yaml   # HelmRelease / Core Resources
│   │   │       │   └── values.yaml
│   │   │       ├── patches/                 # 2. PATCHES (Atomic Features)
│   │   │       │   ├── scale-to-zero.yaml
│   │   │       │   ├── high-availability.yaml
│   │   │       │   └── ingress-traefik.yaml
│   │   │       └── overlays/                # 3. OVERLAYS (Profiles)
│   │   │           ├── dev/                 # (Base + Simple)
│   │   │           ├── prod/                # (Base + HA Patch)
│   │   │           └── maintenance/         # (Base + Scale-Zero Patch)
│   │                       
│   ├── clusters/                            # 4. CLUSTER IMPLEMENTATIONS
│   │   └── [CLUSTER_NAME]/
│   │       └── [APP_NAME]/
│   │           ├── kustomization.yaml
│   │           └── patch-[local].yaml       # Cluster-specific overrides
│   │
│   └── bootstrap/                           # MANAGEMENT LAYER (ArgoCD)
│       └── [MGMT_CLUSTER]/                  # e.g., CLS1 (The Hub)
│           ├── appset-core.yaml             # Apps installed everywhere
│           ├── appset-apps-CLS1.yaml        # Apps specific to CLS1 (Hub)
│           ├── appset-apps-CLS2.yaml        # Apps specific to CLS2 (Spoke)
│           └── appset-apps-CLS3.yaml        # Apps specific to CLS3 (Spoke)
```

Future when we will multiple tenants in 1 cluster
```text
│
└── clusters/ruth/              # [THE INVENTORY]
    └── tenants/person-a/immich/
        ├── kustomization.yaml  # Level 3: The Implementation
        └── ingress.yaml        # (Resource Addition #3 + Custom URL)
```

---

## 3. Operational Protocols: Bootstrapping & Cluster Management

### A. The "Hub-and-Spoke" Topology
*   **Hub (Management Cluster):** The cluster running ArgoCD (e.g., `CLS1`). It manages itself and other clusters.
*   **Spoke (Target Cluster):** A cluster registered to the Hub. It does not run its own ArgoCD control plane.
*   **Bootstrapping:** All ApplicationSets live in `kubernetes/bootstrap/[HUB]/`. Target clusters do *not* have their own bootstrap folder.

### B. The Matrix Generator Pattern (Core Apps)
To manage core infrastructure (like `cert-manager`, `monitoring`) across **ALL** clusters efficiently, we use the **Matrix Generator**.

1.  **Generator 1 (Clusters):** Automatically discovers all clusters registered in ArgoCD.
2.  **Generator 2 (List):** Defines the list of core applications to deploy.

**Rule:** If adding an app to *all* clusters, add it to `appset-core.yaml`. Explicitly exclude it from individual cluster ApplicationSets if needed.

### C. Tenant Apps (Cluster Specific)
Tenant-specific apps are managed by a **Git Generator** in `appset-apps-[CLUSTER].yaml`. This generator looks for directories inside `kubernetes/clusters/[CLUSTER]/*`.

**To Add a New App to CLS1:**
1.  Create folder `kubernetes/clusters/CLS1/my-new-app`.
2.  Add `kustomization.yaml` (consuming Base or Overlay).
3.  ArgoCD automatically detects and deploys it.

---

## 4. Operational Protocols: Execution & Debugging

**Rule:** Never assume `kubectl` works locally against the target cluster. Use Ansible tunneling.

### Debugging Workflow
**Scenario:** "Investigate why Podinfo is failing on CLS1"

1.  **Locate Host:** Check `ansible/inventory.yml` to find the control plane IP for `CLS1`.
2.  **Check Status:**
    *   `task -d ansible k8s:cmd HOST=cls1-cp CMD="kubectl get pods -n podinfo"`
3.  **Deep Dive:**
    *   `task -d ansible k8s:cmd HOST=cls1-cp CMD="kubectl logs -l app=podinfo -n podinfo"`
4.  **Decide Fix Scope (Critical Step):**
    *   **Is this a Global Issue?** (e.g., Wrong Docker image tag, buggy config).
        *   -> Fix in `apps/services/podinfo/base` or `patches`.
    *   **Is this a Local Issue?** (e.g., Ingress host mismatch, specialized resource limit).
        *   -> Fix in `clusters/CLS1/podinfo/kustomization.yaml` or `patch-local.yaml`.
5.  **Apply Fix (Local or Global):**
    *   Update the specific file determined in Step 4.
6.  **Deploy:** Commit & Push. ArgoCD handles the sync.

### Local Debugging: Chart Inflation (The "X-Ray")
To determine *exactly* what path to patch, you can inflate the Helm chart locally.

1.  **Command:** `kustomize build --enable-helm . > debug_full.yaml`
    *   Run this inside `base/` or `overlays/dev/`.
2.  **Inspect:** Open `debug_full.yaml`. Find the resource (e.g., `Deployment`) and copy the exact path structure.
3.  **Cleanup (CRITICAL):**
    *   **NEVER** commit `debug_full.yaml`.
    *   **NEVER** commit the `charts/` directory (created by Kustomize).
    *   (Tip: Add headers to `.gitignore` to prevent accidents).

---

## 5. Configuration Guidelines

### A. The Base
**File:** `apps/services/[app]/base/kustomization.yaml`
*   Use `helmCharts` with `valuesFile`.
*   Enable Ingress/Resources with dummy values so objects are generated for later patching.

### B. The Patches (Atomic Units)
**File:** `apps/services/[app]/patches/[feature].yaml`
*   **Functional:** Changes *one* aspect (e.g., `replicas: 0`, `resources: limits`).
*   **Self-Contained:** Must be a valid Kustomize patch.

### C. The Overlays (Profiles)
**File:** `apps/services/[app]/overlays/[profile]/kustomization.yaml`
*   **Composition:** `resources: [ ../../base ]` + `patches: [ ../../patches/feature.yaml ]`.
*   **Rule:** Do *not* redefine Helm charts here. Only patch.

### D. The Cluster Implementation
**File:** `clusters/[cluster]/[app]/kustomization.yaml`
*   **Consumption:** `resources: [ ../../../apps/services/[app]/overlays/prod ]` (or `base`).
*   **Local Patching:** Add `patches: [ patch-local-ingress.yaml ]` for specific overrides like domains or secrets.
*   **Shared Patching:** Can also pull in shared patches manually: `patches: [ ../../../apps/services/[app]/patches/extra-feature.yaml ]`.

---

## 6. Naming Conventions

*   **Patches Folder:** `/patches/` (Plural).
*   **Patch Files (Shared):** Descriptive names (e.g., `scale-to-zero.yaml`, `high-availability.yaml`).
*   **Patch Files (Local):** `patch-[logic].yaml` (e.g., `patch-ingress.yaml`).
*   **Resources:** `resource-[kind]-[name].yaml` (e.g., `resource-cm-dashboard.yaml`).
*   **SecretGenerators:** Suffix with purpose (e.g., `podinfo-auth`).

---

## 7. Patching Strategy & Decision Tree

**INPUT:** Modify property `X` on resource `Y`.

1.  **Is it a shared feature?** (e.g., "HA Mode", "Maintenance Mode")
    *   **Action:** Create a shared patch in `apps/.../patches/`.
    *   **Usage:** Reference it in `overlays/`.

2.  **Is it cluster-specific?** (e.g., "Ingress Host", "DB Password")
    *   **Action:** Create a local patch `patch-ingress.yaml` in `clusters/.../`.

3.  **Is `X` a Standard Field?** (Replicas, Image)
    *   **Action:** Use **Strategic Merge Patch**.

4.  **Is `X` an Ordered List?** (Command, Args)
    *   **Action:** Use **JSON Patch 6902**.
    *   (Merge patches append to lists, often breaking commands).

5.  **Is `X` a Key-Value Map?** (Env, Labels)
    *   **Action:** Use **Strategic Merge Patch**.

---

## 8. Common Pitfalls & Anti-Patterns

1.  **The "Values in Overlay" Fallacy:**
    *   *Bad:* Defining `helmCharts` again in Overlay to pass different values.
    *   *Correct:* Inflate Helm in Base to default YAML. Patch the YAML in Overlay/Cluster.

2.  **The "Path Blindness":**
    *   *Bad:* `resources: [ ../base ]` (Relative paths are tricky).
    *   *Correct:* Calculate depth. Cluster -> Overlay = `../../../`.

3.  **Imperative Secret Injection:**
    *   *Bad:* Hardcoding `value: password`.
    *   *Correct:* Use `secretGenerator` + `valueFrom`.

---

## 9. AI Agent Verification Checklist

1.  [ ] **Context:** Am I editing *Shared* (`apps/`) or *Specific* (`clusters/`) logic?
2.  [ ] **Composition:** Did I use the `patches/` folder for reusable logic?
3.  [ ] **Pathing:** Are relative paths correct? (`../../../`)
4.  [ ] **Secrets:** Used `secretGenerator`?
5.  [ ] **Maintenance:** If deleting, check if PVCs are at risk. Use `patches/scale-to-zero.yaml` instead?
