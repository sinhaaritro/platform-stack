
# Kubernetes Operations Guide

This directory (`k8s/`) contains the complete declarative state for all applications and services running on the homelab's Kubernetes cluster. This document serves as the primary runbook for deploying, managing, and recovering the application platform.

The entire system is managed via **Kustomize**. All operations should be performed by modifying the YAML files in this directory and applying them from the root.

## Table of Contents
1.  [Initial Cluster Setup](#1-initial-cluster-setup)
2.  [Day-to-Day Operations](#2-day-to-day-operations)
    -   [Applying Changes](#applying-changes)
    -   [Adding a New Application](#adding-a-new-application)
    -   [Managing Secrets](#managing-secrets)
3.  [Disaster Recovery Plan](#3-disaster-recovery-plan)

---

## 1. Initial Cluster Setup

This procedure is for bootstrapping the Kubernetes cluster on a freshly provisioned VM (e.g., `megalo`).

1.  **Prepare the VM:**
    *   Install all necessary tools (`docker`, `kind`, `kubectl`, `kubeseal`) by following the `docs/System_Setup.md` guide.
    *   Configure the NFS mount at `/mnt/nfs/media-share` by following the `docs/Storage_Architecture.md` guide.

2.  **Clone the Repository:**
    ```bash
    git clone <your-repo-url>
    cd platform-stack/
    ```

3.  **Create the Kind Cluster:**
    The `kind-config.yaml` is pre-configured to handle port mappings and NFS volume mounts.
    ```bash
    kind create cluster --config k8s/kind-config.yaml
    ```

4.  **Perform the Two-Phase Bootstrap:**
    The initial deployment must be done in two phases to avoid race conditions with Custom Resource Definitions (CRDs).

    *   **Phase 1: Apply Core Infrastructure CRDs:**
        This step installs the definitions for Traefik, Prometheus, and Sealed Secrets.
        ```bash
        # Apply Traefik CRDs
        kubectl apply -f k8s/traefik/01-crd.yaml

        # Apply Prometheus CRDs
        kubectl apply --server-side -k k8s/monitoring/manifests/setup/

        # Wait for CRDs to be registered by the API server
        echo "Waiting 30 seconds for CRDs to be established..."
        sleep 30
        ```

    *   **Phase 2: Apply the Full Stack:**
        This command deploys everything else. It is safe to run this command multiple times.
        ```bash
        kubectl apply -k k8s/
        ```

5.  **Verify the Deployment:**
    Use `kubectl get pods -A` to watch all pods across all namespaces. It may take 10-15 minutes for all images to be pulled and all applications to become healthy (`Running`, `1/1`, `2/2`, etc.).

---

## 2. Day-to-Day Operations

### Applying Changes

This repository is the single source of truth. **Do not** use `kubectl edit` or `kubectl patch` to make manual changes. All changes must be made to the YAML files and applied with Kustomize.

From the root of the `platform-stack` repository, run:
```bash
kubectl apply -k k8s/
```
This single command will safely create, update, or delete resources to make the cluster's state match the configuration in this directory.

### Adding a New Application

Follow the established pattern:
1.  Create a new directory for the application (e.g., `k8s/new-app/`).
2.  Create the necessary manifest files inside (`namespace`, `pvc`, `deployment`, `service`, `ingressroute`, `kustomization.yaml`).
3.  Add the new directory (`- ./new-app`) to the `resources` list in the root `k8s/kustomization.yaml`.
4.  Add the new namespace to the `namespaces` argument in `k8s/traefik/03-daemonset.yaml`.
5.  Add a DNS rewrite for `new-app.localhost` in your AdGuard Home instance.
6.  Run `kubectl apply -k k8s/`.

### Managing Secrets

All secrets in this repository must be encrypted as `SealedSecret` objects. The **pre-commit hook** in this repository will automatically check for and reject any commits that contain an unencrypted `kind: Secret`.

#### Workflow 1: Creating a Brand New Secret

1.  **Create a Plain-Text `Secret` File:**
    Create a new file for your secret (e.g., `k8s/some-app/06-new-secret.yaml`). Define it as a standard `Secret`.
    ```yaml
    apiVersion: v1
    kind: Secret
    metadata:
      name: my-new-secret
      namespace: some-app
    stringData:
      API_KEY: "supersecretvalue"
    ```

2.  **Encrypt the File In-Place:**
    Use `kubeseal` to encrypt the file, saving the output to a temporary file, and then replacing the original. This is the safest in-place method.
    ```bash
    # This encrypts the file and saves it as a SealedSecret
    kubeseal --format=yaml < k8s/some-app/06-new-secret.yaml > temp.yaml
    
    # This replaces the original plain-text file with the encrypted version
    mv temp.yaml k8s/some-app/06-new-secret.yaml
    ```
    The file `06-new-secret.yaml` now contains a `kind: SealedSecret` and is safe to commit.

3.  **Add the file** to the appropriate `kustomization.yaml` and run `kubectl apply -k k8s/`.

#### Workflow 2: Editing an Existing Secret

You cannot directly edit a sealed secret. The workflow is to decrypt, edit, and re-encrypt.

1.  **Decrypt the Existing `SealedSecret`:**
    Use your cluster's private key to decrypt the file you want to edit.
    ```bash
    # Decrypt the file into a temporary plain-text version
    kubeseal --recovery-unseal --recovery-private-key ../homelab-kube-sealed-secret/master.key < k8s/some-app/06-new-secret.yaml > temp-decrypted.yaml
    ```

2.  **Edit the Plain-Text File:**
    Open `temp-decrypted.yaml` in your editor and change the secret values as needed.

3.  **Re-Encrypt the File In-Place:**
    Encrypt the modified temporary file and overwrite the original sealed secret file.
    ```bash
    kubeseal --format=yaml < temp-decrypted.yaml > k8s/some-app/06-new-secret.yaml
    ```

4.  **CRITICAL: Delete the temporary decrypted file.**
    ```bash
    rm temp-decrypted.yaml
    ```

5.  Run `kubectl apply -k k8s/` to apply the updated secret to your cluster.

---

## 3. Disaster Recovery Plan

This plan covers the scenario where the **entire Kubernetes cluster and its underlying VM have been lost**, but the Proxmox host, the NFS share, and this Git repository are still intact.

The key to recovery is the **Sealed Secrets master key**, which is stored in a private Git repository: **`https://github.com/sinhaaritro/homelab-kube-sealed-secret`**.

**Procedure:**

1.  **Provision a New Kube VM:**
    *   Create a new VM and follow the `docs/System_Setup.md` guide to install all required tools.
    *   Configure the NFS mount.

2.  **Clone the Repositories:**
    *   `git clone https://github.com/your-org/platform-stack.git`
    *   `git clone https://github.com/sinhaaritro/homelab-kube-sealed-secret.git`

3.  **Create the Kind Cluster:**
    ```bash
    cd platform-stack/
    kind create cluster --config k8s/kind-config.yaml
    ```

4.  **Restore the Sealed Secrets Private Key (CRITICAL STEP):**
    The Sealed Secrets controller will have automatically generated a *new* keypair, which will not be able to decrypt the secrets in your repository. We must overwrite it with the backed-up key.

    ```bash
    # The master.key file is in the cloned private repository
    # This command will delete the new secret and replace it with your backed-up one.
    kubectl replace --force -f ../homelab-kube-sealed-secret/master.key
    ```

5.  **Restart the Controller:**
    To force the controller to load the restored key, restart its pod.
    ```bash
    kubectl rollout restart deployment sealed-secrets-controller -n kube-system
    ```

6.  **Perform the Two-Phase Bootstrap:**
    Now that the cluster can decrypt your secrets, proceed with the standard initial setup as described in [Section 1](#1-initial-cluster-setup).
    *   Apply the CRDs.
    *   Wait.
    *   Apply the full stack with `kubectl apply -k k8s/`.

Your entire application stack, including all secrets, will be restored to its exact previous state.