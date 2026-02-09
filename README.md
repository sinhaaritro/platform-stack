# Homelab GitOps Repository

This repository contains the **complete**, **end-to-end infrastructure**, **configuration**, and **application code** for a multi-site homelab. The entire platform is managed using **GitOps principles**, where this repository serves as the **single source of truth** for the desired state of all environments, from bare-metal Proxmox nodes to cloud resources and Kubernetes applications.

## Documentation Hub

All high-level documentation for this project is located in the `/docs` directory. Before you begin, please familiarize yourself with the core principles of our setup.

*   **[ARCHITECTURE.md](./docs/ARCHITECTURE.md):** Understand the high-level design of our infrastructure.
*   **[GETTING_STARTED.md](./docs/GETTING_STARTED.md):** The complete guide for new developers to set up their environment and contribute.
*   **[NAMING_CONVENTION.md](./docs/NAMING_CONVENTION.md):** The single source of truth for naming all resources. **(Required reading)**
*   **[SECRETS.md](./docs/SECRETS.md):** Our policy for managing secrets with Ansible Vault. **(Required reading)**

## Core Philosophy

This platform is built on a "separation of concerns" principle, where each layer of the stack is managed by a dedicated tool. This creates a clear, maintainable, and scalable system.

*   **Infrastructure as Code (IaC):** The physical or virtual infrastructure is defined declaratively using **OpenTofu**.
*   **Configuration Management:** The state of our servers is managed procedurally using **Ansible**.
*   **Container Orchestration:** Production workloads are deployed and managed at scale using **Kubernetes**.
*   **Local Development Parity:** Developers can run a complete, multi-service application on their local machine using **Podman Compose**.

---

## Directory Structure

The repository is organized into distinct layers, each managed by a specific tool.

```
platform-stack/
├── Makefile           # Automates common project setup and operational tasks.
├── docs/              # High-level project documentation (architecture, conventions, etc.).
│   └── adr/           # Architecture Decision Records (The "Why").
├── planning/          # Layer 0: High-level roadmap and backlog (The "What").
├── scripts/           # Contains helper scripts for safety, automation, and CI/CD.
├── lxc-configs/       # Application-specific configuration files for standalone LXC containers.
├── tofu/              # Layer 1: Provisions the core infrastructure (VMs, networks, LXCs).
├── ansible/           # Layer 2: Configures provisioned resources (installs software, applies configs).
├── k8s/               # Layer 3: Deploys containerized applications to the Kubernetes cluster.
└── compose/           # Layer 4: Defines services for local development on a single machine.
```

---

## One-Time Environment Setup

> **[GO TO: GETTING STARTED GUIDE](./docs/GETTING_STARTED.md)**

All developers **must** follow the **[Getting Started](./docs/GETTING_STARTED.md)** guide to:
1.  Clone the repository.
2.  **Install Git Hooks** (Critical for security).
3.  Configure Ansible Vault secrets.
4.  Install required tools (OpenTofu, Ansible, Task).

---

## The Five Layers of the Platform

> **[GO TO: CODEBASE MAP](./CODEBASE.md)**

For a detailed breakdown of the repository structure and the purpose of each directory, please refer to **[CODEBASE.md](./CODEBASE.md)**.

*   **Layer 0:** Project Management (`planning/`)
*   **Layer 1:** Infrastructure Provisioning (`tofu/`)
*   **Layer 2:** Server Configuration (`ansible/`)
*   **Layer 3:** Production Orchestration (`k8s/` & `kubernetes/`)
*   **Layer 4:** Local Development (`compose/`)