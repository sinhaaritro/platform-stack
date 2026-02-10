# Patching Strategies & Configuration Guidelines

> **Source of Truth:** This document defines the configuration standards for the `kubernetes-management` skill.

## 1. The "Base + Patches + Overlays" Model

We utilize a flexible **Composition Pattern**. Instead of deep linear inheritance, we compose functionality from atomic pieces.

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
    *   **Rule:** Favor putting patches here (Shared) over inside Overlays (Embedded).

    *   **Rule:** Favor putting patches here (Shared) over inside Overlays (Embedded).

3.  **Components (The Modules)**
    *   **Location:** `apps/[category]/[app]/components/[name]`
    *   **Role:** Encapsulated feature sets (Base + Patches).
    *   **Examples:** `s3-config`, `replicas-1`, `storage-longhorn`.
    *   **Logic:** A mini-kustomization that bundles resources and patches for a specific purpose.

4.  **Overlays (The Profiles)**
    *   **Location:** `apps/[category]/[app]/overlays/`
    *   **Role:** Pre-packaged compositions for standard scenarios.
    *   **Logic:** `Base` + `Select Patches` (Composition over Inheritance).
    *   **Examples:** `dev` (Base), `prod` (Base + HA), `maintenance` (Base + Zero Replicas).
    *   **Exception:** Truly unique patches that will *never* be reused can leverage `patchesStrategicMerge` inline or live in the overlay folder, but this is rare.

4.  **Overlays (The Profiles)**
    *   **Location:** `apps/[category]/[app]/overlays/`
    *   **Role:** Pre-packaged compositions for standard scenarios.
    *   **Logic:** `Base` + `Components` + `Select Patches`.
    *   **Examples:** `dev` (Base), `prod` (Base + HA), `maintenance` (Base + Scaling Component).
    *   **Exception:** Truly unique patches that will *never* be reused can leverage `patchesStrategicMerge` inline or live in the overlay folder, but this is rare.

5.  **Cluster Implementation (The Deployment)**
    *   **Location:** `clusters/[cluster]/[app]/`
    *   **Role:** The final binding to a specific cluster.
    *   **Logic:** Consumes an Overlay (recommended) or Base.
    *   **Flexibility:** Applies cluster-specific patches (e.g., Ingress Host) on top.

---

## 2. Configuration Guidelines

### A. The Base
**File:** `apps/services/[app]/base/kustomization.yaml`
*   Use `helmCharts` with `valuesFile`.
*   Enable Ingress/Resources with dummy values so objects are generated for later patching.

### B. The Patches
**File:** `apps/services/[app]/patches/[feature].yaml`
*   **Functional:** Changes *one* aspect (e.g., `replicas: 0`).
*   **Self-Contained:** Must be a valid Kustomize patch.

### C. The Overlays
**File:** `apps/services/[app]/overlays/[profile]/kustomization.yaml`
*   **Composition:** `resources: [ ../../base ]` + `patches: [ ../../patches/feature.yaml ]`.
*   **Rule:** Do *not* redefine Helm charts here. Only patch.

### D. The Cluster Implementation
**File:** `clusters/[cluster]/[app]/kustomization.yaml`
*   **Consumption:** `resources: [ ../../../apps/services/[app]/overlays/prod ]`.
*   **Local Patching:** Add `patches: [ patch-local-ingress.yaml ]` for specific overrides.

---

## 3. Patching Strategy & Decision Tree

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

## 4. Naming Conventions

*   **Patches Folder:** `/patches/` (Plural).
*   **Patch Files (Shared):** Descriptive names (e.g., `scale-to-zero.yaml`, `high-availability.yaml`).
*   **Patch Files (Local):** `patch-[logic].yaml` (e.g., `patch-ingress.yaml`).
*   **Resources:** `resource-[kind]-[name].yaml` (e.g., `resource-cm-dashboard.yaml`).
*   **SecretGenerators:** Suffix with purpose (e.g., `podinfo-auth`).

---

## 5. Common Pitfalls & Anti-Patterns

1.  **The "Values in Overlay" Fallacy:**
    *   *Bad:* Defining `helmCharts` again in Overlay to pass different values.
    *   *Correct:* Inflate Helm in Base to default YAML. Patch the YAML in Overlay/Cluster.

2.  **The "Path Blindness":**
    *   *Bad:* `resources: [ ../base ]` (Relative paths are tricky).
    *   *Correct:* Calculate depth. Cluster -> Overlay = `../../../`.

3.  **Imperative Secret Injection:**
    *   *Bad:* Hardcoding `value: password`.
    *   *Correct:* Use `secretGenerator` + `valueFrom`.
