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

## Repository Structure (The Stack)

This repository is organized into **Five Logical Layers**, plus automation and documentation.

### Layer 0: Project Management (`planning/` & `docs/adr/`)
*   **The Brain:** Where all work begins.
*   **`planning/ROADMAP.md`**: Strategic goals.
*   **`planning/BACKLOG.md`**: The tactical inbox for ideas, technical debt, and issues found mid-task. **AI Agents:** Always check here before declaring a task "done" to ensure no related cleanup was missed.
*   **`docs/adr/`**: Architecture Decision Records (The "Why").

### Layer 1: Infrastructure (`tofu/`)
*   **The Hardware:** Defines "Constraint-based" infrastructure (VMs, LXC containers, networking, DNS).
*   **Tool:** OpenTofu.
*   **Rule:** Output variables often feed into Ansible.

### Layer 2: Configuration (`ansible/`)
*   **The OS:** Configures the servers provisioned by Layer 1.
*   **Tool:** Ansible.
*   **Rule:** Idempotent playbooks. Secrets managed via Ansible Vault.

### Layer 3: Orchestration (`k8s/` & `kubernetes/`)
*   **The Platform:** Manages containerized workloads.
*   **`k8s/`**: Legacy Kustomize manifests (Current Active).
*   **`kubernetes/`**: Modern GitOps structure (`apps/`, `clusters/`, `bootstrap/`).

### Layer 4: Development (`compose/`)
*   **The Lab:** Local emulation of the stack.
*   **Tool:** Podman Compose.
*   **Rule:** Rapid feedback loop for developers. Mirrors production architecture but runs on a single machine.

### Automation & Intelligence (`.agent/`)
*   **The Team:** AI Agent definitions, skills, and behavior rules.
*   **`GEMINI.md`**: The master ruleset.

---

## "Code as Documentation" Principles for AI

1.  **Read First:** Before answering "How do I deploy X?", check `planning/` for existing decisions or strict guidelines.
2.  **Write Back:** If you find a bug during a task but cannot fix it immediately, **you are obligated** to add it to `planning/BACKLOG.md`.
3.  **Contextual Awareness:** Always determine if you are working in the "Legacy" (`k8s/`) or "Modern" (`kubernetes/`) context.
