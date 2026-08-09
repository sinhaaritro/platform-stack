# Oracle Cloud (OCI) Account & API Credentials Setup Guide

This guide describes how to set up an Oracle Cloud Infrastructure (OCI) account, locate necessary account identifiers (OCIDs), generate API PEM keys, and prepare for future integration with the `platform-stack` infrastructure.

---

## 1. Account Creation

Oracle Cloud offers a generous **Always Free Tier** that includes ARM-based virtual machines, block storage, and load balancers, making it ideal for hosting lightweight homelab nodes or remote entry proxies.

1. Navigate to [Oracle Cloud Free Tier Sign Up](https://www.oracle.com/cloud/free/).
2. Select your country and fill in your account details.
3. **Region Selection:** Choose your **Home Region** carefully. Always Free resources (like Ampere ARM instances) are subject to capacity constraints, and you can *only* provision Always Free resources in your Home Region. (Popular regions like `us-ashburn-1` or European hubs may experience compute resource shortages).
4. Enter payment details for verification. Oracle will run a small temporary authorization charge (usually $1 USD) to verify identity, but you will not be billed unless you explicitly upgrade to a Paid account.

---

## 2. Retrieve Account OCIDs & Generate API Keys

OCI uses Oracle Cloud Identifiers (OCIDs) to target api commands to specific tenancies, compartments, and users.

### 2.1. Find Tenancy OCID
1. Log in to the [Oracle Cloud Console](https://cloud.oracle.com).
2. Click on the Profile icon in the top-right corner and select **Tenancy: [Your-Account-Name]**.
3. In the Tenancy Information section, locate **OCID** and click **Copy**.

### 2.2. Find User OCID
1. Click the Profile icon in the top-right corner and click **User settings**.
2. Under User Information, locate **OCID** and click **Copy**.

### 2.3. Find or Create Compartment OCID
Compartments partition OCI resources. For safety, avoid provisioning in the Root compartment.
1. Open the main navigation menu (hamburger icon in top left) -> **Identity & Security** -> **Compartments**.
2. Click **Create Compartment** (e.g. name it `platform-stack-compartment`).
3. Click on the compartment name and click **Copy** next to the **OCID**.

### 2.4. Generate OCI API Key Pair
1. Click the Profile icon in the top-right corner and select **User settings**.
2. On the left side under Resources, click **API Keys**.
3. Click **Add API Key**.
4. Select **Generate API Key Pair**.
5. Click **Download Private Key** (PEM format). Store this file securely (e.g., `oci_api_key.pem`).
6. Click **Add**.
7. In the resulting dialog, OCI will display your configuration file preview. Copy the **Fingerprint** (e.g., `20:3b:97:13:e7:...`) and note your **Region** identifier (e.g., `us-ashburn-1`).

---

## 3. Required Permissions & Resource Constraints

OCI requires explicitly defined IAM permissions and policies.

> [!WARNING]
> Oracle Free Tier account limits are strictly enforced. The Always Free Tier limits you to:
> - Max 4 ARM Ampere A1 Compute instances (up to 24 GB RAM and 4 CPUs total, which can be allocated to 1-4 VMs).
> - Max 2 AMD-based Micro instances.
> - Max 200 GB total Block Volume storage.
>
> If you write policies for OpenTofu automation, ensure your IAM User has policies enabling full resource management within the designated compartment. For example:
> `Allow group PlatformAdmins to manage all-resources in compartment platform-stack-compartment`
>
> Be aware that OCI frequently returns "Out of Host Capacity" errors when trying to provision ARM instances. This is a provider-side constraint due to high demand, not an OpenTofu configuration error.

---

## 4. Secrets Integration

When the Oracle Cloud Infrastructure (OCI) stack is added, the following standard variables will be defined in OCI provider configuration files.

### Configuration Variables
The future OCI OpenTofu provider expects:

| Variable Name | Type | Description |
|---|---|---|
| `tenancy_ocid` | String | The Tenancy OCID |
| `user_ocid` | String | The User OCID |
| `fingerprint` | String | The API Key Fingerprint generated in Step 2.4 |
| `private_key` | String | The plaintext contents of the PEM Private Key |
| `region` | String | The OCI Region (e.g. `us-ashburn-1`) |
| `compartment_ocid` | String | The Target Compartment OCID |

### Future Secrets Entry
Once OCI is configured in your stack (e.g. `tofu/stacks/cloud/oci_babylon`), you will manage its credentials via:
```bash
task tofu:secrets:edit STACK_NAME=oci_babylon
```
And input the variables securely:
```hcl
tenancy_ocid     = "ocid1.tenancy.oc1..aaaaaaaaxxx"
user_ocid        = "ocid1.user.oc1..aaaaaaaayyy"
fingerprint      = "20:3b:97:13:e7:..."
private_key      = "-----BEGIN RSA PRIVATE KEY-----\n...\n-----END RSA PRIVATE KEY-----"
region           = "us-ashburn-1"
compartment_ocid = "ocid1.compartment.oc1..aaaaaaaazzz"
```
