# Kubernetes Application Pattern: The "Russian Doll" Strategy

This document outlines the standard pattern for onboarding and managing Kubernetes applications in this repository. We use a **"Russian Doll" Strategy** (Composition) combining **Kustomize** and **Helm**.

## Core Concept

The key concept is that **Kustomize inflates (renders) the Helm chart at the Base level**, converting it into standard YAML objects (Deployment, Service, etc.).

 The layers above it (Profiles and Clusters) **do not** patch the Helm values file; they patch the **Resulting YAML objects**. This allows us to modify any aspect of the application manifest even if the original Helm chart does not expose a value for it.

## The Enterprise Standard: The "Kustomize Wrapper" Pattern

We explicitly use **Helm for Packaging** and **Kustomize for Configuration/Patching**.

> **Advisory:** We do **not** use Flux `HelmRelease` resources. Running two GitOps engines (ArgoCD + Flux) is unnecessary complexity. We stick to standard Kubernetes resources and Kustomize.

### Why this pattern?
1.  **Vendor Upstream:** We reference official Helm charts directly.
2.  **Clean Overrides:** We avoid copy-pasting monolithic `values.yaml` files. We only maintain the *delta*.
3.  **Last Mile Patching:** Kustomize allows us to path the resulting YAML (e.g., adding annotations to Secrets) even if the Helm chart doesn't expose a variable for it.

---

## Directory Structure: The "Catalog" vs. "Inventory"

There is a deliberate structural difference between the **Apps Catalog** (`kubernetes/apps`) and the **Cluster Inventory** (`kubernetes/clusters`).

### 1. The Apps Catalog (`kubernetes/apps/`)
This is organized by **Category**. It contains the reusable definitions.
*   `infrastructure/` (System level: cert-manager, ingress, monitoring, etc.)
*   `services/` (User level: immich, plex, etc.)

### 2. The Cluster Inventory (`kubernetes/clusters/`)
This is organized by **Target**. It contains the specific implementations.
*   **Flat Structure:** Inside a cluster folder (e.g., `ruth`), we do **not** mirror the `infrastructure/` or `services/` folders.
*   **Single Tenant Model:** Currently, we assume **1 Tenant = 1 Cluster**. All apps for that tenant sit directly under the cluster folder or within the `tenants/` folder if separation is needed in the future.

```text
kubernetes/
├── apps/                                   # [THE CATALOG] (Categorized)
│   ├── infrastructure/
│   │   └── cert-manager/ ...
│   ├── services/
│   │   └── immich/                         # [THE CATALOG] 
│   │   │   ├── base/                       # Level 1: The Core Helm Chart + Common Resources
│   │   │   │   ├── kustomization.yaml
│   │   │   │   ├── values.yaml             # Vendor defaults
│   │   │   │   └── common-secret.yaml      # (Resource Addition #1)
│   │   │   │
│   │   │   └── overlays/
│   │   │       └── minimal/                # Level 2: The "Low Resource" Profile
│   │   │           ├── kustomization.yaml
│   │   │           ├── scaling.yaml        # (Patch: Reduce Pods)
│   │   │           └── extra-cm.yaml       # (Resource Addition #2)
│
└── clusters/ruth/              # [THE INVENTORY] (Flat)
    ├── cert-manager/           # Infrastructure app
    └── tenants/person-a/immich/# Tenant app
```

Future
```text
│
└── clusters/ruth/              # [THE INVENTORY]
    └── tenants/person-a/immich/
        ├── kustomization.yaml  # Level 3: The Implementation
        └── ingress.yaml        # (Resource Addition #3 + Custom URL)
```

---

## Detailed Implementation Layers

### Level 1: The Base (`apps/services/immich/base`)
**Goal:** Define the Helm Chart source and add a global secret used by all versions.

**`kustomization.yaml`**
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: immich

helmCharts:
- name: immich
  repo: https://immich-app.github.io/immich-charts
  version: 0.8.0
  releaseName: immich
  valuesFile: values.yaml
  includeCRDs: true

resources:
  - common-secret.yaml
```

### Level 2: The Profile (`apps/services/immich/overlays/minimal`)
**Goal:** Inherit Base, reduce replicas to 1 (Patching), and add a ConfigMap (Resource #2).

**`kustomization.yaml`**
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - ../../base
  - extra-cm.yaml

patches:
  - path: scaling.yaml
    target:
      kind: Deployment
      name: immich-.*
```

**`scaling.yaml` (The Patch)**
```yaml
- op: replace
  path: /spec/replicas
  value: 1
```

### Level 3: The Cluster Implementation (`clusters/ruth/immich`)
**Goal:** Inherit "Minimal", add Ingress with custom URL (Resource #3), and deploy.

**`kustomization.yaml`**
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: person-a-immich

resources:
  - ../../../../../../apps/services/immich/overlays/minimal
  - ingress.yaml

patches:
  - target:
      kind: Ingress
      name: immich-ingress
    patch: |-
      - op: replace
        path: /spec/rules/0/host
        value: photos.person-a.com
```

**`ingress.yaml` (The Cluster Specific Resource)**
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: immich-ingress
spec:
  rules:
    - host: placeholder # Kustomize will patch this
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: immich-server
                port:
                  number: 3001
```

---


## Bootstrap & Automation (`kubernetes/bootstrap/`)

For multi-cluster management, we use **ArgoCD ApplicationSets** located in the `bootstrap` folder.

### The Matrix Generator Pattern
To manage core infrastructure (like `cert-manager`, `monitoring`, `system-patches`) across **ALL** clusters efficiently, we use the **Matrix Generator**.

1.  **Generator 1 (Clusters):** Automatically discovers all clusters registered in ArgoCD.
2.  **Generator 2 (List):** Defines the list of applications to deploy (name, namespace, sync options).

The Matrix generator acts as a multiplication table: `(Clusters) x (Apps) = Deployments`.
This ensures that if we add a new cluster, it automatically gets the standard baseline configuration without copying paste YAML.

**Example: `appset-core.yaml`**
```yaml
spec:
  generators:
    - matrix:
        generators:
          - clusters: {} # Dynamic discovery
          - list:
              elements:
                - app: cert-manager
                - app: kyverno
                # ...
```

### Tenant Apps
Tenant-specific apps are usually managed by a simpler **Git Generator**, which looks for directories separately in each cluster's folder (e.g., `kubernetes/bootstrap/ruth/appset-apps-ruth.yaml`), allowing for per-cluster customization.

---

## Summary of Rules
1.  **DRY (Don't Repeat Yourself):** The Helm chart is defined **once** (Level 1).
2.  **Profiles:** Different profiles (e.g., `minimal`, `production`) can coexist in the catalog, inheriting from the same base.
3.  **Encapsulation:** The Cluster level simply imports a profile and applies local specifics (URL), without knowing internal details like replica counts.
4.  **Resource Flexibility:** Unique resources (Secret, ConfigMap, Ingress) can be injected at any layer (Base, Overlay, or Cluster).
5.  **Automation:** ApplicationSets handle the "fan-out" to multiple clusters, so humans don't have to manually create ArgoCD Applications.
6.  **Avoid `valuesInline`:** It clutters the `kustomization.yaml`. Always use `valuesFile`.
7.  **Avoid Flux CRDs:** Stick to standard Kubernetes resources (`Deployment`, `Service`) and Kustomize configs.
8.  **Use `patchesStrategicMerge`** for simple overrides (like changing replicas).
9.  **Use `patches` (JSON 6902)** for complex overrides (like injecting a specific container into a list).

This approach gives you the **Dependency Management** of Helm with the **Granular Control** of Kustomize.
