# AWS Account & Credentials Setup Guide

This guide describes how to set up an AWS account, obtain programmatic API credentials (access keys), configure necessary IAM permissions, and integrate them with the `platform-stack` infrastructure.

---

## 1. Account Creation

If you do not have an AWS account:
1. Navigate to [AWS Portal Registration](https://portal.aws.amazon.com/billing/signup).
2. Enter your email, password, and AWS account name. Complete the verification steps.
3. Choose the **Basic Support - Free** plan.
4. AWS accounts include a **Free Tier** for 12 months, which covers limited usage of services like S3 and DynamoDB.

---

## 2. Generate API Access Keys

To allow OpenTofu to provision resources, you must create a programmatic IAM User and generate an Access Key ID and Secret Access Key.

1. Log in to the [AWS Management Console](https://console.aws.amazon.com).
2. In the top search bar, search for **IAM** (Identity and Access Management) and select it.
3. In the left navigation pane, click **Users**, then click **Create user**.
4. Configure the user:
   - **User name**: `tofu-platform-stack` (or similar descriptive name).
   - **Console access**: Leave **unchecked** (this user only needs programmatic API access).
   - Click **Next**.
5. Set permissions:
   - For initial setup, choose **Attach policies directly**.
   - Search for and select the **AdministratorAccess** policy (or attach a custom least-privilege policy as outlined in the permissions section below).
   - Click **Next**.
6. Review the settings and click **Create user**.
7. In the user list, click on the name of your newly created user (`tofu-platform-stack`).
8. Go to the **Security credentials** tab.
9. Scroll down to the **Access keys** section and click **Create access key**.
10. Select the **Command Line Interface (CLI)** use case.
11. Check the box acknowledging the recommendation for alternative security credentials, and click **Next**.
12. (Optional) Add a description tag, then click **Create access key**.
13. **CRITICAL:** Copy the **Access key ID** and the **Secret access key**. Click **Download .csv file** to save them securely. *Once you close this page, you will never be able to view the secret key again.*

---

## 3. Required Permissions

The `aws_kyoto` stack is designed to provision global resources, primarily S3 buckets for backups (Velero, Immich) and managing IAM users/groups. 

> [!WARNING]
> In a homelab, resources and configurations frequently change. A broad privilege level (like `AdministratorAccess`) makes it easier to expand your stack without authentication errors. However, if your keys are leaked, an attacker has full control of your AWS account. If you expose services publicly or share the environment, a least-privilege policy is highly recommended.

### Scoped Policy Example
To run the default `aws_kyoto` stack configuration under least privilege, you can attach a custom policy containing the following permissions:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:CreateBucket",
        "s3:DeleteBucket",
        "s3:GetBucketLocation",
        "s3:GetBucketVersioning",
        "s3:PutBucketVersioning",
        "s3:GetBucketPublicAccessBlock",
        "s3:PutBucketPublicAccessBlock",
        "s3:GetEncryptionConfiguration",
        "s3:PutEncryptionConfiguration",
        "s3:ListBucket",
        "s3:ListAllMyBuckets"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "iam:CreateGroup",
        "iam:DeleteGroup",
        "iam:GetGroup",
        "iam:UpdateGroup",
        "iam:CreateUser",
        "iam:DeleteUser",
        "iam:GetUser",
        "iam:UpdateUser",
        "iam:AddUserToGroup",
        "iam:RemoveUserFromGroup",
        "iam:CreatePolicy",
        "iam:DeletePolicy",
        "iam:GetPolicy",
        "iam:GetPolicyVersion",
        "iam:CreatePolicyVersion",
        "iam:DeletePolicyVersion",
        "iam:AttachGroupPolicy",
        "iam:DetachGroupPolicy"
      ],
      "Resource": "*"
    }
  ]
}
```

---

## 4. Secrets Integration

The credentials generated in Step 2 must be written directly into the stack's encrypted secrets variable file:
`tofu/stacks/cloud/aws_kyoto/schema.secret.tfvars`.

### Configuration Variables
The OpenTofu stack expects these credentials within the `aws_credentials` object:

| Variable Path | Type | Description |
|---|---|---|
| `aws_credentials.name` | String | A label identifying this set of credentials (e.g. `"tofu-platform"`) |
| `aws_credentials.access_key` | String | The AWS Access Key ID |
| `aws_credentials.secret_key` | String | The AWS Secret Access Key |

### Step-by-Step Secrets Entry
1. Run the following command from the root of the repository to decrypt and edit the secrets file:
   ```bash
   task tofu:secrets:edit STACK_NAME=aws_kyoto
   ```
2. Insert/update the `aws_credentials` block with your values:
   ```hcl
   aws_credentials = {
     name       = "tofu-platform-stack"
     access_key = "AKIAEXAMPLEACCESSKEY"
     secret_key = "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
   }
   ```
3. Save and close the editor. The file will be automatically re-encrypted.
