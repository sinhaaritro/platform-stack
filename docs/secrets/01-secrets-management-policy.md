# Secrets Management Policy

This document is the single source of truth for the policy and procedures related to managing all sensitive information within this project. Adherence to this policy is mandatory.

> **THE CARDINAL RULE**
>
> **No plaintext secrets of any kind shall ever be committed to this Git repository.**
>
> This repository is public. Assume any information committed here is visible to the entire world. This rule is **automatically enforced** by a pre-commit hook that actively scans for unencrypted files that follow our secrets naming convention.

## Table of Contents

1. [What is Considered a Secret?](#1-what-is-considered-a-secret)
2. [The Primary Tools: Ansible Vault & Sealed Secrets](#2-the-primary-tools-ansible-vault--sealed-secrets)
3. [File Naming Convention (MANDATORY)](#3-file-naming-convention-mandatory)
4. [Managing the Vault Password](#4-managing-the-vault-password)
5. [Developer Workflow: Working with Secret Files](#5-developer-workflow-working-with-secret-files)
6. [Using Secrets in Automation](#6-using-secrets-in-automation)
7. [Secrets in Kubernetes (GitOps)](#7-secrets-in-kubernetes-gitops)

---

## 1. What is Considered a Secret?

A "secret" is any piece of information that could be used to compromise the security, integrity, or privacy of the infrastructure. If you are unsure, err on the side of caution and treat the information as a secret.

This includes, but is not limited to:
-   **Credentials:** Passwords, API keys, private SSH keys, private SSL/TLS certificates.
-   **Network Configuration:** Internal IP addresses, subnets, ranges, and VLAN IDs.
-   **Service Configuration:** Database connection strings, authentication provider client secrets.
-   **Personal Information:** Personal email addresses or domain names not intended for public use.

---

## 2. The Primary Tools: Ansible Vault & Sealed Secrets

We utilize a two-pronged approach to secrets management due to our Infrastructure-as-Code (OpenTofu/Ansible) and GitOps (ArgoCD/K3s) architecture:

1.  **Ansible Vault:** Used for infrastructure-level secrets (VM passwords, OpenTofu variables, K3s bootstrap tokens) and for backing up the Kubernetes Sealed Secrets Master Key.
2.  **Bitnami Sealed Secrets:** Used for application-level Kubernetes secrets. This allows developers to safely commit encrypted Kubernetes `Secret` manifests directly into the Git repository for ArgoCD to deploy.

---

## 3. File Naming Convention (MANDATORY)

To allow our automated hooks to distinguish between secret and non-secret files, all **Ansible Vault encrypted files** must follow a strict naming convention.

**The Rule:** Add `.secret` as a suffix to the filename, before the file extension.
**Pattern:** `[filename].secret.[extension]`

*Note: This convention is strictly for Ansible Vault files. Kubernetes `SealedSecret` YAML files generated via `kubeseal` do NOT require this suffix, as they are a custom Kubernetes resource inherently safe for Git.*

#### Examples:
-   An Ansible variables file: `vars.secret.yml`
-   An OpenTofu variables file for production: `prod.secret.tfvars`

---

## 4. Managing the Vault Password

The Ansible Vault is encrypted with a master password.

1.  **Obtaining the Password:** The vault password must be obtained from a project administrator through a secure, out-of-band channel (e.g., a password manager share).
2.  **Configuring Your Environment:** You must set the `ANSIBLE_VAULT_PASSWORD` environment variable.
   > **See [GETTING_STARTED.md](./GETTING_STARTED.md#3-configure-secrets) for the official setup instructions.**

---

## 5. Developer Workflow: Working with Secret Files

All of the following commands should be run from within the `ansible/` directory.

#### 5.1. Viewing an Encrypted File

To view the plaintext contents of a vaulted file:
```sh
ansible-vault view group_vars/all/vars.secret.yml
```

#### 5.2. Editing an Encrypted File

This command decrypts the file into a temporary location, opens your default editor, and automatically re-encrypts the file upon saving and closing.
```sh
ansible-vault edit group_vars/all/vars.secret.yml
```

#### 5.3. Creating a New Encrypted File

When creating a new file for secrets, you **must** follow the naming convention.
```sh
ansible-vault create group_vars/all/new-creds.secret.yml
```

#### 5.4. Encrypting an Existing Plaintext File

If you have a plaintext file that needs to be converted into a secret:

1.  **Rename the file** to follow the mandatory naming convention.
    ```sh
    mv my-plaintext-vars.yml my-plaintext-vars.secret.yml
    ```

2.  **Encrypt the file** using `ansible-vault encrypt`.
    ```sh
    # DANGER: The original plaintext file is NOT automatically deleted by this command.
    ansible-vault encrypt my-plaintext-vars.secret.yml
    ```
    You have now created an encrypted version (`my-plaintext-vars.secret.yml`) and the original plaintext file still exists.

3.  **VERIFY AND SECURELY DELETE THE PLAINTEXT ORIGINAL.** This is a critical step to avoid accidentally committing secrets.

---

## 6. Using Secrets in Automation

-   **With Ansible:** Ansible automatically decrypts vaulted files during a playbook run using the `ANSIBLE_VAULT_PASSWORD` environment variable.
-   **With OpenTofu:** OpenTofu cannot read Ansible Vault directly. Our `Taskfile` handles on-the-fly decryption into standard input:
    ```yaml
    # In Taskfile.yml
    tasks:
      tofu:plan:
        cmds:
          - tofu plan -var-file=<(ansible-vault view environments/prod.secret.tfvars)
    ```
> **Note:** (When you run `task tofu:plan`, the `ansible-vault view` command decrypts the secrets file and pipes the contents directly into the Tofu process without ever writing the plaintext secrets to disk.)

---

## 7. Secrets in Kubernetes (GitOps)

Because we use ArgoCD for continuous deployment, our Kubernetes manifests live in Git. Standard Kubernetes `Secret` objects are only base64 encoded, meaning they **cannot** be committed to Git.

To solve this, we use **Sealed Secrets**. 
- Application secrets are encrypted locally using the `kubeseal` CLI tool.
- The resulting `SealedSecret` object is committed to Git.
- ArgoCD deploys the `SealedSecret` to K3s.
- The Sealed Secrets Controller running inside K3s decrypts it into a standard Kubernetes `Secret`.

For details on how the encryption master key survives cluster rebuilds, see [Sealed Secrets Architecture & Disaster Recovery](./02-sealed-secrets-architecture.md).  
For developer instructions on creating these secrets, see [Creating Kubernetes Secrets](./03-creating-kubernetes-secrets.md).
