# Proxmox Infrastructure as Code with OpenTofu

This part of the repository contains the Infrastructure as Code (IaC) configuration for managing multiple Proxmox environments using OpenTofu. The entire workflow is containerized with Podman to ensure a consistent and clean execution environment.

The project is designed to be highly structured, reusable, and safe, incorporating best practices such as workspaces for environment separation and guardrails to prevent accidental changes.

## Core Concepts

This project is built on a few key concepts:

*   **Containerized Tooling:** All `tofu` commands are run from within a Podman container defined in `compose.yaml`. This means you do not need to install OpenTofu on your control machine, only Podman and `podman-compose`.
*   **Workspaces:** Each Proxmox environment (`internal`, `public`, etc.) is managed by a separate OpenTofu workspace. This creates an independent state file for each environment, providing strong isolation.
*   **Declarative Data:** The infrastructure for each environment is defined in `.tfvars` files within the `tofu/environments/` directory. The core logic in `main.tf` is generic and simply reads this data.
*   **Workspace Guardrail:** A safety check in `checks.tf` prevents you from running a `plan` or `apply` if your current workspace does not match the environment defined in your `.tfvars` file, preventing catastrophic mistakes.

## Prerequisites

Before you begin, ensure you have the following:

1.  **A Control Machine:** A Linux VM or machine where you will run commands. This can be a central "Control VM" or a dedicated one within each environment.
2.  **Podman & Podman-Compose:** Installed on the control machine.
3.  **Git:** Installed and configured with your user information.
4.  **SSH Access:** Your SSH public key must be authorized for GitHub to clone this private repository.
5.  **Proxmox API User:** A dedicated user (e.g., `vmprovisioner@pve`) must be created in each Proxmox environment with the necessary permissions. This project uses a security model where this user is normally disabled.
6.  **VSCodium (Recommended):** The [Remote - SSH](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-ssh) extension is recommended for editing files on the control machine.

## Directory Structure

The key files and directories for this part of the project are located within the `tofu/` folder.

```
platform-stack/
├── .build/
│   └── tofu/
│       └── Containerfile    # Blueprint for our OpenTofu container image
├── compose.yaml             # Defines the OpenTofu service for Podman
└── tofu/                      # Your primary working directory
    ├── main.tf              # Core logic for creating QEMU VMs and LXC Containers
    ├── provider.tf          # Proxmox provider configuration
    ├── variables.tf         # DECLARATIONS of all possible input variables
    ├── outputs.tf           # Defines what to output after a successful apply
    ├── checks.tf            # Contains the Workspace Guardrail safety check
    │
    ├── environments/          # Contains the DATA for each environment
    │   ├── calm-belt.tfvars
    │   ├── admin.tfvars
    │   └── ...
    │
    └── modules/               # Contains reusable infrastructure components
        ├── proxmox_qemu_vm/   # Module for creating QEMU VMs
        │   ├── main.tf
        │   ├── variables.tf
        │   ├── outputs.tf
        │   └── providers.tf
        │
        └── proxmox_lxc_container/ # Module for creating LXC containers
            └── ...

```

---

## Step-by-Step Workflow

Follow these steps to deploy and manage your infrastructure. All commands should be run from the `platform-stack/tofu/` directory on your control machine.

### Phase 1: Initial Setup (One-Time Only)

You only need to perform these steps once when you first clone the repository to a new control machine.

1.  **Clone the Repository**
    ```bash
    git clone git@github.com:your-username/platform-stack.git
    cd platform-stack/
    ```

2.  **Build the Podman Image**
    This command reads the `Containerfile` and `compose.yaml` to build the local container image that holds OpenTofu.
    ```bash
    podman-compose build
    ```

3.  **Create Workspaces**
    You need to create a workspace for each environment you intend to manage.
    ```bash
    # Move into the working directory
    cd tofu/

    # Create the workspace for your sandbox environment
    tofu workspace new calm-belt

    # Create workspaces for your other environments
    tofu workspace new grand-line  # Example for 'internal'
    tofu workspace new new-world    # Example for 'public'
    tofu workspace new red-line     # Example for 'admin'
    ```

### Phase 2: Day-to-Day Operations

This is the standard loop you will follow every time you want to deploy, update, or destroy resources in an environment. We will use the `calm-belt` environment as our example.

1.  **Connect to Your Control Machine**
    Ensure you connect with SSH Agent Forwarding enabled if you need to perform `git` operations.
    ```powershell
    # From your Windows PC
    ssh -A your_user@<control_vm_ip>
    ```

2.  **Navigate and Pull Latest Changes**
    ```bash
    cd ~/platform-stack/
    git pull
    ```

3.  **Start the Container Service**
    This starts the `tofu` service in the background.
    ```bash
    podman-compose up -d
    ```

4.  **Select Your Target Workspace**
    This is a critical step. Tell OpenTofu which environment you want to work on.
    ```bash
    # Move into the working directory
    cd tofu/

    podman-compose exec tofu tofu workspace select calm-belt
    ```

5.  **Enable the Proxmox User (Manual Step)**
    As per our security model, log in to the Proxmox UI for the `calm-belt` environment and **enable** the `vmprovisioner@pve` user.

6.  **Initialize OpenTofu (If Needed)**
    You only need to do this once per workspace, or if you change provider versions.
    ```bash
    podman-compose exec tofu tofu init
    ```

7.  **Plan Your Changes (The Dry Run)**
    This is the most important command. It shows you exactly what OpenTofu will do without making any changes. The `-var-file` flag is **mandatory**.
    ```bash
    podman-compose exec tofu tofu plan -var-file="environments/calm-belt.tfvars"
    ```
    Review the output carefully. The Workspace Guardrail in `checks.tf` will run here and stop the plan if your workspace doesn't match the file.

8.  **Apply Your Changes (The Execution)**
    If the plan looks correct, apply it. You will be prompted to type `yes`.
    ```bash
    podman-compose exec tofu tofu apply -var-file="environments/calm-belt.tfvars"
    ```
    Or, directly approve it
    ```bash
    podman-compose exec tofu tofu apply -var-file="environments/calm-belt.tfvars" --auto-approve
    ```
    After completion, the outputs defined in `outputs.tf` will be displayed.

9.  **Disable the Proxmox User (Manual Step)**
    For security, go back to the Proxmox UI and **disable** the `vmprovisioner@pve` user.

10. **Stop the Container Service**
    When you are finished, shut down the container environment to free up resources.
    ```bash
    # Make sure you are in the platform-stack/ directory
    podman-compose down
    ```

11. **Commit Your Changes**
    The `apply` command created or updated a file named `terraform.tfstate.d/calm-belt/terraform.tfstate`. This file is the record of your infrastructure and **must be committed**.
    ```bash
    cd .. # Back to the root of platform-stack/
    git add .
    git commit -m "feat(feature): message"
    git push
    ```