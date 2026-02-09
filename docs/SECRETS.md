list# Secrets Management Policy

This document is the single source of truth for the policy and procedures related to managing all sensitive information within this project. Adherence to this policy is mandatory.

> **THE CARDINAL RULE**
>
> **No plaintext secrets of any kind shall ever be committed to this Git repository.**
>
> This repository is public. Assume any information committed here is visible to the entire world. This rule is **automatically enforced** by a pre-commit hook that actively scans for unencrypted files that follow our secrets naming convention.

## Table of Contents

1.  [What is Considered a Secret?](#1-what-is-considered-a-secret)
2.  [The Primary Tool: Ansible Vault](#2-the-primary-tool-ansible-vault)
3.  [File Naming Convention (MANDATORY)](#3-file-naming-convention-mandatory)
4.  [Managing the Vault Password](#4-managing-the-vault-password)
5.  [Developer Workflow: Working with Secret Files](#5-developer-workflow-working-with-secret-files)
6.  [Using Secrets in Automation](#6-using-secrets-in-automation)
7.  [Secrets in Kubernetes](#7-secrets-in-kubernetes)

---

## 1. What is Considered a Secret?

A "secret" is any piece of information that could be used to compromise the security, integrity, or privacy of the infrastructure. If you are unsure, err on the side of caution and treat the information as a secret.

This includes, but is not limited to:
-   **Credentials:** Passwords, API keys, private SSH keys, private SSL/TLS certificates.
-   **Network Configuration:** Internal IP addresses, subnets, ranges, and VLAN IDs.
-   **Service Configuration:** Database connection strings, authentication provider client secrets.
-   **Personal Information:** Personal email addresses or domain names not intended for public use.

All such information **must** be stored in an encrypted file using Ansible Vault.

---

## 2. The Primary Tool: Ansible Vault

**Ansible Vault** is the designated tool for secrets management in this project. It is a feature of Ansible that allows for the encryption of data files at rest. It integrates seamlessly with our Ansible-based configuration management and provides a command-line interface that can be used by other tools like OpenTofu.

---

## 3. File Naming Convention (MANDATORY)

To allow our automated hooks to distinguish between secret and non-secret files, all encrypted files **must** follow a strict naming convention.

**The Rule:** Add `.secret` as a suffix to the filename, before the file extension.
**Pattern:** `[filename].secret.[extension]`

This convention is not a suggestion; it is a **mandatory rule enforced by our pre-commit hook**. If you commit a file that matches this pattern but is not encrypted, your commit will be rejected.

#### Examples:
-   An Ansible variables file: `vars.secret.yml`
-   An OpenTofu variables file for production: `prod.secret.tfvars`
-   A file with miscellaneous keys: `api-keys.secret.json`

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

#### 6.1. With Ansible
Ansible automatically decrypts any vaulted file it encounters during a playbook run, using the `ANSIBLE_VAULT_PASSWORD` environment variable. No extra configuration is needed.

#### 6.2. With OpenTofu
OpenTofu cannot read Ansible Vault files directly. We feed secrets to it by decrypting the files on-the-fly. This is handled by our `Taskfile`. A typical command in `Taskfile.yml` looks like this:

```yaml
# In Taskfile.yml
tasks:
  tofu:plan:
    cmds:
      - |
        tofu plan \
          -var-file=<(ansible-vault view environments/prod.secret.tfvars)
```
When you run `task tofu:plan`, the `ansible-vault view` command decrypts the secrets file and pipes the contents directly into the Tofu process without ever writing the plaintext secrets to disk.

---

## 7. Secrets in Kubernetes

Kubernetes has its own native object for managing secrets.

-   **Current Method (Via Ansible):** Ansible playbooks are used to create or update Kubernetes `Secret` objects. The playbook reads the vaulted variables (from a `*.secret.yml` file) and applies them directly to the cluster. This keeps the secret data out of the declarative Kubernetes manifests in the `/k8s` directory.
-   **Future Direction (Sealed Secrets):** We may evolve to use a tool like **Sealed Secrets**, which would allow us to commit encrypted Kubernetes `Secret` manifests to the Git repository.