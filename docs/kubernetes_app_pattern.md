# Authoritative Kubernetes Architecture Guide for AI Agent 
**Version:** 4.0 (Complete)

**Author:** Aritro Sinha

**Scope:** Architecture, Coding Standards, Directory Structure, Operational Protocols.

---

## 1. Architectural Philosophy & Mental Models

### A. The "Russian Doll" Configuration Pattern
We utilize a strict 3-layer inheritance model. Specificity increases as we go down the layers.
*   **Level 1: Base (The Package)**
    *   **Technology:** `Helm` (via Kustomize `helmCharts` and `valuesFile`).
    *   **Role:** Inflates the upstream chart into raw YAML. Sets "Safe Defaults".
    *   **Constraint:** NEVER contains environment-specific logic.
*   **Level 2: Overlay (The App Profile)**
    *   **Technology:** `Kustomize` (Patches & Resources).
    *   **Role:** Defines logical application profiles (e.g., `dev`, `prod`, `minimal`). Modifies replicas, feature flags, UI colors.
    *   **Constraint:** NEVER contains infrastructure-specific data (Ingress hosts, specific secrets).
*   **Level 3: Cluster (The Tenant/Infra)**
    *   **Technology:** `Kustomize` (Patches & Resources).
    *   **Role:** Binds the App Profile to a specific Cluster. Defines Ingress domains, injects Secrets, NetworkPolicies.
    *   **Constraint:** The final build target.

> **Advisory:** We do **not** use Flux `HelmRelease` resources. Running two GitOps engines (ArgoCD + Flux) is unnecessary complexity. We stick to standard Kubernetes resources and Kustomize.

#### Why this pattern?
1.  **Vendor Upstream:** We reference official Helm charts directly.
2.  **Clean Overrides:** We avoid copy-pasting monolithic `values.yaml` files. We only maintain the *delta*.
3.  **Last Mile Patching:** Kustomize allows us to path the resulting YAML (e.g., adding annotations to Secrets) even if the Helm chart doesn't expose a variable for it.

### B. The "Hub-and-Spoke" GitOps Topology
*   **Hub (Management Cluster):** The cluster running ArgoCD (e.g., `CLS1`). It manages itself and other clusters.
*   **Spoke (Target Cluster):** A cluster registered to the Hub. It does not run its own ArgoCD control plane.
*   **ApplicationSets:** Used to automate deployment.
    *   `appset-core`: Deploys common apps to **ALL** clusters (Matrix Generator).
    *   `appset-apps-[CLUSTER]`: Deploys unique apps to **ONE** specific cluster (Git Directory Generator).

### C. The "Remote Operator" Execution Model
The environment where this code is generated is **NOT** the cluster.
*   **Local Scope:** File generation, `kustomize build` (dry-run), Git operations.
*   **Remote Scope:** `kubectl` commands, logs, debugging.
*   **Bridge:** All remote interaction **MUST** be tunneled through **Ansible** using the `Taskfile`.

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
│   ├── inventory.yml                        # Host list (Look here to find IPs)
│   ├── Taskfile.yml                         # Wrappers commands for remote execution
│   └── ansible.cfg                          # Connection config
├── kubernetes/
│   ├── Taskfile.yml                         # Common K8s helper commands
│   ├── apps/                                # APP DEFINITIONS
│   │   ├── infrastructure/
│   │   │   └── cert-manager/ ...
│   │   └── services/
│   │       └── [APP_NAME]/
│   │           ├── base/                    # LEVEL 1 (Helm Inflation)
│   │           │   ├── kustomization.yaml
│   │           │   └── values.yaml
│   │           └── overlays/                # LEVEL 2 (App Profiles)
│   │               └── [PROFILE_NAME]/      # e.g., dev, prod
│   │                   ├── kustomization.yaml
│   │                   └── patch-[logic].yaml
│   ├── clusters/                            # CLUSTER INSTANCES (LEVEL 3)
│   │   └── [CLUSTER_NAME]/                  # e.g., CLS1, CLS2
│   │       └── [APP_NAME]/                  # e.g., podinfo
│   │           ├── kustomization.yaml
│   │           └── patch-[infra].yaml
│   └── bootstrap/                           # MANAGEMENT LAYER (ArgoCD)
│       └── [MGMT_CLUSTER]/                  # e.g., CLS1 (The Hub)
│           ├── appset-core.yaml             # Apps installed everywhere
│           ├── appset-apps-CLS1.yaml        # Apps specific to CLS1 (Hub)
│           ├── appset-apps-CLS2.yaml        # Apps specific to CLS2 (Spoke)
│           └── appset-apps-CLS3.yaml        # Apps specific to CLS3 (Spoke)
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

## 3. Operational Protocols: Bootstrapping & Cluster Management

For multi-cluster management, we use **ArgoCD ApplicationSets** located in the `bootstrap` folder.

### A. The "Hub-and-Spoke" Definition
The `bootstrap` folder is organized by **Management Cluster**.
*   If `CLS1` is the Hub, all ApplicationSets live in `kubernetes/bootstrap/CLS1/`.
*   Target clusters (`CLS2`, `CLS3`) **do not** have their own folder in `bootstrap`. They have a definition file inside the Hub's folder.

#### The Matrix Generator Pattern
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
                  namespace: networking
                  serverSideApply: "true"
                  replace: "false"
                - app: longhorn
                  namespace: storage
                  serverSideApply: "true"
                  replace: "false"
                # ...
```

> Note: If we want to add a app to all cluster then we have to add it to `appset-core.yaml`. And we have to manually excluse the app from the cluster specific files like `kubernetes/bootstrap/CLS1/appset-apps-CLS1.yaml`, `kubernetes/bootstrap/CLS1/appset-apps-CLS2.yaml`, `kubernetes/bootstrap/CLS1/appset-apps-CLS3.yaml`

#### Tenant Apps
Tenant-specific apps are usually managed by a simpler **Git Generator**, which looks for directories separately in each cluster's folder (e.g., `kubernetes/bootstrap/CLS1/appset-apps-CLS1.yaml`), allowing for per-cluster customization.

### B. Protocol: Adding a New Cluster (e.g., CLS3)
To bring a new cluster under management:
1.  **Register:** Connect `CLS3` to the ArgoCD on `CLS1` (CLI: `argocd cluster add ...` via Ansible).
2.  **Define:** Create a new file `kubernetes/bootstrap/CLS1/appset-apps-CLS3.yaml`.
3.  **Content:** Copy the pattern from `CLS2`, changing the `destination.name` and the `git.directories.path`.

```yaml
# kubernetes/bootstrap/CLS1/appset-apps-CLS3.yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: apps-cls3
spec:
  generators:
    - git:
        repoURL: https://github.com/my-org/gitops.git
        revision: HEAD
        directories:
          - path: kubernetes/clusters/CLS3/* # Target the specific cluster folder
  template:
    metadata:
      name: 'CLS3-{{path.basename}}'
    spec:
      project: default
      source:
        repoURL: https://github.com/my-org/gitops.git
        targetRevision: HEAD
        path: '{{path}}'
      destination:
        name: CLS3 # Matches the registered cluster name
        namespace: '{{path.basename}}'
```

### C. Protocol: Adding a New App
1.  **Global App:** Add to `appset-core.yaml`. It automatically rolls out to CLS1, CLS2, CLS3...
2.  **Cluster Specific App:**
    *   Create folder `kubernetes/clusters/CLS3/my-new-app`.
    *   **Result:** `appset-apps-CLS3.yaml` automatically finds this folder and deploys it only to CLS3.

---

## 4. Operational Protocols: Execution & Debugging

**Rule:** Never assume `kubectl` works locally against the target cluster. Use Ansible tunneling from `ansible/Taskfile.yml`..

### Example Scenario: "Investigate why Podinfo is failing on CLS1"

**Agent Thought Process:**
1.  **Goal:** Debug Podinfo on CLS1.
2.  **Constraint:** Cannot run kubectl locally.
3.  **Action 1 (Locate Host):** Read `ansible/inventory.yml`.
    *   *Found:* `CLS1` group has host `cls1-control-plane-01`.
4.  **Action 2 (Check Status):** Construct Ansible command via Taskfile.
    *   *Command:* `task -d ansible k8s:cmd HOST=cls1-control-plane-01 CMD="kubectl get pods -n podinfo"`
    *   *Output:* `podinfo-dep-xyz CrashLoopBackOff`
5.  **Action 3 (Deep Dive):** Check logs/describe.
    *   *Command:* `task -d ansible k8s:cmd HOST=cls1-control-plane-01 CMD="kubectl logs -l app=podinfo -n podinfo --tail=20"`
    *   *Output:* `Error: Memory limit exceeded`
6.  **Action 4 (Fix):** Modify Code (Local).
    *   Edit `kubernetes/clusters/CLS1/podinfo/patch-resources.yaml` (Level 3 patch).
    *   Increase Memory limit.
7.  **Action 5 (Deploy):** Commit & Push. ArgoCD handles the rest.

---

## 5. Configuration & Coding Guidelines

### Level 1: Base (Helm Inflation)
**File:** `kubernetes/apps/services/[APP]/base/kustomization.yaml`

**Rule:** Use `helmCharts` with `valuesFile`. Enable Ingress/Resources with dummy values so objects are generated for later patching.

### Level 2: Overlay (App Profile)
**File:** `kubernetes/apps/services/[APP]/overlays/[PROFILE]/kustomization.yaml`

**Rule:** Inherit Base. Use **Strategic Merge Patches** for simple updates.

### Level 3: Cluster (Infra Binding)
**File:** `kubernetes/clusters/[CLUSTER]/[APP]/kustomization.yaml`

**Rule:** Inherit Overlay. Use **JSON Patches** for lists. Use **SecretGenerator** for credentials.

---

## 6. Naming Conventions
- **File Naming**:
    * Kustomization file: kustomization.yaml (Lowercase).
    * Patches: patch-[functional-area].yaml (e.g., patch-ingress.yaml, patch-limits.yaml).
    * New Resources: resource-[kind]-[name].yaml (e.g., resource-cm-dashboard.yaml).
- **Resource Naming**:
    * All Kubernetes objects must use kebab-case.
    * SecretGenerators should use a functional suffix (e.g., podinfo-auth).
- **Patch Naming (Metadata)**:
    * Patches usually do not need a filename inside the file content, but the name and namespace in the YAML MUST match the target object exactly.

---

## 7. Patching Strategy & Decision Tree

**INPUT:** User wants to modify property `X` on resource `Y`.

1.  **Is this a new object?** (e.g., Dashboard ConfigMap, NetworkPolicy)
    *   **YES:** Create `resource-[kind]-[name].yaml`. Add to `resources` list.
    *   **NO:** Proceed to 2.

2.  **Is `X` a standard field?** (e.g., `replicas`, `image`, `service.type`, `tolerations`)
    *   **Action:** Use **Strategic Merge Patch**.
    *   **File:** `patch-[feature].yaml`.
    *   **Style:** Copy original structure, include only changed fields.

3.  **Is `X` a Key-Value List?** (e.g., `env`, `volumeMounts`, `labels`)
    *   **Action:** Use **Strategic Merge Patch**.
    *   **Logic:** Kubernetes merges these by the "name" key. New names are appended; existing names are updated.

4.  **Is `X` an Ordered List?** (e.g., `command`, `args`, `ingress.rules`)
    *   **Action:** Use **JSON Patch 6902**.
    *   **Why:** Merge patches often overwrite the whole list or append incorrectly.
    *   **Style:**
        ```yaml
        - target:
            kind: Deployment
            name: my-app
          patch: |-
            - op: replace
              path: /spec/template/spec/containers/0/command/2
              value: "--new-flag"
        ```

5.  **Is the goal to DELETE an object?**
    *   **Action:** Use `$patch: delete` directive in the Kustomization file or patch.

---

## 8. Syntax Guide & Code Snippets

### A. Level 1: Base (Helm Inflation)
**File:** `apps/services/podinfo/base/kustomization.yaml`

**Rule:** `valuesFile` is preferred over `valuesInline` for readability.

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

helmCharts:
  - name: podinfo
    repo: https://stefanprodan.github.io/podinfo
    version: 6.9.4
    releaseName: my-podinfo
    namespace: podinfo
    includeCRDs: true
    valuesFile: values.yaml # Must exist in same folder
```

### B. Level 2: Overlay (Strategic Merge Patch)
**File:** `apps/services/podinfo/overlays/dev/patch-replicas.yaml`

**Rule:** Only include fields that change.

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-podinfo # STRICT MATCH
  namespace: podinfo # STRICT MATCH
spec:
  replicas: 1
  template:
    spec:
      containers:
        - name: podinfo # STRICT MATCH
          env:
            - name: LOG_LEVEL # Updating existing env
              value: "debug"
            - name: NEW_FEATURE # Adding new env
              value: "enabled"
```

### C. Level 3: Cluster (JSON Patch 6902)
**File:** `cluster/tenant-a/podinfo/kustomization.yaml`

**Rule:** Used for precise surgical changes to arrays or complex paths.

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: podinfo

resources:
  - ../../../apps/services/podinfo/overlays/dev

patches:
  - target:
      kind: Ingress
      name: my-podinfo
    patch: |-
      - op: replace
        path: /spec/rules/0/host
        value: "tenant-a.example.com"
```

### D. Secret Generation (Level 3 Only)
**Rule:** Never commit base64 secrets. Use `secretGenerator`.

```yaml
secretGenerator:
  - name: db-creds
    literals:
      - username=admin
      - password=complex-password
    # OR file based
    # files:
    #   - secrets/db.properties
```

---

## 9. Common Pitfalls & Anti-Patterns (The "Don't Do This" List)

1.  **The "Values in Overlay" Fallacy:**
    *   *Bad:* Defining `helmCharts` again in `overlays/dev/kustomization.yaml` to pass a different `values.yaml`.
    *   *Why:* This creates two different Helm releases.
    *   *Correct:* Inherit the Base (which has the Helm Chart) and use **Patches** to modify the output.

2.  **The "Path Blindness":**
    *   *Bad:* `resources: [ ../base ]` (Relative paths are tricky).
    *   *Correct:* Always calculate the relative path based on the depth.
        *   Overlay -> Base: `../../base`
        *   Cluster -> Overlay: `../../../apps/services/[app]/overlays/[profile]`

3.  **Imperative Secret Injection:**
    *   *Bad:* Hardcoding `value: my-password` in a `Deployment` patch.
    *   *Correct:* Create a `Secret` (via generator) and use `valueFrom: secretKeyRef` in the `Deployment` patch.

4.  **Overwriting Lists with Strategic Merge:**
    *   *Bad:* Trying to change the 3rd argument in `command: [...]` by copying the whole list in a merge patch.
    *   *Why:* This often appends rather than replaces, or replaces the whole list destroying other settings.
    *   *Correct:* Use JSON Patch 6902 for ordered lists (`command`, `args`).

---


## 10. AI Agent Verification Checklist

Before generating code or executing commands, verify:

1.  [ ] **Context Check:** Am I writing code (Local) or debugging (Remote/Ansible)?
2.  [ ] **Pathing:** Am I using `clusters` (plural) for level 3?
3.  [ ] **Bootstrap Check:**
    *   Is this a new Cluster? (Update `bootstrap/[HUB]/appset-apps-[NEW_CLUSTER].yaml`).
    *   Is this a Core app? (Update `appset-core.yaml` & check excludes).
4.  [ ] **Secret Check:** Did I use `secretGenerator` instead of hardcoding secrets?
5.  [ ] **Patch Logic:** Did I use JSON Patch for ordered lists (`args`) and Merge Patch for maps (`env`)?
6.  [ ] **Host Check:** Did I check `ansible/inventory.yml` before constructing a remote command?

---

## 11. Complete Example: "The Podinfo Standard"

**Input Request:** "Deploy Podinfo to 'tenant-b' cluster using 'prod' profile. Change Host to 'b.com' and Memory limit to '1Gi'."

**AI Generated Plan:**

1.  **Apps Layer:** `apps/services/podinfo/overlays/prod` exists.
2.  **Cluster Layer:** Create `cluster/tenant-b/podinfo`.

**File:** `cluster/tenant-b/podinfo/kustomization.yaml`
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: podinfo

resources:
  - ../../../apps/services/podinfo/overlays/prod

patches:
  - path: patch-ingress-host.yaml
  - path: patch-memory-limit.yaml
```

**File:** `cluster/tenant-b/podinfo/patch-ingress-host.yaml`
```yaml
- target:
    kind: Ingress
    name: my-podinfo
  patch: |-
    - op: replace
      path: /spec/rules/0/host
      value: "b.com"
```

**File:** `cluster/tenant-b/podinfo/patch-memory-limit.yaml`
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-podinfo
  namespace: podinfo
spec:
  template:
    spec:
      containers:
        - name: podinfo
          resources:
            limits:
              memory: "1Gi"
```

---

## 12. Maintenance Mode & Scaling

For operational tasks like storage upgrades, we need a standard way to scale applications to 0 without destroying their configuration (replicas, env vars) defined in `overlays/prod`.

**Pattern:** "Cluster Object Patch" using Shared Resources.
We maintain shared patches in `kubernetes/apps/maintenance/`.

### A. The "Scale to Zero" Patch
**File:** `kubernetes/apps/maintenance/patch-scale-zero.yaml`
Sets `replicas: 0` for Deployments and StatefulSets.

### B. Usage (How to enable Maintenance)
Edit the **Level 3 (Cluster)** Kustomization file: `kubernetes/clusters/[CLUSTER]/[APP]/kustomization.yaml`.

```yaml
resources:
  - ../../../apps/services/podinfo/overlays/prod

patches:
  # UNCOMMENT TO ENABLE MAINTENANCE MODE
  - path: ../../../apps/maintenance/patch-scale-zero.yaml
    target:
      kind: Deployment|StatefulSet
      name: .* # Target ALL resources in this app
```

### C. DaemonSets
DaemonSets cannot be scaled to 0. We disable them by adding a non-existent `nodeSelector`.
**File:** `kubernetes/apps/maintenance/patch-daemonset-disable.yaml`

```yaml
patches:
  - path: ../../../apps/maintenance/patch-daemonset-disable.yaml
    target:
      kind: DaemonSet
      name: .*
```

