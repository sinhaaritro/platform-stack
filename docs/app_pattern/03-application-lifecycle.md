# Application Lifecycle

This document covers the end-to-end lifecycle of a Kubernetes application: creating, shutting down, and managing storage. It is the operational guide for adding or removing workloads from the platform.

## Table of Contents

1. [Creating a New Application](#1-creating-a-new-application)
2. [Safe Shutdown (Deletion)](#2-safe-shutdown-deletion)
3. [Managing StatefulSet Storage (PVCs)](#3-managing-statefulset-storage-pvcs)
4. [Feature Extraction Protocol](#4-feature-extraction-protocol)
5. [Related Documentation](#5-related-documentation)

---

## 1. Creating a New Application

Follow these 5 steps to add a new app (e.g., `radarr`) to a cluster.

### Step 1: Define the Base

1. Identify the Helm Chart URL and version.
2. Create `apps/services/[app]/base/kustomization.yaml`:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

helmCharts:
  - name: radarr
    repo: https://charts.example.com
    version: 1.0.0
    releaseName: radarr
    namespace: radarr
    valuesFile: values.yaml
```

3. Create `apps/services/[app]/base/values.yaml` — start minimal.

### Step 2: Create Components

For complex apps where features need to be toggled or configured independently of the environment:

1. Create `apps/services/[app]/components/[name]/kustomization.yaml`.
2. Common component types:

| Type | Example | Purpose |
|---|---|---|
| Features | `components/s3-config` | Jobs, scripts, setup logic |
| Configuration | `components/replicas-1` | Replica counts |
| Storage | `components/storage-longhorn` | StorageClass overrides |
| Secrets | `components/secrets` | SealedSecrets + env patches |
| Maintenance | `components/maintenance` | Scale-to-zero |

> **Secrets Component:** When creating a `components/secrets`, follow the full SealedSecrets workflow documented in [Advanced Secrets Pattern](../secrets/04-advanced-secrets-pattern.md).

### Step 3: Create Profiles (Overlays) (If Needed)

1. Create `apps/services/[app]/overlays/prod/kustomization.yaml`:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - ../../base

patches:
  # - path: ../../patches/high-availability.yaml
```

2. Compose the profile by selecting patches and components from the shared library.
3. Non-reusable patches *can* live in the overlay folder, but prefer shared patches.

### Step 4: Implement in Cluster

1. Create `clusters/[cluster]/[app]/kustomization.yaml`:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: radarr

resources:
  - ../../../apps/services/radarr/overlays/prod

patches:
  # - path: patch-ingress.yaml
```

2. Add cluster-specific patches as needed (e.g., Ingress host).

### Step 5: Register in ArgoCD

Applications are registered using the **Explicit List Pattern**.

1. **Edit** the appropriate ApplicationSet:
   - `appset-core.yaml` — for infrastructure apps deployed to **all** clusters.
   - `appset-apps-[cluster].yaml` — for workload apps deployed to **one** cluster.

2. **Add to the list** in `generators.list.elements`:

```yaml
- app: radarr
  namespace: radarr
  serverSideApply: "true"
  replace: "false"
```

3. ArgoCD will automatically detect and deploy the new item.

> **The Exclusion Principle:** If promoting an app from a cluster-specific AppSet to `appset-core.yaml`, you **must** remove it from the cluster AppSet to avoid duplicate management.

---

## 2. Safe Shutdown (Deletion)

**Goal:** Remove an app's workloads *without* deleting its data (PVCs).

> **⚠️ WARNING:** Never delete the ArgoCD Application resource directly if you want to keep data.

### Protocol

1. **Target:** `clusters/[cluster]/[app]/kustomization.yaml`
2. **Action:** Switch the base resource to the maintenance overlay:

```diff
 resources:
-  - ../../../apps/services/[app]/overlays/prod
+  - ../../../apps/services/[app]/overlays/maintenance
```

3. **Prerequisite:** Ensure `overlays/maintenance` exists and applies the `patches/scale-to-zero.yaml` patch.
4. **Result:** All workload pods scale to 0. PVCs remain bound and intact.

### Verification

```sh
kubectl get pods -n [app]    # Should return 0 pods
kubectl get pvc -n [app]     # PVCs should still be Bound
```

---

## 3. Managing StatefulSet Storage (PVCs)

**Goal:** Override StorageClass or PVC size defined in a Helm Chart without forking it.

### Protocol

1. **Do NOT** modify `volumeClaimTemplates` in `base/values.yaml` (this often causes render issues with Helm).
2. **Instead:** Use a Kustomize patch via a storage component.
3. **Create:** `apps/services/[app]/components/storage-[type]/patch-storage.yaml`:

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

4. **Benefit:** Different clusters can use different storage backends (e.g., `longhorn` vs. `local-path`) for the same app by selecting different storage components.

---

## 4. Feature Extraction Protocol

**Rule:** If a feature requires extra resources (Jobs, ConfigMaps, Scripts) or complex patching, do **not** bury it in an overlay.

1. **Extract:** Create `apps/services/[app]/components/[feature]/`.
2. **Encapsulate:** Place all resources, patches, and logic in that folder with a `kustomization.yaml`.
3. **Import:** Reference it in the overlay or cluster `kustomization.yaml`.
4. **Why:** Keeps the Base clean, the Overlay simple, and the feature independently testable.

---

## 5. Related Documentation

- [Directory Structure](./01-directory-structure.md) — Folder hierarchy and naming conventions.
- [Base + Patches + Overlays](./02-base-patches-overlays.md) — The composition model and patching decision tree.
- [Debugging Guide](./04-debugging-guide.md) — Troubleshooting broken applications.
- **Secrets Management:**
  - [Secrets Management Policy](../secrets/01-secrets-management-policy.md) — The cardinal rules for handling sensitive data.
  - [Creating Kubernetes Secrets](../secrets/03-creating-kubernetes-secrets.md) — How to create and seal secrets.
  - [Advanced Secrets Pattern](../secrets/04-advanced-secrets-pattern.md) — Cross-namespace bridging and the full secrets component workflow.
