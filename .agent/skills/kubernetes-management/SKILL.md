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

### Step 2: Create Profiles (Overlays)
1.  Create `apps/services/[app]/overlays/prod/kustomization.yaml`.
    *   `resources: [ ../../base ]`
    *   `resources: [ ../../base ]`
    *   **Compostion:** Use `patches: [ ../../patches/feature.yaml ]`.
    *   *Note:* Unique, non-reusable patches can live in the overlay folder, but prefer shared patches.

### Step 3: Implement in Cluster
1.  Create `clusters/[cluster]/[app]/kustomization.yaml`.
    *   `resources: [ ../../../apps/services/[app]/overlays/prod ]`
    *   `namespace: [app]`
2.  Add Local Patches (e.g., Ingress Host).
    *   Create `patch-ingress.yaml`.
    *   Add to `patches` list in `kustomization.yaml`.

### Step 4: Register in ArgoCD
1.  Add the app to `kubernetes/bootstrap/[HUB]/appset-apps-[CLUSTER].yaml` (if using Git Generator).
2.  **Matrix Generator:** If adding to `appset-core.yaml` (for all clusters), ensure you **EXCLUDE** it from the individual `appset-apps-[CLUSTER].yaml` files to avoid conflicts.

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

## 3. Debugging & Fixing

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

## 4. Verification

Always run the structure validator after creating/moving files:
`python .agent/skills/kubernetes-management/scripts/validate_structure.py .`
