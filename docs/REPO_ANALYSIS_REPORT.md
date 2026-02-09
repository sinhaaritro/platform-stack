 # Repository Analysis & Improvement Report

**Date:** 2026-02-09
**Target:** `platform-stack` Repository

## 1. Executive Summary

The `platform-stack` repository is a comprehensive GitOps-based solution for managing a hybrid homelab environment (Proxmox On-Prem + Cloud). It adheres to strict "Infrastructure as Code" (IaC) principles, utilizing **OpenTofu** for provisioning, **Ansible** for configuration, and **Kubernetes** for application orchestration.

**Current Status:** The repository is currently in a **transitional state**, specifically regarding its Kubernetes architecture. While the documentation points to a simple Kustomize-based workflow (`k8s/`), the codebase contains a more advanced, directory-based monorepo structure (`kubernetes/`) that is likely the future standard.

---

## 2. Directory Structure Analysis

### Root Level
The root structure is clean and logical, adhering to the "Separation of Concerns" philosophy defined in `README.md`.

| Directory | Purpose | Status |
| :--- | :--- | :--- |
| `tofu/` | Infrastructure Provisioning (Layer 1) | ✅ Well-defined |
| `ansible/` | configuration Management (Layer 2) | ✅ Well-defined |
| `k8s/` | **Legacy/Current** Kubernetes Manifests | ⚠️ **Conflict:** Documented as the source of truth, but overlaps with `kubernetes/`. |
| `kubernetes/` | **Future** Kubernetes GitOps Structure | ⚠️ **Undocumented:** Contains `apps`, `clusters`, `bootstrap` (ArgoCD/Flux pattern) but is not mentioned in docs. |
| `.agent/` | AI Agent Rules & Skills | ⚠️ **Minor Issue:** Main rule file is named `GIMINI.md` instead of `GEMINI.md`. |

### The "Kubernetes Split" (Critical Finding)
There are two competing directories for Kubernetes:
1.  **`k8s/`**: Contains a flat Kustomize structure. This is what `README.md` and `GETTING_STARTED.md` tell users to use.
2.  **`kubernetes/`**: Contains a structured "App of Apps" or generic GitOps folder structure (`apps/`, `clusters/`, `bootstrap/`). This appears to be the "Directory-Based Monorepo" pattern mentioned in recent development logs but is currently "invisible" in the documentation.

**Impact:** A new developer (or AI) following the documentation will effectively be working on the "old" stack (`k8s/`), potentially ignoring the "new" stack (`kubernetes/`) where future development is intended.

---

## 3. `.agent` Folder Health Check

The `.agent` folder is robust but has a few clean-up items:

*   **Rule File Typo:** The central rule file is named `GIMINI.md`. It should likely be renamed to `GEMINI.md` to match the "Gemini Kit" branding and standard naming conventions.
*   **Completeness:** The `agents/` and `skills/` directories are well-populated and align with the project's complex needs.
*   **Context Missing:** The agents might struggle to distinguish between `k8s/` and `kubernetes/` without explicit instructions in `CODEBASE.md` or updated docs.

---

## 4. Recommendations & Roadmap

To achieve the goal of "making it better for others (including AI) to understand and work," we recommend the following actions:

### Phase 1: Standardization (Immediate)
1.  **Rename `GIMINI.md` to `GEMINI.md`:** Fix the typo to ensure consistency.
2.  **Create `CODEBASE.md`:** Add a file in the root (or `docs/`) specifically for AI agents and new developers that maps the directory structure to the architectural intent. Explicitly explain the `k8s` vs `kubernetes` situation.
    *   *Example:* "⚠️ `k8s/` is legacy. Active development for GitOps is in `kubernetes/`."

### Phase 2: Documentation Upgrade
1.  **Update `README.md`:**
    *   Add a "Current Status" badge or note about the migration.
    *   Briefly explain the `kubernetes/` directory if it is ready for use.
2.  **Update `GETTING_STARTED.md`:**
    *   If `kubernetes/` is usable, add a section on "Advanced/GitOps Workflow" alongside the standard `k8s/` workflow.
3.  **Create `kubernetes/README.md`:**
    *   Explain the `apps`, `clusters`, `bootstrap` structure.
    *   Provide a "Mapping" table: "Old way (`k8s/app`) -> New way (`kubernetes/apps/app`)".

### Phase 3: Alignment (Long-term)
1.  **Migrate & Archive:** Move valid workloads from `k8s/` to `kubernetes/`.
2.  **Deprecate `k8s/`:** Once migration is confirmed, delete or archive `k8s/` to remove the source of confusion.

---

## 5. Proposed "Quick Win" Updates

We can immediately improve the "understanding" factor by adding a `docs/CODEBASE_MAP.md` (or updating `docs/ARCHITECTURE.md`) with the following map:

```markdown
# Codebase Map

## Primary Layers
- **Provisioning:** `tofu/` (OpenTofu)
- **Configuration:** `ansible/` (Ansible)
- **Orchestration:** `kubernetes/` (Main GitOps Repo)
  - `clusters/`: Cluster-specific configurations (overlays)
  - `apps/`: Base application manifests
  - `bootstrap/`: Cluster bootstrapping components

## Legacy / Transition
- **`k8s/`**: Previous generation Kustomize manifests. *Reference only.*
```
