# Developer Guide: Creating Kubernetes Secrets

This guide outlines how to safely create and commit application secrets for our Kubernetes workloads using **Sealed Secrets**. 

Because of our GitOps architecture, you will never run `kubectl create secret` directly against the cluster. Instead, you will create a `SealedSecret` file locally, commit it to Git, and let ArgoCD deploy it.

## Prerequisites

1.  Install the `kubeseal` CLI tool (e.g., `brew install kubeseal`).
2.  Ensure you have `kubectl` access to the cluster so `kubeseal` can fetch the public key. *(Alternatively, the public cert can be downloaded and used completely offline via `kubeseal --cert pub-cert.pem`).*

---

## How to Create Secrets (Examples)

The general workflow consists of two steps:
1.  Generate a standard Kubernetes Secret locally in YAML format (using `--dry-run=client`).
2.  Pipe that YAML directly into `kubeseal` to create the encrypted `SealedSecret`.

> **Note:** The output files (`*-sealed.yaml`) are fully encrypted. You **can** and **should** commit them to Git. They do not need the `.secret.` file suffix used by Ansible Vault.

### Example 1: Creating an Opaque Secret from Literals (e.g., DB Password)

Use this when you have a few specific key-value pairs, such as a database password or a single API token.

```bash
kubectl create secret generic db-credentials \
  --namespace my-app \
  --from-literal=username=admin \
  --from-literal=password=SuperSecret123! \
  --dry-run=client -o yaml | \
kubeseal --format=yaml > db-credentials-sealed.yaml
```

### Example 2: Creating a Secret from an Environment File (`.env`)

Use this when your application requires a `.env` file containing multiple environment variables.

1. Create a temporary `.env` file locally:
   ```env
   STRIPE_API_KEY=sk_test_12345
   OAUTH_CLIENT_SECRET=abc987
   REDIS_URL=redis://localhost:6379
   ```

2. Generate the Sealed Secret from the file:
   ```bash
   kubectl create secret generic app-env-secret \
     --namespace my-app \
     --from-env-file=.env \
     --dry-run=client -o yaml | \
   kubeseal --format=yaml > app-env-sealed.yaml
   ```

3. **CRITICAL:** Securely delete the temporary `.env` file so it is not accidentally committed to Git.
   ```bash
   rm .env
   ```

### Example 3: Creating a TLS Certificate Secret

Use this when you need to store custom SSL/TLS certificates for Ingress controllers or mutual TLS (mTLS).

1. Ensure you have your `tls.crt` and `tls.key` files locally.
2. Generate the Sealed Secret:
   ```bash
   kubectl create secret tls custom-domain-tls \
     --namespace ingress-nginx \
     --cert=tls.crt \
     --key=tls.key \
     --dry-run=client -o yaml | \
   kubeseal --format=yaml > custom-domain-tls-sealed.yaml
   ```

### Example 4: Creating a Secret from an Application Config File (e.g., `config.json`)

Use this when your application mounts a secure configuration file (like a JSON or YAML config) directly into the pod.

```bash
kubectl create secret generic app-config-file \
  --namespace my-app \
  --from-file=config.json=./local-secure-config.json \
  --dry-run=client -o yaml | \
kubeseal --format=yaml > app-config-sealed.yaml
```

---

## Modifying an Existing Sealed Secret

You **cannot** decrypt a `SealedSecret` back into plaintext on your local machine. If you need to change a password:

1. Re-run the exact `kubectl create secret ... | kubeseal` command you used to create it, substituting the new password.
2. Overwrite the existing `*-sealed.yaml` file.
3. Commit and push the updated file to Git. ArgoCD will handle the rest.