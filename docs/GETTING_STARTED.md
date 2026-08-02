# Getting Started for Developers

Welcome to the Homelab GitOps project! This guide provides all the necessary steps to set up your local development environment so you can begin contributing.

The goal of this guide is to configure your machine to **interact with and manage** the homelab infrastructure, not to replicate the entire infrastructure locally. For local application development, please see the documentation in the `/compose` directory.

## 1. Prerequisites: Tool Installation

All required tools can be installed automatically by running:

```sh
task env:init
```

This installs and verifies: `tofu`, `kubectl`, `helm`, `kubeseal`, `ansible`, and Python dependencies.

> **Note:** This assumes `git`, `curl`, `make`, and `Task` are already installed on your system.

---

## 2. Initial Repository Setup

1.  **Clone the Repository**
    ```sh
    git clone <your-repository-url>
    cd platform-stack/
    ```

2.  **Install Project Hooks (CRITICAL)**
    This project uses Git hooks to enforce security policies, such as preventing unencrypted secrets from being committed. The `Makefile` at the root of the project automates the installation of these hooks.

    **This step is not optional.** It is a critical safeguard for the repository.

    Run the following command from the root of the repository:
    ```sh
    make install-hooks
    ```
    This command sets up a pre-commit hook that will now run automatically before every `git commit` command.

---

## 3. Core Development Workflow

All changes to the infrastructure and applications must be made through Git.

1.  **Create a Branch:** Always create a new feature branch for your changes from the `main` branch.
    ```sh
    git checkout main
    git pull origin main
    git checkout -b feat/my-new-feature
    ```

2.  **Check the Roadmap & Backlog:** Before starting, check `planning/ROADMAP.md` and `planning/BACKLOG.md` to see if your task is listed or if there are related bugs/notes to consider.

3.  **Make Your Changes:** See the directory mapping in **[README.md](../README.md)** to find which directory to edit for what you're changing.

4.  **Commit and Push:** Commit your changes with a descriptive message that follows the [Conventional Commits](https://www.conventionalcommits.org/) standard.
    ```sh
    git add .
    git commit -m "feat: add new monitoring dashboard for proxmox"
    git push origin feat/my-new-feature
    ```

5.  **Create a Pull Request:** Open a Pull Request on GitHub for your branch to be reviewed and merged.

---

## Next Steps

- Study the [System Overview](./ARCHITECTURE.md#system-overview) diagram
- Read [App Pattern 01: Directory Structure](./app_pattern/01-directory-structure.md) for layout conventions
- Check [ROADMAP.md](../planning/ROADMAP.md) for what to work on next
