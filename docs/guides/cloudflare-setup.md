# Cloudflare Account & API Token Setup Guide

This guide describes how to set up a Cloudflare account, generate a secure API Token, define required permissions for Cloudflare Tunnels and DNS management, and integrate them with the `platform-stack` infrastructure.

---

## 1. Account Creation

If you do not have a Cloudflare account:
1. Navigate to [Cloudflare Sign Up](https://dash.cloudflare.com/sign-up).
2. Enter your email and password, then click **Sign Up**.
3. Follow the onboarding flow to add your domain name (apex domain, e.g., `yourdomain.com`).
4. Select the **Free** plan ($0/month) for your domain.
5. Update your domain name registrar's nameservers to point to the Cloudflare nameservers provided during onboarding. Wait for DNS propagation.

---

## 2. Generate API Token

To allow OpenTofu to provision DNS records and establish secure Cloudflare Tunnels, you must generate an API Token. Avoid using the "Global API Key" for security reasons.

1. Log in to the [Cloudflare Dashboard](https://dash.cloudflare.com).
2. Click on the Profile icon in the top right corner and select **My Profile**.
3. In the left sidebar, click **API Tokens**.
4. Click **Create Token**.
5. Scroll down to the bottom and click **Create Custom Token**.
6. Configure your token:
   - **Token name**: `tofu-platform-stack` (or similar).
   - **Permissions**: Add the following three permission rows:
     - **Account** | **Cloudflare Tunnel** | **Edit**
     - **Zone** | **DNS** | **Edit**
     - **Zone** | **Zone** | **Read**
   - **Account Resources**: Select **All accounts** (or your specific Cloudflare account).
   - **Zone Resources**: Select **All zones** (or **Specific zone** -> select your domain).
   - **Client IP Filtering / TTL**: (Optional) Configure if you wish to restrict token usage.
7. Click **Continue to summary**, then click **Create Token**.
8. **CRITICAL:** Copy the generated API Token. *Cloudflare will only display this token once.* Store it securely in a password manager.

---

## 3. Required Permissions

The `cloudflare_alexandria` stack handles zone DNS management, public entry routes, and Cloudflare Zero Trust Tunnels to securely expose homelab services without opening router ports.

> [!WARNING]
> The permissions must be set exactly as shown. Omitting **Account / Cloudflare Tunnel / Edit** will prevent OpenTofu from creating and retrieving tunnel credentials. Similarly, omitting **Zone / DNS / Edit** will prevent automation of domain routing. Ensure your token is restricted only to the zones and accounts necessary to minimize blast radius in case of exposure.

---

## 4. Secrets Integration

The credentials generated in Step 2 must be written directly into the stack's encrypted secrets variable file:
`tofu/stacks/cloud/cloudflare_alexandria/schema.secret.tfvars`.

### Configuration Variables
The OpenTofu stack expects the API Token and your tunnel secrets inside these variables:

| Variable Path | Type | Description |
|---|---|---|
| `cloudflare_api_token` | String | The Cloudflare API Token generated in Step 2 |
| `tunnel_secrets` | Map(String) | A map of tunnel names to their pre-shared secrets (user-defined base64-encoded string, minimum 32 bytes) |

### Step-by-Step Secrets Entry
1. Run the following command from the root of the repository to decrypt and edit the secrets file:
   ```bash
   task tofu:secrets:edit STACK_NAME=cloudflare_alexandria
   ```
2. Insert/update the variables with your values:
   ```hcl
   cloudflare_api_token = "your-cloudflare-api-token-here"

   tunnel_secrets = {
     "homelab-tunnel" = "aGF2ZS1hLW5pY2UtZGF5LW15LWZyaWVuZC1zZWNyZXQ=" # Base64 encoded 32+ bytes secret
   }
   ```
3. Save and close the editor. The file will be automatically re-encrypted.
