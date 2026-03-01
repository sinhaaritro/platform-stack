# Sealed Secrets Architecture & Disaster Recovery

Because our infrastructure is fully defined as code (OpenTofu) and managed ephemerally (rebuilt automatically), we face a specific challenge with Kubernetes Sealed Secrets: **The Master Key Lifecycle.**

## The Ephemeral Cluster Problem
By default, the Bitnami Sealed Secrets controller generates a new RSA public/private key pair when it starts up for the first time. If we destroy our Proxmox VMs and rebuild the K3s cluster, a **new** master key is generated. Consequently, all the `SealedSecret` files currently stored in our Git repository will fail to decrypt, breaking all our applications.

## The Solution: Ansible Vault Injection

To ensure our encrypted Git repository remains valid across infinite cluster teardowns and rebuilds, we utilize **Ansible Vault** to backup the Master Key and inject it during the K3s bootstrap process, *before* ArgoCD installs the Sealed Secrets controller.

### The Bootstrap Workflow
1. **OpenTofu** provisions fresh VMs on Proxmox.
2. **Ansible** configures the OS and installs K3s.
3. **Ansible** creates the `security` namespace.
4. **Ansible** dynamically decrypts our backed-up Master Key (`master.secret.yaml`) from Ansible Vault and applies it to K3s.
5. **Ansible** installs ArgoCD.
6. **ArgoCD** installs the Sealed Secrets Controller. 
7. The controller detects the pre-existing Master Key, skips generating a new one, and uses our vaulted key to safely decrypt all GitOps application secrets.

---

## Administrator Guide: Backing up the Master Key

If you are setting this up for the first time, or explicitly rotating the master key, follow these steps to back it up to Ansible Vault.

### 1. Extract the Active Key
From a running, healthy cluster, extract the current active key:
```bash
kubectl get secret -n security -l sealedsecrets.bitnami.com/sealed-secrets-key -o yaml > master-key.yaml
```

### 2. Sanitize the Manifest
Open `master-key.yaml` and strip out all ephemeral Kubernetes metadata (creation timestamps, UIDs, resource versions). Keep only the `name`, `namespace`, `labels`, `type`, and `data`.

**Cleaned Example:**
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: sealed-secrets-key-master
  namespace: security
  labels:
    sealedsecrets.bitnami.com/sealed-secrets-key: active
type: kubernetes.io/tls
data:
  tls.crt: LS0tLS1CR...
  tls.key: QmFzZTY...
```

### 3. Encrypt with Ansible Vault
Move the sanitized file into the appropriate location and encrypt it:
```bash
mv master-key.yaml kubernetes/clusters/[CLUSTER_NAME]/sealed-secrets/master.secret.yaml
ansible-vault encrypt kubernetes/clusters/[CLUSTER_NAME]/sealed-secrets/master.secret.yaml
```

### 4. Prevent Automatic Key Rotation
To prevent the controller from generating new keys every 30 days (which would desync from our Ansible Vault backup), automatic key rotation is permanently disabled via ArgoCD Helm values:
```yaml
# In our ArgoCD application values for Sealed Secrets
keyrenewperiod: "0"
```
