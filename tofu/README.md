# Proxmox Infrastructure as Code with OpenTofu

This part of the repository contains the Infrastructure as Code (IaC) configuration for managing multiple Proxmox environments using OpenTofu. The workflow uses OpenTofu installed directly on a dedicated control machine.

The project is designed to be highly structured, reusable, and safe, incorporating best practices such as modular components, workspaces for environment separation, and guardrails to prevent accidental changes.

## Core Concepts

This project is built on a few key concepts:

*   **Native Tooling:** All `tofu` commands are run as native executables on the control machine. This simplifies the workflow and VSCodium integration.
*   **Modular & Reusable Components:** The logic for creating resources (like QEMU VMs and LXC containers) is encapsulated in self-contained modules within the `modules/` directory. The root configuration focuses on *what* to build, while the modules define *how* to build it.
*   **Workspaces:** Each Proxmox environment (`calm-belt`, `public`, etc.) is managed by a separate OpenTofu workspace. This creates an independent state file for each environment, providing strong isolation.
*   **Declarative Data:** The infrastructure for each environment is defined in `.tfvars` files within the `tofu/environments/` directory. The core logic is generic and simply consumes this data.
*   **Workspace Guardrail:** A safety check in `checks.tf` prevents you from running a `plan` or `apply` if your current workspace does not match the environment defined in your `.tfvars` file, preventing catastrophic mistakes.
*   **Secure Secret Management:** Plain-text secrets (like API keys and passwords) must never be committed to Git. We use **Ansible Vault** to encrypt our secrets. For each environment, we maintain two variable files:
    *   `environments/<env>.tfvars`: Contains non-secret configuration (VM names, sizes, etc.). This file is committed to Git.
    *   `environments/<env>.secrets.tfvars`: Contains all sensitive data. This file is encrypted with Ansible Vault before being committed to Git.
    *   During `plan` and `apply`, we use a shell feature called **Process Substitution** (`<(...)`) to decrypt the secrets file in-memory and pass it to OpenTofu, ensuring no secrets are ever written to disk in plain text.

## Prerequisites

Before you begin, ensure you have the following:

1.  **A Control Machine:** A Linux VM (like `hiking-bear`) where you will run commands.
2.  **OpenTofu:** Installed directly on the control machine. Follow the `System Setup.md` guide for detailed installation instructions.
3.  **Ansible:** Required for the `ansible-vault` tool to manage encrypted secrets.
4.  **Git:** Installed and configured with your user information.
5.  **SSH Access:** Your SSH public key must be authorized for GitHub to clone this private repository.
6.  **Proxmox API User:** A dedicated user (e.g., `vmprovisioner@pve`) must be created in each Proxmox environment with the necessary permissions.
7.  **VSCodium (Recommended):** The [Remote - SSH](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-ssh) extension is recommended for editing files on the control machine.

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
    │   ├── calm-belt.secrets.tfvars  # Encrypted secrets for Calm Belt
    │   ├── admin.tfvars
    │   ├── admin.secrets.tfvars      # Encrypted secrets for Admin
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
    git clone git@github.com:sinhaaritro/platform-stack.git
    cd platform-stack/
    ```

2.  **Go to the tofu folder**
    ```bash
    # Move into the working directory
    cd tofu/
    ```

3.  **Create Workspaces**
    You need to create a workspace for each environment you intend to manage.
    ```bash
    # Create the workspace for your sandbox environment
    tofu workspace new calm-belt

    # Create workspaces for your other environments
    tofu workspace new grand-line  # Example for 'internal'
    tofu workspace new new-world    # Example for 'public'
    tofu workspace new red-line     # Example for 'admin'
    ```
    **Note:** You must re-run `tofu init` any time you add a new module or change provider versions.

### Phase 1.5: Creating and Managing Secrets

For each environment, you must create an encrypted file to hold its secrets.

1.  **Create an Encrypted Secrets File**
    Use `ansible-vault create` to make a new, encrypted `.tfvars` file. You will be prompted to set a vault password.
    ```bash
    # Example for the 'calm-belt' environment
    ansible-vault create environments/calm-belt.secrets.tfvars
    ```
    When the editor opens, add your secret variables **in HCL format**. For example:
    ```hcl
    # environments/calm-belt.secrets.tfvars (decrypted view)

    proxmox_connection = {
      password_auth = {
        user     = "vmprovisioner@pve"
        password = "vmprovisioner"
      }
    }

    user_credentials = {
      password        = "devdevdev"
      ssh_public_keys = ["ssh-ed25519 AAA..."]
    }
    ```

2.  **Viewing and Editing Secrets (Day-to-Day)**
    You will use these commands to manage your secrets without ever decrypting them to disk.
    ```bash
    # To view the decrypted content in your terminal
    ansible-vault view environments/calm-belt.secrets.tfvars

    # To securely edit the file in your default editor (e.g., nano, vim)
    ansible-vault edit environments/calm-belt.secrets.tfvars
    ```

3.  **Encrypting and Decrypting (Manual Operations)**
    These commands are for manually encrypting a plain-text file or decrypting a vault file. **Use with caution.**
    ```bash
    # To encrypt an existing plain-text file
    ansible-vault encrypt environments/some_plain_file.tfvars

    # To decrypt a vault file to plain-text (avoid this if possible)
    ansible-vault decrypt environments/calm-belt.secrets.tfvars
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

3.  **Navigate to the OpenTofu Directory**
    ```bash
    cd tofu/
    ```

4.  **Select Your Target Workspace**
    This is a critical step. Tell OpenTofu which environment's state file to use.
    ```bash
    tofu workspace select calm-belt
    ```

5.  **Enable the Proxmox User (Manual Step)**
    As per our security model, log in to the Proxmox UI for the `calm-belt` environment and **enable** the `vmprovisioner@pve` user.

6.  **Initialize OpenTofu (If Needed)**
    You only need to do this once per workspace, or if you change provider versions.
    ```bash
    tofu init
    ```

7.  **Plan Your Changes (The Dry Run)**
    This command now uses **two `-var-file` flags**. The first points to your standard variables file. The second uses Process Substitution (`<(...)`) to securely decrypt and pass your secrets file.
    ```bash
    # You will be prompted for your Ansible Vault password here
    tofu plan \
      -var-file="environments/calm-belt.tfvars" \
      -var-file=<(ansible-vault view --vault-password-file <(echo "$ANSIBLE_VAULT_PASSWORD") environments/calm-belt.secret.tfvars)
    ```
    Review the output carefully. The Workspace Guardrail will still protect you from cross-environment mistakes.

8.  **Apply Your Changes (The Execution)**
    If the plan looks correct, apply it using the same command structure. You will be prompted for your vault password again.
    ```bash
    # For interactive approval (typing 'yes')
    tofu apply \
      -var-file="environments/calm-belt.tfvars" \
      -var-file=<(ansible-vault view --vault-password-file <(echo "$ANSIBLE_VAULT_PASSWORD") environments/calm-belt.secret.tfvars)

    # To approve it directly
    tofu apply \
      -var-file="environments/calm-belt.tfvars" \
      -var-file=<(ansible-vault view --vault-password-file <(echo "$ANSIBLE_VAULT_PASSWORD") environments/calm-belt.secret.tfvars) \
      --auto-approve
    ```
    After completion, the outputs defined in `outputs.tf` will be displayed.

9.  **Disable the Proxmox User (Manual Step)**
    For security, go back to the Proxmox UI and **disable** the `vmprovisioner@pve` user.

10. **Commit Your Changes**
    The `apply` command created or updated a file named `terraform.tfstate.d/calm-belt/terraform.tfstate`. This file is the record of your infrastructure and **must be committed**.
    ```bash
    cd .. # Back to the root of platform-stack/
    git add .
    git commit -m "feat(feature): message"
    git push
    ```