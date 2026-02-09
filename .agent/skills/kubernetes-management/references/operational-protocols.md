# Operational Protocols

> **Source of Truth:** Global operational protocols for the Kubernetes platform.

## 1. The "Hub-and-Spoke" Topology

*   **Hub (Management Cluster):** The cluster running ArgoCD (e.g., `CLS1`). It manages itself and other clusters.
*   **Spoke (Target Cluster):** A cluster registered to the Hub. It does not run its own ArgoCD control plane.
*   **Bootstrapping:** All ApplicationSets live in `kubernetes/bootstrap/[HUB]/`. Target clusters do *not* have their own bootstrap folder.

## 2. The Matrix Generator Pattern (Core Apps)

To manage core infrastructure (like `cert-manager`, `monitoring`) across **ALL** clusters efficiently, we use the **Matrix Generator**.

1.  **Generator 1 (Clusters):** Automatically discovers all clusters registered in ArgoCD.
2.  **Generator 2 (List):** Defines the list of core applications to deploy.

### Critical Rule: The Exclusion Principle
If adding an app to *all* clusters via `appset-core.yaml`:
1.  Add it to the Matrix Generator list in `appset-core.yaml`.
2.  **EXCLUDE** it from individual cluster ApplicationSets (`appset-apps-[CLUSTER].yaml`) if it was previously defined there, to avoid duplicate management conflicts.

## 3. Tenant Apps (Cluster Specific)

Tenant-specific apps are managed by a **Git Generator** in `appset-apps-[CLUSTER].yaml`. This generator looks for directories inside `kubernetes/clusters/[CLUSTER]/*`.

**Protocol using `kubernetes-management`:**
1.  **Create:** Use the `Creating a New Application` workflow in `SKILL.md`.
2.  **Result:** Work is done in `clusters/[CLUSTER]/[APP]`.
3.  **Deploy:** ArgoCD Git Generator automatically detects the new folder and deploys it.

## 4. Operational Troubleshooting

**Rule:** Never assume `kubectl` works locally against the target cluster. Use Ansible tunneling via `task -d ansible k8s:cmd`.

> **See `SKILL.md` -> "Debugging & Fixing" for the full step-by-step workflow.**
