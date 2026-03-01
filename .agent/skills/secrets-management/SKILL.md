---
name: secrets-management
description: Workflow for creating, sealing, and managing Kubernetes secrets and Ansible Vault encrypted files. Use when any task involves passwords, API keys, database credentials, TLS certificates, or sensitive configuration. Also triggered when creating or updating Kubernetes applications that need secret injection (e.g., components/secrets). Covers the full lifecycle from plaintext to SealedSecret to GitOps deployment.
---

# Secrets Management Skill

> **Source of Truth:** All policy and procedures are defined in `docs/secrets/`. This skill codifies the workflows for AI agent use.

## References

- [Secrets Management Policy](../../../docs/secrets/01-secrets-management-policy.md) — Cardinal rules, naming conventions, vault password setup
- [Sealed Secrets Architecture](../../../docs/secrets/02-sealed-secrets-architecture.md) — Master key lifecycle, disaster recovery, bootstrap workflow
- [Creating Kubernetes Secrets](../../../docs/secrets/03-creating-kubernetes-secrets.md) — Developer guide with examples for all secret types

## Decision Tree

Before any action, classify the request:

| Request | Workflow |
|---------|----------|
| "Create a K8s secret" / "Add credentials to app" | → [Seal a Kubernetes Secret](#1-seal-a-kubernetes-secret) |
| "Encrypt a file" / "Add a secret variable" | → [Encrypt with Ansible Vault](#2-encrypt-with-ansible-vault) |
| "Rotate / backup master key" | → [Master Key Operations](#3-master-key-operations) |
| "Creating a new K8s app that needs secrets" | → [App Secret Component](#4-create-app-secret-component) |

---

## 1. Seal a Kubernetes Secret

**Prerequisites:** `kubeseal` CLI installed, `kubectl` access to cluster or public cert available.

### Steps
1. Generate plaintext secret (NEVER write to a tracked file):
   ```bash
   kubectl create secret generic <name> \
     --namespace <ns> \
     --from-literal=KEY=value \
     --dry-run=client -o yaml > /tmp/<name>.yaml
   ```
2. Seal with kubeseal:
   ```bash
   kubeseal --cert <cert.pem> --format yaml \
     < /tmp/<name>.yaml \
     > kubernetes/apps/services/<app>/components/secrets/sealed-<name>.yaml
   ```
3. Securely delete plaintext:
   ```bash
   shred -u /tmp/<name>.yaml
   ```
4. Add `sealed-<name>.yaml` to `kustomization.yaml` resources.
5. Update deployment patch to use `valueFrom.secretKeyRef`.

### Guardrails
- ❌ NEVER commit plaintext secrets to Git
- ❌ NEVER use `value:` for passwords in deployment patches — use `valueFrom.secretKeyRef`
- ✅ SealedSecret YAML files are safe for Git (no `.secret.` suffix needed)
- ✅ Always verify with `kubectl kustomize --enable-helm`

### ⚡ Testing Shortcut (Dev/Kind Clusters Only)

> **Fast iteration over security.** During local development or testing on ephemeral clusters (e.g., Kind), you may skip the `kubeseal` workflow entirely. Apply a plain Kubernetes `Secret` directly to the cluster:
>
> ```bash
> kubectl create secret generic <name> --namespace <ns> --from-literal=KEY=value
> ```
>
> **Rules for testing mode:**
> - ✅ OK to use plain `Secret` applied directly via `kubectl`
> - ✅ OK to use `stringData` in a local-only YAML (do NOT commit)
> - ❌ NEVER commit the plain `Secret` to Git — use `.gitignore` or `/tmp/`
> - ❌ NEVER deploy plain secrets to production clusters
> - 🔁 Before merging to main / deploying to prod, **always seal** via workflow §1

---

## 2. Encrypt with Ansible Vault

**Prerequisites:** `ANSIBLE_VAULT_PASSWORD` environment variable set.

### File Naming Convention (MANDATORY)
Pattern: `[filename].secret.[extension]`

### Steps
1. Rename file: `mv file.yml file.secret.yml`
2. Encrypt: `ansible-vault encrypt file.secret.yml`
3. Verify encryption: `head -1 file.secret.yml` → must show `$ANSIBLE_VAULT`
4. Delete any plaintext original

### Common Operations
- **View:** `ansible-vault view file.secret.yml`
- **Edit:** `ansible-vault edit file.secret.yml`
- **Decrypt (DANGER):** `ansible-vault decrypt file.secret.yml`

---

## 3. Master Key Operations

Read `docs/secrets/02-sealed-secrets-architecture.md` for full procedure.

### Quick Reference
1. **Extract:** `kubectl get secret -n security -l sealedsecrets.bitnami.com/sealed-secrets-key -o yaml > master-key.yaml`
2. **Sanitize:** Strip ephemeral metadata (timestamps, UIDs, resourceVersion)
3. **Place:** `kubernetes/clusters/[CLUSTER]/sealed-secrets/master.secret.yaml`
4. **Encrypt:** `ansible-vault encrypt master.secret.yaml`

---

## 4. Create App Secret Component

When creating a new Kubernetes app that needs secrets, follow this structure:

```
apps/services/<app>/components/secrets/
├── kustomization.yaml        # Component with resources + patches
├── sealed-<name>.yaml        # SealedSecret (safe for Git)
└── patch-env.yaml            # Deployment patch using secretKeyRef
```

### kustomization.yaml Pattern
```yaml
apiVersion: kustomize.config.k8s.io/v1alpha1
kind: Component

resources:
  - sealed-<name>.yaml

patches:
  - path: patch-env.yaml
    target:
      kind: Deployment
      name: <app-name>
```

### patch-env.yaml Pattern
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: <app-name>
spec:
  template:
    spec:
      containers:
        - name: main
          env:
            - name: DB_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: <secret-name>
                  key: DB_PASSWORD
```

### Checklist
- [ ] Created sealed secret via workflow §1 (or plain secret for testing — see [Testing Shortcut](#-testing-shortcut-devkind-clusters-only))
- [ ] Added to kustomization.yaml resources
- [ ] Deployment patch uses `secretKeyRef`, NOT plaintext `value:`
- [ ] `kubectl kustomize --enable-helm` builds successfully
- [ ] No plaintext secrets remain in any tracked file
