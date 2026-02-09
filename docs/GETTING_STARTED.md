
# Getting Started for Developers

Welcome to the Homelab GitOps project! This guide provides all the necessary steps to set up your local development environment so you can begin contributing.

The goal of this guide is to configure your machine to **interact with and manage** the homelab infrastructure, not to replicate the entire infrastructure locally. For local application development, please see the documentation in the `/compose` directory.

## Table of Contents

1.  [Prerequisites: Tool Installation](#1-prerequisites-tool-installation)
2.  [Step 1: Initial Repository Setup](#2-step-1-initial-repository-setup)
3.  [Step 2: Configuring Secrets Management](#3-step-2-configuring-secrets-management)
4.  [Step 3: The Core Development Workflow](#4-step-3-the-core-development-workflow)
5.  [Step 4: Using Taskfile for Common Commands](#5-step-4-using-taskfile-for-common-commands)

---

## 1. Prerequisites: Tool Installation

Before you begin, you must install the following tools on your local machine. Please follow the official installation instructions for each one.

#### Core Tools
-   **[Git](https://git-scm.com/book/en/v2/Getting-Started-Installing-Git):** For version control.
-   **[make](https://www.gnu.org/software/make/):** Used to automate the installation of critical project configurations.
-   **[Task](https://taskfile.dev/installation/):** The command runner for this project, used to simplify complex commands.

#### Infrastructure & Configuration Tools
-   **[OpenTofu](https://opentofu.org/docs/intro/install/):** For provisioning infrastructure (Layer 1).
-   **[Ansible](https://docs.ansible.com/ansible/latest/installation_guide/intro_installation.html):** For configuring servers and managing secrets (Layer 2).
-   **[kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl/):** The command-line tool for interacting with the Kubernetes cluster (Layer 3).

#### Local Development Tools
-   **[Podman](https://podman.io/getting-started/installation) & [Podman Compose](https://github.com/containers/podman-compose#installation):** For running local development environments (Layer 4). (Docker and Docker Compose are also compatible).

---

## 2. Step 1: Initial Repository Setup

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

## 3. Step 2: Configuring Secrets Management

This project uses **Ansible Vault** to encrypt all sensitive data (passwords, API keys, IP addresses, etc.). Our automation scripts, particularly for OpenTofu, are designed to pull the vault password from an environment variable for seamless, non-interactive execution.

#### 3.1. Obtain the Vault Password

The vault password is a shared secret and must be obtained securely from an existing project administrator. **It will never be written down in plain text or committed to this repository.**

#### 3.2. Set the `ANSIBLE_VAULT_PASSWORD` Environment Variable

You must export the vault password into an environment variable named `ANSIBLE_VAULT_PASSWORD`.

The most reliable way to ensure this variable is always available is to add it to your shell's profile file.

1.  Open your shell's profile file (e.g., `~/.bashrc`, `~/.zshrc`, or `~/.profile`):
    ```sh
    nano ~/.bashrc
    ```

2.  Add the following line to the end of the file, replacing the placeholder with the actual password you received:
    ```sh
    export ANSIBLE_VAULT_PASSWORD="your-secret-password-here"
    ```
    **Security Note:** Your shell profile file is now a sensitive file. Ensure its permissions are secure and it is never committed to any repository.

3.  Reload your shell for the change to take effect, or open a new terminal window.
    ```sh
    source ~/.bashrc
    ```

#### 3.3. Verify Your Setup

You can verify that your environment is correctly configured by attempting to view an encrypted file. If the setup is correct, the command will succeed without prompting you for a password.

1.  Navigate to the Ansible directory:
    ```sh
    cd ansible/
    ```

2.  Run the `ansible-vault view` command on a known encrypted file:
    ```sh
    # Replace 'group_vars/all/vault.yml' with any encrypted file if needed
    ansible-vault view group_vars/all/vault.yml
    ```
    If you see the decrypted contents of the file printed to your screen, your setup is successful. If you are prompted for a password, the environment variable was not set or exported correctly.

#### 3.4. How This Variable is Used

Setting this environment variable is critical because it allows our Taskfile and helper scripts to run complex commands without interactively prompting you for a password. For example, a command to plan infrastructure changes securely passes the decrypted secrets to OpenTofu like this:

```bash
# This command only works if $ANSIBLE_VAULT_PASSWORD is set correctly
tofu plan \
  -var-file="environments/some-env.tfvars" \
  -var-file=<(ansible-vault view --vault-password-file <(echo "$ANSIBLE_VAULT_PASSWORD") environments/some-env.secrets.tfvars)
  ```

---

## 4. Step 3: The Core Development Workflow

All changes to the infrastructure and applications must be made through Git.

1.  **Create a Branch:** Always create a new feature branch for your changes from the `main` branch.
    ```sh
    git checkout main
    git pull origin main
    git checkout -b feat/my-new-feature
    ```

2.  **Check the Roadmap & Backlog:** Before starting, check `planning/ROADMAP.md` and `planning/BACKLOG.md` to see if your task is listed or if there are related bugs/notes to consider.

3.  **Make Your Changes:** The directory you work in depends on what you are changing:
    -   **To provision a new VM or change its resources:** Edit files in `/tofu/`.
    -   **To install software on a VM or change its configuration:** Edit files in `/ansible/`.
    -   **To deploy or update a Kubernetes application:** Edit files in `/k8s/` or `/kubernetes/`.
    -   **To work on a local development environment:** Edit files in `/compose/`.

4.  **Log Off-Topic Discoveries:** If you find a bug or think of an improvement that is *out of scope* for your current task, do not fix it immediately. Add it to `planning/BACKLOG.md` for later.

5.  **Document Decisions:** If your changes involve a significant architectural choice, create an ADR in `docs/adr/` using the template provided.

6.  **Commit and Push:** Commit your changes with a descriptive message that follows the [Conventional Commits](https://www.conventionalcommits.org/) standard.
    ```sh
    git add .
    git commit -m "feat: add new monitoring dashboard for proxmox"
    git push origin feat/my-new-feature
    ```

4.  **Create a Pull Request:** Open a Pull Request on GitHub for your branch to be reviewed and merged.

---

## 5. Step 4: Using Taskfile for Common Commands

This project uses **Taskfile** as a simple and consistent way to run common commands. It acts as a command runner, providing shortcuts for complex or frequently used `tofu`, `ansible`, or `kubectl` commands.

-   **To see all available commands,** run the following from the root of the repository:
    ```sh
    task --list
    ```

-   **To run a specific task,** use `task <task-name>`.

#### Examples:

-   To validate and format all OpenTofu code:
    ```sh
    task tofu:fmt
    ```

-   To see the planned infrastructure changes in OpenTofu:
    ```sh
    task tofu:plan
    ```

-   To run an Ansible playbook to configure all Kubernetes nodes:
    ```sh
    task ansible:playbook -- playbooks/configure-k8s-nodes.yml
    ```

Always check the `Taskfile.yml` in the root directory to see what commands are available and what they do.

---
