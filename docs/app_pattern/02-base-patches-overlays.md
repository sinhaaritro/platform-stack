# Base + Patches + Overlays

This document explains the composition model used to manage Kubernetes applications across multiple clusters and environments. All apps follow this pattern to ensure consistency, reusability, and clean separation of concerns.

## Table of Contents

1. [The Composition Model](#1-the-composition-model)
2. [Configuration Guidelines](#2-configuration-guidelines)
3. [Patching Decision Tree](#3-patching-decision-tree)
4. [Naming Conventions](#4-naming-conventions)
5. [Common Pitfalls & Anti-Patterns](#5-common-pitfalls--anti-patterns)

---

## 1. The Composition Model

Instead of deep linear inheritance, we **compose** functionality from atomic pieces. There are 5 structural layers, each with a clear role:

### Layer 1: Base (The Foundation)

- **Location:** `apps/[category]/[app]/base/`
- **Role:** The raw Helm Chart definition + a default `values.yaml`.
- **Constraint:** Pure installation only. No environment-specific configuration.

### Layer 2: Patches (The Features)

- **Location:** `apps/[category]/[app]/patches/`
- **Role:** Atomic, reusable units of change. Each patch modifies exactly **one** aspect.
- **Examples:** `scale-to-zero.yaml` (Maintenance), `high-availability.yaml` (3 replicas), `ingress-internal.yaml`.
- **Constraint:** Must be a valid, self-contained Kustomize patch.
- **Rule:** Favor putting patches here (shared) over embedding them inside overlays.

### Layer 3: Components (The Modules)

- **Location:** `apps/[category]/[app]/components/[name]/`
- **Role:** Encapsulated feature sets that bundle resources and patches for a specific purpose.
- **Examples:** `s3-config`, `replicas-1`, `storage-longhorn`, `secrets`.
- **Logic:** Each component is a mini-kustomization with its own `kustomization.yaml`.

### Layer 4: Overlays (The Profiles)

- **Location:** `apps/[category]/[app]/overlays/[profile]/`
- **Role:** Pre-packaged compositions for standard scenarios.
- **Logic:** `Base` + selected `Components` + selected `Patches`.
- **Examples:**
  - `dev` — Base only (minimal)
  - `prod` — Base + HA patch
  - `maintenance` — Base + scale-to-zero patch
- **Exception:** Truly unique patches that will *never* be reused can live in the overlay folder, but this is rare.

### Layer 5: Cluster Implementation (The Deployment)

- **Location:** `clusters/[cluster]/[app]/`
- **Role:** The final binding to a specific cluster.
- **Logic:** Consumes an Overlay (recommended) or Base directly.
- **Flexibility:** Can apply cluster-specific patches (e.g., Ingress host) on top.

---

## 2. Configuration Guidelines

### A. Base Kustomization

**File:** `apps/[category]/[app]/base/kustomization.yaml`

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

helmCharts:
  - name: [APP_NAME]
    repo: [REPO_URL]
    version: [VERSION]
    releaseName: [RELEASE_NAME]
    namespace: [NAMESPACE]
    valuesFile: values.yaml
```

- Always use `valuesFile` (never `valuesInline`).
- Enable Ingress/Resources with placeholder values so that objects are generated for later patching.

### B. Overlay Kustomization

**File:** `apps/[category]/[app]/overlays/[profile]/kustomization.yaml`

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - ../../base

patches:
  # - path: ../../patches/high-availability.yaml
```

- **Composition:** Reference base via `resources`, compose features via `patches`.
- **Rule:** Do *not* redefine Helm charts here. Only patch.

### C. Cluster Kustomization

**File:** `clusters/[cluster]/[app]/kustomization.yaml`

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: [NAMESPACE]

resources:
  - ../../../apps/services/[APP]/overlays/[PROFILE]

patches:
  # - path: patch-local-ingress.yaml
```

- **Consumption:** Point to an overlay (or base) via the correct relative path.
- **Local Patching:** Add cluster-specific overrides via local `patch-*.yaml` files.

---

## 3. Patching Decision Tree

When you need to modify property `X` on resource `Y`, follow this decision tree:

```
Is it a shared feature? (HA, Maintenance, etc.)
├── YES → Create a shared patch in apps/.../patches/
│         Reference it in the overlay.
└── NO
    Is it cluster-specific? (Ingress host, DB password, etc.)
    ├── YES → Create a local patch in clusters/.../[app]/
    │         File: patch-[logic].yaml
    └── NO
        What type of field is X?
        ├── Standard field (replicas, image) → Strategic Merge Patch
        ├── Ordered list (command, args)    → JSON Patch 6902
        │   (Merge patches append to lists, often breaking commands)
        └── Key-value map (env, labels)     → Strategic Merge Patch
```

---

## 4. Naming Conventions

| Element | Convention | Example |
|---|---|---|
| Shared patch files | Descriptive name | `scale-to-zero.yaml`, `high-availability.yaml` |
| Local patch files | `patch-[logic].yaml` | `patch-ingress.yaml` |
| Extra resources | `resource-[kind]-[name].yaml` | `resource-cm-dashboard.yaml` |
| SecretGenerators | Suffix with purpose | `podinfo-auth` |

---

## 5. Common Pitfalls & Anti-Patterns

### ❌ The "Values in Overlay" Fallacy

- **Bad:** Defining `helmCharts` again in an overlay to pass different values.
- **Correct:** Inflate Helm in Base to produce default YAML. Patch the rendered YAML in Overlay or Cluster.

### ❌ The "Path Blindness"

- **Bad:** `resources: [ ../base ]` (incorrect relative depth).
- **Correct:** Calculate the path depth carefully. Cluster → Overlay typically requires `../../../`.

### ❌ Imperative Secret Injection

- **Bad:** Hardcoding secrets with `value: password` in manifests.
- **Correct:** Use `secretGenerator` + `valueFrom`, or SealedSecrets via the secrets component.

> **See Also:** For the full secrets workflow, refer to [Creating Kubernetes Secrets](../secrets/03-creating-kubernetes-secrets.md).
