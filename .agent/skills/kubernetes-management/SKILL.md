---
name: kubernetes-management
description: Comprehensive workflow for Kubernetes App Lifecycle Management. Use for creating, updating, deleting (safe shutdown), and debugging applications. Enforces the Base+Patches+Overlays pattern.
allowed-tools: Read, Write, List, Grep, Run
---

# Kubernetes Management Skill

> This skill standardizes how we manage applications in the `platform-stack` repository.

## References
*   [Directory Structure & Naming](references/directory-structure.md)
*   [Patching Strategies & Decision Tree](references/patching-strategies.md)
*   [Operational Protocols](references/operational-protocols.md)

## 1. Creating a New Application

**Goal:** Add a new app (e.g., `radarr`) to the cluster.

### Step 1: Define the Base
1.  Identify the Helm Chart URL and Version.
2.  Create `apps/services/[app]/base/kustomization.yaml`:
    *   Use `helmCharts` block.
    *   Set `releaseName` and `namespace`.
    *   Point to `values.yaml`.
3.  Create `apps/services/[app]/base/values.yaml` (Start minimal).

### Step 2: Components (Reusable Modules)
For complex apps (like SeaweedFS) where features need to be toggled or configured independently of the environment:
1.  **Create:** `apps/services/[app]/components/[name]/kustomization.yaml`.
2.  **Use Case:**
    *   **Features**: `components/s3-config` (Jobs/Scripts).
    *   **Configuration**: `components/replicas-1` (Replica Counts), `components/storage-longhorn` (Storage Classes).
    *   **Maintenance**: `components/maintenance` (Scale to Zero).
3.  **Usage:** Import logically in `clusters/[cluster]/[app]/kustomization.yaml` or `overlays/[env]/kustomization.yaml`.

### Step 3: Create Profiles (Overlays)
1.  Create `apps/services/[app]/overlays/prod/kustomization.yaml`.
    *   `resources: [ ../../base ]`
    *   `resources: [ ../../base ]`
    *   **Compostion:** Use `patches: [ ../../patches/feature.yaml ]`.
    *   *Note:* Unique, non-reusable patches can live in the overlay folder, but prefer shared patches.

### Step 4: Implement in Cluster
1.  Create `clusters/[cluster]/[app]/kustomization.yaml`.
    *   `resources: [ ../../../apps/services/[app]/overlays/prod ]` or `../../../apps/services/[app]/base`
    *   `namespace: [app]`
2.  Add Component Patches (e.g., Ingress Host).
    *   Create `patch-component.yaml`.
    *   Add to `component` list in `kustomization.yaml`.
3.  Add Local Patches (e.g., Ingress Host).
    *   Create `patch-ingress.yaml`.
    *   Add to `patches` list in `kustomization.yaml`.

### Step 5: Register in ArgoCD (Explicit List Pattern)
1.  **Edit:** `appset-core.yaml` (for infra) or `appset-apps-[cluster].yaml` (for workloads).
2.  **Add to List:** Add your app to the `generators.list.elements` section:
    ```yaml
    - app: [app-name]
      namespace: [ns]
      serverSideApply: "true"
      replace: "false"
    ```
3.  **Result:** ArgoCD will pick up the new item and deploy it.
    *   **Core Apps:** Deployed to ALL clusters (Ruth, Arr, etc.).
    *   **Workload Apps:** Deployed only to the specific cluster AppSet you edited.

## 2. Safe Shutdown (Deletion)

**Goal:** Remove an app *without* deleting its data (PVCs).

> **WARNING:** Never delete the ArgoCD Application directly if you want to keep data.

### Protocol
1.  **Target:** `clusters/[cluster]/[app]/kustomization.yaml`.
2.  **Action:** Change the base resource.
    *   **From:** `../../apps/services/[app]/overlays/prod`
    *   **To:** `../../apps/services/[app]/overlays/maintenance`
    *   (Note: Ensure `overlays/maintenance` exists and uses `patches/scale-to-zero.yaml`).
3.  **Result:** Workloads scale to 0. PVCs remain bound.
4.  **Verification:** `kubectl get pods -n [app]` (Should be 0).
4.  **Verification:** `kubectl get pods -n [app]` (Should be 0).

## 3. Managing StatefulSet Storage (PVCs)

**Goal:** Override StorageClass or Size defined in a Helm Chart without forking it.

### Protocol
1.  **Do NOT** modify `volumeClaimTemplates` in `base/values.yaml` if the chart allows it (it often leads to render issues).
2.  **Instead**: Use a **Kustomize Patch**.
3.  **Create:** `apps/services/[app]/components/storage-[type]/patch-storage.yaml`.
4.  **Content:**
    ```yaml
    apiVersion: apps/v1
    kind: StatefulSet
    metadata:
      name: [name]
    spec:
      volumeClaimTemplates:
        - metadata:
            name: [pvc-name-from-chart]
          spec:
            storageClassName: [new-class]
            resources:
              requests:
                storage: [new-size]
    ```
5.  **Benefit:** Allows different clusters to use different storage backends (e.g., `longhorn` vs `local-path`) for the same app.
## 4. Debugging & Fixing

**Goal:** Fix a broken application.

### Decision Tree: Global vs Local
Before writing code, ask: "Is this a Global Issue or a Local Issue?"

#### Path A: Global Issue (e.g., Buggy Config, Wrong Image)
*   **Fix Location:** `apps/services/[app]/base/` (Values) or `apps/services/[app]/patches/`.
*   **Impact:** Affects ALL clusters using this app/profile.

#### Path B: Local Issue (e.g., Ingress Host, Quota)
*   **Fix Location:** `clusters/[cluster]/[app]/`.
*   **Method:**
    *   Edit `kustomization.yaml`.
    *   Add/Edit `patch-local.yaml`.
*   **Impact:** Affects ONLY this cluster.

### Technique: Local Chart Inflation
If you need to see the full YAML to match a patch path:
1.  Run `python .agent/skills/kubernetes-management/scripts/inflate_chart.py [path_to_kustomization]`.
2.  Inspect `debug_full.yaml`.
3.  **DELETE** `debug_full.yaml` before committing.

## 5. Verification

Always run the structure validator after creating/moving files:
`python .agent/skills/kubernetes-management/scripts/validate_structure.py .`
