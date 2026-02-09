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

Before working with any of the layers, every developer **must** perform this one-time setup after cloning the repository. This ensures that the development environment is consistent and that critical safety checks are active.

1.  **Clone the Repository**
    ```sh
    git clone <your-repository-url>
    cd platform-stack/
    ```

2.  **Install Project Hooks (CRITICAL)**
    This project uses Git hooks to enforce security policies, such as preventing unencrypted secrets from being committed. The `Makefile` at the root of the project automates the installation of these hooks.

    **Prerequisite:** Ensure you have `make` installed.

    Run the following command from the root of the repository:
    ```sh
    make install-hooks
    ```
    This command sets up a pre-commit hook that will now run automatically before every commit, safeguarding the repository.

3.  **Continue with the Full Setup**
    For the complete developer setup, workflow, and tool installation, please follow the **[GETTING_STARTED.md](./docs/GETTING_STARTED.md)** guide.

---

## The Five Layers of the Platform

Each directory below contains its own `README.md` file with detailed instructions for that specific layer.

### Layer 0: Project Management & Decisions
*   **Purpose:** To track the long-term roadmap, manage the backlog of ideas/bugs, and document architectural decisions.
*   **Location:** `planning/` and `docs/adr/`
*   **Documentation:** AI agents are required to check these before and after every task.

### Layer 1: Infrastructure Provisioning with OpenTofu
*   **Purpose:** To create the raw infrastructure (VMs, LXCs, networks) declaratively.
*   **Location:** `tofu/`
*   **Documentation:** For detailed usage, see the **[Tofu README](./tofu/README.md)**.

### Layer 2: Server Configuration with Ansible
*   **Purpose:** To take the raw servers from OpenTofu and configure them into a consistent, ready-to-use state.
*   **Location:** `ansible/`
*   **Documentation:** For detailed usage, see the **[Ansible README](./ansible/README.md)**.

### Layer 3: Production Orchestration with Kubernetes
*   **Purpose:** To deploy, manage, and scale our containerized applications in a resilient, production-grade environment.
*   **Location:** `k8s/`
*   **Documentation:** For detailed usage, see the **[Kubernetes README](./k8s/README.md)**.

### Layer 4: Local Development & Testing with Compose
*   **Purpose:** To provide developers with a fast, isolated, and easy-to-use environment on their local machine that mirrors the production architecture.
*   **Location:** `compose/`
*   **Documentation:** For detailed usage, see the **[Compose README](./compose/README.md)**.