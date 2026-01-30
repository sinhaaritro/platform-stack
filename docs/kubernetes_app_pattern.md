# Kubernetes Application Pattern: The "Russian Doll" Strategy

This document outlines the standard pattern for onboarding and managing Kubernetes applications in this repository. We use a **"Russian Doll" Strategy** (Composition) combining **Kustomize** and **Helm**.

## Core Concept

The key concept is that **Kustomize inflates (renders) the Helm chart at the Base level**, converting it into standard YAML objects (Deployment, Service, etc.).

 The layers above it (Profiles and Clusters) **do not** patch the Helm values file; they patch the **Resulting YAML objects**. This allows us to modify any aspect of the application manifest even if the original Helm chart does not expose a value for it.

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

### Level 1: The Base (`apps/<category>/<app>/base`)

**Goal:** Define the Helm Chart source and add global resources used by all versions.

**`kustomization.yaml`**
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: immich  # Default namespace (can be overridden)

helmCharts:
- name: immich
  repo: https://immich-app.github.io/immich-charts
  version: 0.8.0
  releaseName: immich
  valuesFile: values.yaml
  includeCRDs: true

# Resource Addition #1 (Global)
resources:
  - common-secret.yaml
```

**`common-secret.yaml`**
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: immich-global-keys
stringData:
  api-key: "placeholder-base"
```

---

### Level 2: The Profile (`apps/<category>/<app>/overlays/minimal`)

**Goal:** Inherit Base, apply profile-specific patches (e.g., reduce replicas), and add profile-specific resources.

**`kustomization.yaml`**
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

# 1. Inherit Level 1
resources:
  - ../../base
  - extra-cm.yaml # Resource Addition #2

# 2. Apply "Minimal" Logic (Patching the output of the Helm Chart)
patches:
  - path: scaling.yaml
    target:
      kind: Deployment
      name: immich-.* # Regex matches immich-server, immich-microservices
```

**`scaling.yaml` (The Patch)**
```yaml
- op: replace
  path: /spec/replicas
  value: 1
```

**`extra-cm.yaml` (The Resource)**
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: minimal-profile-config
data:
  profile: "low-resource-mode"
```

---

### Level 3: The Cluster Implementation (`clusters/<cluster>/.../<app>`)

**Goal:** Inherit a specific Profile (Overlay), apply cluster/tenant-specific patches (e.g., Ingress URL), and deploy.

**`kustomization.yaml`**
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

# 1. Set the destination namespace for this specific tenant
namespace: person-a-immich

# 2. Inherit Level 2 (which inherits Level 1)
resources:
  - ../../../../../../apps/services/immich/overlays/minimal
  - ingress.yaml # Resource Addition #3 (Technically an addition OR a patch depending on approach)

# 3. Patch the Custom URL into the Ingress
patches:
  - target:
      kind: Ingress
      name: immich-ingress # Name defined in ingress.yaml
    patch: |-
      - op: replace
        path: /spec/rules/0/host
        value: photos.person-a.com
```

**`ingress.yaml` (The Cluster Specific Resource)**
```yaml
# We define the Ingress here because the URL is unique to the cluster/user
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
                name: immich-server # Connecting to the Service generated by Helm in Level 1
                port:
                  number: 3001
```

---

## The Build Flow

When ArgoCD runs `kustomize build clusters/ruth/tenants/person-a/immich`, the order of operations is:

1.  **Level 1 Inflates:**
    *   Helm renders `Deployment`, `Service` (with default replicas).
    *   Adds `common-secret.yaml`.
2.  **Level 2 Modifies:**
    *   Receives the objects from Level 1.
    *   Adds `extra-cm.yaml`.
    *   **Patch:** Finds the Deployment, changes Replicas to 1.
3.  **Level 3 Finalizes:**
    *   Receives objects from Level 2.
    *   Changes Namespace to `person-a-immich` for **ALL** objects.
    *   Adds `ingress.yaml`.
    *   **Patch:** Finds the Ingress, sets host to `photos.person-a.com`.

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

## Why this Strategy?

1.  **DRY (Don't Repeat Yourself):** The Helm chart is defined **once** (Level 1).
2.  **Profiles:** Different profiles (e.g., `minimal`, `production`) can coexist in the catalog, inheriting from the same base.
3.  **Encapsulation:** The Cluster level simply imports a profile and applies local specifics (URL), without knowing internal details like replica counts.
4.  **Resource Flexibility:** Unique resources (Secret, ConfigMap, Ingress) can be injected at any layer (Base, Overlay, or Cluster).
5.  **Automation:** ApplicationSets handle the "fan-out" to multiple clusters, so humans don't have to manually create ArgoCD Applications.
