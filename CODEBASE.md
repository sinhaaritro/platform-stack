# Codebase Map & Context

> **Note to AI Agents:** This file is your primary source of truth for navigating the repository structure.

## ⚠️ Critical Context: The Kubernetes Split

This repository is in transition. You must understand the difference between these two directories:

*   **`k8s/` (Legacy/Current):** 
    *   **Status:** Active but effectively "Legacy". 
    *   **Mechanism:** Plain Kustomize.
    *   **Usage:** The current documentation (`README.md`, `GETTING_STARTED.md`) directs users here.
    *   **Agent Protocol:** If the user asks for "k8s" or standard deployment, check here first, but warn about the transition if relevant.

*   **`kubernetes/` (Future/Modern):** 
    *   **Status:** Future standard (GitOps/App-of-Apps).
    *   **Mechanism:** ArgoCD/Flux directory structure (`apps/`, `clusters/`, `bootstrap/`).
    *   **Usage:** Intended for the advanced GitOps workflow.
    *   **Agent Protocol:** Prioritize this structure for any new "Platform Engineering" or "GitOps" related tasks.

---

## Repository Structure

### 1. Infrastructure (Constraint-based)
*   **`tofu/`**: Infrastructure as Code (OpenTofu).
    *   Defines *physical* and *virtual* resources (VMs, LXCs, DNS records).
    *   **Rule:** Output variables often feed into Ansible.

*   **`ansible/`**: Configuration Management.
    *   Configures the operating systems provisioned by Tofu.
    *   **Rule:** Idempotent playbooks. Secrets managed via Ansible Vault.

### 2. Orchestration (Application Layer)
*   **`kubernetes/`**: (See "The Kubernetes Split" above).
    *   **`clusters/`**: Cluster-specific overlays.
    *   **`apps/`**: Base manifests for applications.
    *   **`bootstrap/`**: Initial cluster setup components.

### 3. Project Management (The "Brain")
*   **`planning/`**: The source of truth for work-in-progress and future plans.
    *   **`ROADMAP.md`**: High-level milestones.
    *   **`BACKLOG.md`**: The "Dump" for ideas, technical debt, and issues found mid-task. **AI Agents:** Always check here before declaring a task "done" to ensure no related cleanup was missed.
    *   **`active/`**: Detailed specs for currently active feature work.
    *   **`done/`**: Archived tasks.

*   **`docs/adr/`**: Architecture Decision Records.
    *   **Rule:** When making a significant design choice (e.g., "Switching from Traefik to Nginx"), you MUST generate an ADR explaining *why*.

### 4. Agent & Automation
*   **`.agent/`**: AI Behaviors.
    *   **`GEMINI.md`**: The core ruleset.
    *   **`agents/`**: Persona definitions.
    *   **`skills/`**: Reusable capability toolboxes.

---

## "Code as Documentation" Principles for AI

1.  **Read First:** Before answering "How do I deploy X?", check `planning/` for existing decisions or strict guidelines.
2.  **Write Back:** If you find a bug during a task but cannot fix it immediately, **you are obligated** to add it to `planning/BACKLOG.md`.
3.  **Contextual Awareness:** Always determine if you are working in the "Legacy" (`k8s/`) or "Modern" (`kubernetes/`) context.
