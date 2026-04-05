# Kubernetes Management Skill

---
name: kubernetes-management
description: Comprehensive workflow for Kubernetes App Lifecycle Management. Use for creating, updating, deleting (safe shutdown), and debugging applications. Enforces the Base+Patches+Overlays pattern.
allowed-tools: Read, Write, List, Grep, Run
---

# Kubernetes Management Skill

> This skill standardizes how we manage applications in the `platform-stack` repository.
> It provides compact agent workflows. For full explanations, see the **Documentation** section below.

## Documentation (Authoritative Source)

Before executing any workflow, **read the relevant doc** for context:

| Doc | When to Read |
|---|---|
| [Directory Structure](../../../docs/app_pattern/01-directory-structure.md) | Understanding where files belong |
| [Base + Patches + Overlays](../../../docs/app_pattern/02-base-patches-overlays.md) | Understanding the composition model |
| [Application Lifecycle](../../../docs/app_pattern/03-application-lifecycle.md) | Creating, shutting down, or managing storage |
| [Debugging Guide](../../../docs/app_pattern/04-debugging-guide.md) | Fixing a broken application |
| [Validation & Tooling](../../../docs/app_pattern/05-validation-and-tooling.md) | Running structure checks |
| [Secrets Management](../../../docs/secrets/) | Any work involving secrets or SealedSecrets |

## Templates

Use these when generating new files:
*   `templates/kustomization-base.yaml` — Base Helm chart definition
*   `templates/kustomization-overlay.yaml` — Overlay profile
*   `templates/kustomization-cluster.yaml` — Cluster implementation

## 1. Creating a New Application

> **Full details:** [Application Lifecycle](../../../docs/app_pattern/03-application-lifecycle.md)

1.  **Define Base:** Create `apps/services/[app]/base/kustomization.yaml` using `templates/kustomization-base.yaml`. Create `values.yaml`.
2.  **Create Components:** Create `apps/services/[app]/components/[name]/kustomization.yaml`.
    *   Types: `secrets`, `s3-config`, `replicas-1`, `storage-longhorn`, `maintenance`.
    *   For secrets → **MUST load `@[skills/secrets-management]`**.
3.  **Create Overlays:** Create `apps/services/[app]/overlays/[profile]/kustomization.yaml` using `templates/kustomization-overlay.yaml`. Compose with patches.
4.  **Implement in Cluster:** Create `clusters/[cluster]/[app]/kustomization.yaml` using `templates/kustomization-cluster.yaml`. Add local patches.
5.  **Register in ArgoCD:**
    *   Edit `appset-core.yaml` (infra, all clusters) or `appset-apps-[cluster].yaml` (workloads, one cluster).
    *   Add to `generators.list.elements`:
    ```yaml
    - app: [app-name]
      namespace: [ns]
      serverSideApply: "true"
      replace: "false"
    ```

## 2. Safe Shutdown (Deletion)

> **Full details:** [Application Lifecycle § Safe Shutdown](../../../docs/app_pattern/03-application-lifecycle.md#2-safe-shutdown-deletion)

1.  **Target:** `clusters/[cluster]/[app]/kustomization.yaml`.
2.  **Action:** Change resource from `overlays/prod` → `overlays/maintenance`.
3.  **Result:** Pods scale to 0. PVCs remain bound.
4.  **Verify:** `kubectl get pods -n [app]` (should be 0).

> **WARNING:** Never delete the ArgoCD Application directly if you want to keep data.

## 3. Managing StatefulSet Storage (PVCs)

> **Full details:** [Application Lifecycle § Storage](../../../docs/app_pattern/03-application-lifecycle.md#3-managing-statefulset-storage-pvcs)

1.  **Do NOT** modify `volumeClaimTemplates` in `base/values.yaml`.
2.  **Instead:** Create a Kustomize patch at `apps/services/[app]/components/storage-[type]/patch-storage.yaml`.
3.  **Benefit:** Different clusters can use different storage backends.

## 4. Debugging & Fixing

> **Full details:** [Debugging Guide](../../../docs/app_pattern/04-debugging-guide.md)

### Decision Tree
*   **Global Issue** (buggy config, wrong image) → Fix in `apps/services/[app]/base/` or `patches/`. Affects ALL clusters.
*   **Local Issue** (ingress host, quota) → Fix in `clusters/[cluster]/[app]/`. Affects ONLY this cluster.

### Chart Inflation
```sh
python .agent/skills/kubernetes-management/scripts/inflate_chart.py [path_to_kustomization]
```
Inspect `debug_full.yaml`. **DELETE before committing.**

## 5. Verification

> **Full details:** [Validation & Tooling](../../../docs/app_pattern/05-validation-and-tooling.md)

Always run after creating/moving files:
```sh
python .agent/skills/kubernetes-management/scripts/validate_structure.py .
```
