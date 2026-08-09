# Proxmox VE API User & Token Setup Guide

This guide describes how to configure an API user and token in Proxmox VE (PVE) to allow OpenTofu to automate the provisioning of VMs and containers, and how to integrate it with the `platform-stack` infrastructure.

---

## 1. Prerequisites

You must have:
- An active Proxmox VE (PVE) node or cluster running.
- Access to the Proxmox Web UI with administrative privileges (e.g. logging in as `root@pam`).

---

## 2. API User & Token Creation

To follow best security practices, do not run automation scripts using the root PAM credentials directly. Instead, create a dedicated automation user and API token.

### 2.1. Create a Dedicated User
1. Log in to the Proxmox VE Web UI.
2. Select **Datacenter** from the left-side resource tree.
3. Under the **Permissions** section, click **Users**.
4. Click **Add**.
5. Configure the user details:
   - **User name**: `tofu-prov`
   - **Realm**: Select **pve** (Proxmox VE authentication realm).
   - **Password**: Enter a secure password (used primarily during user setup, though we will authenticate via token).
   - Click **Add**.

### 2.2. Assign Administrative Permissions
The automation user needs rights to create, delete, and configure VMs, storage, and networking on the cluster.
1. Still under **Datacenter**, click **Permissions** (directly under Users).
2. Click **Add** -> **User Permission**.
3. Configure the permission rule:
   - **Path**: Enter `/` (this grants permissions across the entire cluster).
   - **User**: Select `tofu-prov@pve`.
   - **Role**: Select **Administrator** (or a custom role with appropriate VM, storage, and SDN privileges).
   - **Propagate**: Ensure the checkbox is **checked** (so sub-paths like storage and nodes inherit these permissions).
4. Click **Add**.

### 2.3. Generate API Token
1. Under **Datacenter**, click **API Tokens**.
2. Click **Add**.
3. Configure the token settings:
   - **User**: Select `tofu-prov@pve`.
   - **Token ID**: Enter `tofu-token` (or a descriptive label).
   - **Privilege Separation**: **Uncheck** this box. *(If checked, you must assign permissions to the token itself. By unchecking it, the token automatically inherits all the permissions of the `tofu-prov@pve` user).*
4. Click **Add**.
5. **CRITICAL:** Copy the **Token ID** (formatted as `tofu-prov@pve!tofu-token`) and the **Secret** value. *The secret value is shown only once and will be hidden forever once you close the window.*

---

## 3. Required Permissions

OpenTofu coordinates PVE templates, clone procedures, CPU/RAM configuration, disk resizing, and VLAN setups.

> [!WARNING]
> If you choose to enable **Privilege Separation** on the API token, you must explicitly assign permissions directly to the token ID (e.g., `tofu-prov@pve!tofu-token`) under **Datacenter -> Permissions**. The token will need rights like:
> - `VM.Allocate`, `VM.Config.Disk`, `VM.Config.Network`, `VM.Config.HWType`, `VM.Config.Options`, `VM.PowerMgmt`
> - `Datastore.AllocateSpace`, `Datastore.Audit`
> - `SDN.Use` (if using Software Defined Networking VNets)
>
> Using a token with **Privilege Separation disabled** that inherits the **Administrator** role at `/` is the most reliable way to avoid API errors during infrastructure changes. Ensure the token secret is treated as a highly sensitive key.

---

## 4. Secrets Integration

The credentials generated in Step 2 must be written directly into the stack's encrypted secrets variable file:
`tofu/stacks/onprem/proxmox_atlas/schema.secret.tfvars`.

### Configuration Variables
The OpenTofu stack expects the connection endpoint and authentication details in the `proxmox_connection` object:

| Variable Path | Type | Description |
|---|---|---|
| `proxmox_connection.url` | String | The Proxmox API Endpoint URL (e.g., `https://192.168.1.10:8006/api2/json`) |
| `proxmox_connection.insecure_tls` | Boolean | Allow insecure SSL connections (set to `true` if utilizing self-signed certs) |
| `proxmox_connection.auth_method` | String | Authentication method, set to `"token"` |
| `proxmox_connection.token_auth.id` | String | The API Token ID (e.g., `tofu-prov@pve!tofu-token`) |
| `proxmox_connection.token_auth.secret` | String | The API Token Secret key |

### Step-by-Step Secrets Entry
1. Run the following command from the root of the repository to decrypt and edit the secrets file:
   ```bash
   task tofu:secrets:edit STACK_NAME=proxmox_atlas
   ```
2. Insert/update the `proxmox_connection` block:
   ```hcl
   proxmox_connection = {
     url          = "https://192.168.0.10:8006/api2/json" # Replace with your Proxmox node IP
     insecure_tls = true
     auth_method  = "token"
     token_auth = {
       id     = "tofu-prov@pve!tofu-token"
       secret = "your-proxmox-api-token-secret-here"
     }
   }
   ```
3. Save and close the editor. The file will be automatically re-encrypted.
