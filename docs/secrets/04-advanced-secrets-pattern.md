# Developer Pattern: Advanced Kubernetes Secrets (Bridge Pattern)

## Architecture Principles

1. **SOLID Principles:** Each component handles a single responsibility (SealedSecrets for encryption, ESO for distribution).
2. **Single Source of Truth:** Secrets exists in the apps namespace only. If another app needs the same secret (like a db secret), then ESO will make sure the secret is available in the consumer namespace.
3. **DRY (Don't Repeat Yourself):** Avoid duplicating encrypted secrets across multiple application states.
4. **GitOps Native:** All secrets must be safely committed to the repository.
5. **No Secret Store in Corporate Vaults:** Rely entirely on Kubernetes-native mechanisms (SealedSecrets) for the primary vault.
6. **Automatic Pod Start:** Pods must initialize seamlessly from scratch without manual intervention.

## Core Components

1. **Sealed Secrets (Bitnami):** Used to encrypt raw secrets and securely store them in Git. These are applied to the *Canonical Source Namespace*.
2. **External Secrets Operator (ESO):** Used to intelligently sync and bridge secrets from the Canonical Source Namespace to the *Consumer Namespace*.

## The Cross-Namespace Bridge Pattern

This pattern is designed to solve the problem of sharing a single secret (e.g., a database password) between the infrastructure provider (e.g., PostgreSQL in the `storage` namespace) and the application consumer (e.g., Immich in the `personal` namespace).

### 1. The Canonical Source Namespace (e.g., `storage`)

This namespace *owns* the secret. 

*   You create a `SealedSecret` containing the sensitive data (e.g., `sealed-postgres-admin.yaml`).
*   The `SealedSecret` is decrypted by the cluster's controller into a standard Kubernetes `Secret`.
*   **Crucial detail:** You must add annotations to the `SealedSecret` template to allow the ESO backend service account to read it (e.g., `platform-stack/mirror-to: "personal,security"`).

### 2. The Bridge Mechanism (`ClusterSecretStore`)

To move the secret across namespaces, a `ClusterSecretStore` sits between them.

*   It acts as a secure tunnel.
*   It is configured with a `kubernetes` provider, pointing at the `remoteNamespace` (where the canonical secret lives, e.g., `storage`).
*   It utilizes a highly restricted ServiceAccount (e.g., `eso-kubernetes-backend` in the `security` namespace) to authorize the read.
*   **ArgoCD Timing Constraint:** The `ClusterSecretStore` must be created *before* the remote secret can be fetched. See the "ArgoCD Delivery Constraints" section below.

### 3. The Consumer Namespace (e.g., `personal`)

This namespace *consumes* the secret for an application.

*   Instead of another `SealedSecret`, you create an `ExternalSecret` (e.g., `external-postgres-admin.yaml`).
*   The `ExternalSecret` references the `ClusterSecretStore` created in step 2.
*   ESO reads the secret via the bridge and materializes it as a local standard Kubernetes `Secret` right next to the application pod.
*   **ArgoCD Timing Constraint:** The `ExternalSecret` needs time to bridge the secret *before* the application starts (to avoid CrashLoopBackOff).

## ArgoCD Delivery Constraints (Crucial)

Because pods require their `Secrets` to exist *at the exact moment they start*, we use ArgoCD hooks and sync-waves to stagger the creation of the bridge elements. This guarantees secrets are fully materialized before applications boot.

*   `argocd.argoproj.io/hook: PreSync`: Ensures Secret configurations run before the main sync phase.
*   `argocd.argoproj.io/sync-wave`: Determines the EXACT order of operations. Lower negative numbers run first.

**The Ordered Boot Sequence:**
1.  **Wave -3**: `ClusterSecretStore` is applied (establishes the bridge tunnel).
2.  **Wave -2**: `ExternalSecret` is applied (instructs ESO to pull data through the tunnel). Also `SealedSecrets` specific to the app are created here.
3.  **Wave -1**: Application Pre-flight jobs run (e.g., `init-db`), confidently utilizing the newly fetched secrets.
4.  **Wave 0**: Main applications start.

## Consumption Example: The Init-DB Job

Once the secrets are bridged, your application workloads consume them as standard environmental variables or volume mounts just like any local secret. 

For example, the Immich database initialization (`apps/services/immich/components/init-db/init-db-job.yaml`) runs on `sync-wave: "-1"`, and injects the bridged Postgres admin credential natively:

```yaml
env:
  - name: ADMIN_PASSWORD
    valueFrom:
      secretKeyRef:
        name: postgres-admin    # The bridged ExternalSecret!
        key: POSTGRES_PASSWORD
  - name: DB_USER
    valueFrom:
      secretKeyRef:
        name: immich-db-credentials # A local SealedSecret!
        key: DB_USERNAME
```

Because of the ArgoCD sync-waves, `postgres-admin` is guaranteed to exist before this Job is scheduled by Kubernetes.

## Directory Structure Enforcement

To maintain organization, both the source and the consumer MUST isolate these YAML definitions inside a dedicated `components/secrets/` directory within their respective Kustomize applications.

**Example Structure:**

```text
apps/
├── infrastructure/postgresql-14/
│   ├── base/
│   └── components/
│       └── secrets/
│           ├── kustomization.yaml
│           └── sealed-postgres-admin.yaml     <-- The Source of Truth
└── services/immich/
    ├── base/
    └── components/
        └── secrets/
            ├── kustomization.yaml
            ├── cluster-secret-store.yaml      <-- The Bridge
            ├── external-postgres-admin.yaml   <-- The Consumer
            └── sealed-immich-db-credentials.yaml <-- (App-specific secrets remain SealedSecrets)
```