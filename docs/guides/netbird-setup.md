# NetBird Account & Token Setup Guide

This guide describes how to set up a NetBird account, generate a Personal Access Token (PAT) for OpenTofu automation, and integrate it with the `platform-stack` infrastructure.

---

## 1. Account Creation

If you do not have a NetBird account:
1. Navigate to the [NetBird Management Console](https://app.netbird.io/).
2. Sign up using an Identity Provider (e.g. Google, GitHub, or your custom Authentik/Keycloak OIDC if self-hosted).
3. By default, NetBird offers a **Free Tier** for small networks, allowing up to 100 peers/devices, which is more than enough for a standard homelab setup.

---

## 2. Generate Personal Access Token (PAT)

To allow OpenTofu to provision Netbird Setup Keys, policies, DNS nameserver groups, and subnet routes, you must generate a Personal Access Token (PAT).

1. Log in to the [NetBird Management Console](https://app.netbird.io/).
2. Navigate to **Settings** in the bottom left sidebar.
3. Click on the **Personal Access Tokens** tab.
4. Click **Create Token**.
5. Configure the token:
   - **Token Name**: `tofu-platform-stack` (or similar).
   - **Expiration**: Set an expiration date (e.g., 90 days or 365 days, depending on your rotation policy).
6. Click **Create**.
7. **CRITICAL:** Copy the generated token string immediately. *You will not be able to view this token again after leaving the screen.*

---

## 3. Required Permissions

The NetBird PAT acts on behalf of your user account. 

> [!WARNING]
> NetBird does not currently support granular API Token permissions. The token inherits the full permission level of the account that created it. To manage the full suite of networks, routers, setup keys, and routing policies, the user creating the token must have the **Owner** or **Administrator** role in the NetBird organization. Use caution and ensure this token is kept secure and encrypted.

---

## 4. Secrets Integration

The credentials generated in Step 2 must be written directly into the stack's encrypted secrets variable file:
`tofu/stacks/cloud/netbird_samarkand/schema.secret.tfvars`.

### Configuration Variables
The OpenTofu stack expects the token in the `netbird_management_token` variable:

| Variable Name | Type | Description |
|---|---|---|
| `netbird_management_token` | String | The Netbird Personal Access Token (PAT) generated in Step 2 |

### Step-by-Step Secrets Entry
1. Run the following command from the root of the repository to decrypt and edit the secrets file:
   ```bash
   task tofu:secrets:edit STACK_NAME=netbird_samarkand
   ```
2. Insert/update the variable with your token:
   ```hcl
   netbird_management_token = "your-netbird-pat-token-here"
   ```
3. Save and close the editor. The file will be automatically re-encrypted.
