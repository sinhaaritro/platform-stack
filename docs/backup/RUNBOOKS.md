# Restore Runbook Templates

> **Scope:** Generic restore procedures organized by workload type. Any application — current or future — slots into the appropriate template. For backup architecture details, see [ARCHITECTURE.md](./ARCHITECTURE.md).

---

## Restore Strategy

All restores follow a **namespace-mapped** pattern: data is restored into a shared `restore` namespace (which ArgoCD does NOT manage), verified, then migrated to the live namespace. This avoids ArgoCD race conditions and allows safe verification before going live.

### Restore Decision Tree

```mermaid
---
config:
  theme: redux
  look: neo
  layout: elk
---
flowchart TD
  subgraph Diagram["Restore Decision Tree"]
    Start["Need to restore?"] --> Q1{"What was lost?"}
    Q1 -->|"Single app's data"| Q2{"Does the app\nhave PVC data?"}
    Q1 -->|"Entire cluster"| TE["Template E:\nFull Cluster Rebuild"]
    Q2 -->|"No PVC\n(stateless)"| TA["Template A:\nStateless Restore"]
    Q2 -->|"Yes, PVC\n(no DB)"| TB["Template B:\nStateful App Restore"]
    Q2 -->|"Yes, PVC\nwith database"| TC["Template C:\nDatabase App Restore"]
    Q2 -->|"Yes, PVC\n+ NFS data"| TD["Template D:\nApp with NFS Data"]
  end

  style Start fill:#E1BEE7
  style TA fill:#C8E6C9
  style TB fill:#BBDEFB
  style TC fill:#FFE0B2
  style TD fill:#FFCDD2
  style TE fill:#EF9A9A
  style Diagram fill:transparent
```

---

## Common Variables

All templates use these variables. Replace them before executing:

| Variable | Description | How to Find |
|---|---|---|
| `<APP>` | Application name | e.g., `obsidian`, `immich` |
| `<NAMESPACE>` | Source namespace | e.g., `personal`, `security` |
| `<SCHEDULE_NAME>` | Velero schedule name | `kubectl get schedules -n backup` |
| `<BACKUP_NAME>` | Specific backup to restore from | `kubectl get backups -n backup -l velero.io/schedule-name=<SCHEDULE_NAME>` |
| `<PVC_NAME>` | PVC to restore | `kubectl get pvc -n <NAMESPACE> -l app=<APP>` |
| `<BACKUP_PVC_NAME>` | Dedicated backup PVC (Template C) | e.g., `<APP>-db-backup` |
| `<DB_HOSTNAME>` | Database host | Check app's env vars or Secret |
| `<DB_USERNAME>` | Database user | Check app's Secret |
| `<DB_PASSWORD>` | Database password | Check app's Secret |
| `<DB_DATABASE_NAME>` | Database name | Check app's env vars or Secret |

## Common Prerequisites

Before any restore:

1.  Velero is healthy: `kubectl get deployment velero -n backup`
2.  BSL is available: `kubectl get bsl -n backup`
3.  The backup exists and is completed: `kubectl get backup <BACKUP_NAME> -n backup -o jsonpath='{.status.phase}'`
4.  The `restore` namespace does not exist or is empty: `kubectl get ns restore`

---

## Template A: Stateless App Restore

**When to use:** K8s resources only (Deployments, Services, Secrets). No PVC data to restore. The app is fully defined by its manifests.

**Examples:** SSL certificates (cert-manager re-issues), stateless API gateways, CronJobs.

**Estimated time:** 5-10 minutes.

```bash
# 1. Find the backup
kubectl get backups.velero.io -n backup \
  -l velero.io/schedule-name=<SCHEDULE_NAME> \
  --sort-by=.metadata.creationTimestamp

# 2. Create the restore (namespace-mapped)
cat <<EOF | kubectl apply -f -
apiVersion: velero.io/v1
kind: Restore
metadata:
  name: <APP>-restore
  namespace: backup
spec:
  backupName: <BACKUP_NAME>
  includedNamespaces:
    - <NAMESPACE>
  namespaceMapping:
    <NAMESPACE>: restore
  existingResourcePolicy: none
  restorePVs: false
EOF

# 3. Wait for completion
kubectl get restore <APP>-restore -n backup -w

# 4. Verify restored resources
kubectl get all -n restore

# 5. If satisfied, apply to live namespace via ArgoCD sync
#    (ArgoCD manages the live namespace — restoring directly would conflict)

# ⚠️ WARNING: Dynamically generated in-cluster state (e.g., cert-manager SSL/TLS Secrets)
# is not stored in Git and cannot be synced by ArgoCD. If you are restoring a dynamically
# generated Secret/TLS Cert, you must manually copy it from the 'restore' namespace:
#
# kubectl get secret <SECRET_NAME> -n restore -o yaml \
#   | sed 's/namespace: restore/namespace: <NAMESPACE>/' \
#   | kubectl apply -f -

# 6. Cleanup
kubectl delete ns restore
kubectl delete restore <APP>-restore -n backup
```

---

## Template B: Stateful App Restore (Longhorn PVC)

**When to use:** App has a Longhorn PVC with config or data that is NOT a database (no consistency hook needed). Velero backed up the PVC via `defaultVolumesToFsBackup: true`.

**Examples:** Obsidian (config PVC), any app with a `/config` directory on Longhorn.

> [!WARNING]
> The placeholders `/data` and `<PVC_NAME>` in this template are generic. You must replace them with the application's actual mount path (e.g., `/config` for Obsidian) and specific PVC name (e.g., `obsidian-config`).

**Estimated time:** 15-30 minutes.

```bash
# 1. Find the backup
kubectl get backups.velero.io -n backup \
  -l velero.io/schedule-name=<SCHEDULE_NAME> \
  --sort-by=.metadata.creationTimestamp

# 2. Enable maintenance mode (scale app to 0)
#    Option A: Via Git (recommended — ArgoCD-safe)
#      Add/uncomment the maintenance component in the cluster overlay kustomization.yaml:
#        - ../../../apps/services/<APP>/components/maintenance
#      Commit and push. Wait for ArgoCD sync.
#    Option B: Direct (temporary — ArgoCD will revert)
kubectl scale deploy <APP> -n <NAMESPACE> --replicas=0

# 3. Verify app is scaled down
kubectl get deploy <APP> -n <NAMESPACE>
# READY should show 0/0

# 4. Create the restore (namespace-mapped)
cat <<EOF | kubectl apply -f -
apiVersion: velero.io/v1
kind: Restore
metadata:
  name: <APP>-restore
  namespace: backup
spec:
  backupName: <BACKUP_NAME>
  includedNamespaces:
    - <NAMESPACE>
  namespaceMapping:
    <NAMESPACE>: restore
  labelSelector:
    matchLabels:
      app: <APP>
  existingResourcePolicy: none
  restorePVs: true
EOF

# 5. Wait for completion
kubectl get restore <APP>-restore -n backup -w

# 6. Copy data from restored PVC to live PVC
#    a) Mount the live PVC
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: pvc-mount-live
  namespace: <NAMESPACE>
spec:
  containers:
  - name: mount
    image: alpine
    command: ["sleep", "3600"]
    volumeMounts:
    - name: data
      mountPath: /data
  volumes:
  - name: data
    persistentVolumeClaim:
      claimName: <PVC_NAME>
  restartPolicy: Never
EOF

#    b) Mount the restored PVC
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: pvc-mount-restored
  namespace: restore
spec:
  containers:
  - name: mount
    image: alpine
    command: ["sleep", "3600"]
    volumeMounts:
    - name: data
      mountPath: /data
  volumes:
  - name: data
    persistentVolumeClaim:
      claimName: <PVC_NAME>
  restartPolicy: Never
EOF

#    c) Wait for pods
kubectl wait pod/pvc-mount-live -n <NAMESPACE> --for=condition=Ready --timeout=60s
kubectl wait pod/pvc-mount-restored -n restore --for=condition=Ready --timeout=60s

#    d) Copy: restored → local → live
kubectl cp restore/pvc-mount-restored:/data ./restore-data-tmp
kubectl cp ./restore-data-tmp <NAMESPACE>/pvc-mount-live:/data

#    e) Cleanup temp pods
kubectl delete pod pvc-mount-live -n <NAMESPACE>
kubectl delete pod pvc-mount-restored -n restore
rm -rf ./restore-data-tmp

# 7. Disable maintenance mode
#    Revert the Git change (re-comment the maintenance component).
#    Commit and push. ArgoCD scales the app back.

# 8. Verify app is healthy
kubectl get deploy <APP> -n <NAMESPACE>
kubectl get pods -n <NAMESPACE> -l app=<APP>

# 9. Cleanup
kubectl delete ns restore
kubectl delete restore <APP>-restore -n backup
```

---

## Template C: Database App Restore

**When to use:** App has a database that was dumped via a pre-backup hook (inline annotation) or a separate CronJob before Velero ran. The dump file lives on a Longhorn PVC.

**Examples:** Immich (pg_dump inline hook → dump in PVC), Authentik (CronJob → dedicated backup PVC).

**Estimated time:** 30-60 minutes.

```bash
# 1. Find the backup
kubectl get backups.velero.io -n backup \
  -l velero.io/schedule-name=<SCHEDULE_NAME> \
  --sort-by=.metadata.creationTimestamp

# 2. Create the restore (namespace-mapped)
cat <<EOF | kubectl apply -f -
apiVersion: velero.io/v1
kind: Restore
metadata:
  name: <APP>-restore
  namespace: backup
spec:
  backupName: <BACKUP_NAME>
  includedNamespaces:
    - <NAMESPACE>
  namespaceMapping:
    <NAMESPACE>: restore
  existingResourcePolicy: none
  restorePVs: true
EOF

# 3. Wait for completion
kubectl get restore <APP>-restore -n backup -w

# 4. Mount the restored PVC to access the DB dump
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: db-restore
  namespace: restore
spec:
  containers:
  - name: psql
    image: postgres:14-alpine
    command: ["sleep", "3600"]
    volumeMounts:
    - name: backup
      mountPath: /backup
  volumes:
  - name: backup
    persistentVolumeClaim:
      claimName: <BACKUP_PVC_NAME>
  restartPolicy: Never
EOF

kubectl wait pod/db-restore -n restore --for=condition=Ready --timeout=60s

# 5. Restore the database
#    Choose the appropriate connection option based on your database setup:

#    --- OPTION 1: Network-based Connection ---
#    Use when: Restoring to an external database, managed database service (e.g., AWS RDS), 
#    or a database server on a different network subnet.
#    Note: Requires a psql client inside the restore pod and network routing to the host.
#
#    kubectl exec -n restore db-restore -- /bin/sh -c \
#      "PGPASSWORD=<DB_PASSWORD> psql \
#       -h <DB_HOSTNAME> \
#       -U <DB_USERNAME> \
#       -d <DB_DATABASE_NAME> \
#       -f /backup/<APP>-db.sql"

#    --- OPTION 2: UNIX Socket / Super-user Exec Stream (Recommended for internal DBs) ---
#    Use when: Restoring to a cluster-internal database container (e.g., postgresql-14-0) 
#    where we want to bypass network constraints, avoid raw password exposure, and utilize 
#    direct Unix socket peer authentication on the database pod.
#
#    kubectl exec -n restore db-restore -- cat /backup/<APP>-db.sql | \
#      kubectl exec -i -n <DB_NAMESPACE> <DB_POD_NAME> -- psql -U postgres -d <DB_DATABASE_NAME>

# 6. Verify database integrity
#    For Option 1:
#    kubectl exec -n restore db-restore -- /bin/sh -c \
#      "PGPASSWORD=<DB_PASSWORD> psql \
#       -h <DB_HOSTNAME> \
#       -U <DB_USERNAME> \
#       -d <DB_DATABASE_NAME> \
#       -c '\dt'"
#
#    For Option 2:
#    kubectl exec -i -n <DB_NAMESPACE> <DB_POD_NAME> -- psql -U postgres -d <DB_DATABASE_NAME> -c "\dt"

# 7. Cleanup
kubectl delete pod db-restore -n restore
kubectl delete ns restore
kubectl delete restore <APP>-restore -n backup
```

---

## Template D: App with NFS User Data / Large Media Plane

**When to use:** App has both K8s state (Velero) AND large user data on NFS/Object Storage (rclone). The restore requires recovering both planes in a specific order to prevent resource locks and Longhorn storage exhaustion.

**Examples:** Immich (DB on Longhorn + photos on NFS/RWX volume).

**Estimated time:** 1-8 hours (depends on media data volume).

```bash
# 1. Enable maintenance mode (scale app to 0 to prevent conflicting writes)
#    Option A: Via Git (ArgoCD-safe)
#      Uncomment the maintenance component in the kustomization.yaml.
#    Option B: Direct
#      kubectl scale deploy <APP> -n <NAMESPACE> --replicas=0

# 2. Prepare the target namespace and Secrets
kubectl create ns restore
kubectl get secret <APP>-config -n <NAMESPACE> -o json | jq 'del(.metadata.ownerReferences, .metadata.uid, .metadata.resourceVersion, .metadata.creationTimestamp) | .metadata.namespace="restore"' | kubectl apply -f -
kubectl get secret <APP>-db-credentials -n <NAMESPACE> -o json | jq 'del(.metadata.ownerReferences, .metadata.uid, .metadata.resourceVersion, .metadata.creationTimestamp) | .metadata.namespace="restore"' | kubectl apply -f -

# 3. Pre-create mock 1Gi PVCs in target 'restore' namespace
#    ⚠️ WARNING: Crucial to prevent duplicate 50Gi allocations in Longhorn, which exhaust node disks.
#    Replace placeholders with actual PVC names (e.g. immich-library).
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: <APP>-library
  namespace: restore
spec:
  accessModes: [ "ReadWriteMany" ]
  resources: { requests: { storage: 1Gi } }
  storageClassName: longhorn
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: <APP>-machine-learning-cache
  namespace: restore
spec:
  accessModes: [ "ReadWriteMany" ]
  resources: { requests: { storage: 1Gi } }
  storageClassName: longhorn
EOF

# 4. Trigger Velero restore (recovers DB PVC and uploader pod)
kubectl apply -f restore.yaml

# 5. Re-create the database with correct ownership and extensions as superuser
kubectl exec -i -n <DB_NAMESPACE> <DB_POD> -- psql -U postgres -c "DROP DATABASE IF EXISTS \"<DB_NAME>\";"
kubectl exec -i -n <DB_NAMESPACE> <DB_POD> -- psql -U postgres -c "CREATE USER \"<DB_USER>\" WITH PASSWORD '\''<DB_PASSWORD>'\''" || echo "User exists"
kubectl exec -i -n <DB_NAMESPACE> <DB_POD> -- psql -U postgres -c "CREATE DATABASE \"<DB_NAME>\" OWNER \"<DB_USER>\";"
kubectl exec -i -n <DB_NAMESPACE> <DB_POD> -- psql -U postgres -d "<DB_NAME>" -c "CREATE EXTENSION IF NOT EXISTS vectors; GRANT ALL PRIVILEGES ON SCHEMA vectors TO \"<DB_USER>\"; CREATE EXTENSION IF NOT EXISTS cube; CREATE EXTENSION IF NOT EXISTS earthdistance;"

# 6. Stream import DB dump, filtering out incompatible database creation lines
#    a) Start a temp mount pod in 'restore' namespace
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata: { name: restore-temp, namespace: restore }
spec:
  containers:
  - name: utils, image: busybox, command: ["sleep", "3600"]
    volumeMounts: [ { name: data, mountPath: /data } ]
  volumes: [ { name: data, persistentVolumeClaim: { claimName: <APP>-db-backup } } ]
EOF

kubectl wait pod/restore-temp -n restore --for=condition=Ready --timeout=120s

#    b) Stream SQL dump directly to DB pod
kubectl exec -n restore restore-temp -- cat /data/<APP>-db.sql | \
  sed -E '/^(DROP DATABASE|CREATE DATABASE|ALTER DATABASE|\\connect postgres)/Id' | \
  kubectl exec -i -n <DB_NAMESPACE> <DB_POD> -- psql -U postgres -d <DB_NAME>

# 7. Correct ownership of restored objects in the DB public schema to app user
kubectl exec -i -n <DB_NAMESPACE> <DB_POD> -- psql -U postgres -d <DB_NAME> -c '
DO $$
DECLARE r RECORD;
BEGIN
    IF (SELECT pg_catalog.pg_get_userbyid(nspowner) FROM pg_catalog.pg_namespace WHERE nspname = '\''public'\'') = '\''postgres'\'' THEN
        EXECUTE '\''ALTER SCHEMA public OWNER TO <DB_USER>'\'';
    END IF;
    FOR r IN (SELECT tablename FROM pg_tables WHERE schemaname = '\''public'\'' AND (SELECT pg_catalog.pg_get_userbyid(relowner) FROM pg_catalog.pg_class WHERE relname = tablename AND relnamespace = (SELECT oid FROM pg_namespace WHERE nspname = '\''public'\'')) = '\''postgres'\'') LOOP
        EXECUTE '\''ALTER TABLE public.'\'' || quote_ident(r.tablename) || '\'' OWNER TO <DB_USER>'\'';
    END LOOP;
    FOR r IN (SELECT sequencename FROM pg_sequences WHERE schemaname = '\''public'\'' AND (SELECT pg_catalog.pg_get_userbyid(relowner) FROM pg_catalog.pg_class WHERE relname = sequencename AND relnamespace = (SELECT oid FROM pg_namespace WHERE nspname = '\''public'\'')) = '\''postgres'\'') LOOP
        EXECUTE '\''ALTER SEQUENCE public.'\'' || quote_ident(r.sequencename) || '\'' OWNER TO <DB_USER>'\'';
    END LOOP;
    FOR r IN (SELECT viewname FROM pg_views WHERE schemaname = '\''public'\'' AND (SELECT pg_catalog.pg_get_userbyid(relowner) FROM pg_catalog.pg_class WHERE relname = viewname AND relnamespace = (SELECT oid FROM pg_namespace WHERE nspname = '\''public'\'')) = '\''postgres'\'') LOOP
        EXECUTE '\''ALTER VIEW public.'\'' || quote_ident(r.viewname) || '\'' OWNER TO <DB_USER>'\'';
    END LOOP;
END$$;'

# 8. Restore files via rclone to live PVC
#    Run rclone copy from cloud bucket to the live app PVC:
kubectl create job --from=cronjob/<APP>-rclone-backup <APP>-rclone-restore -n <NAMESPACE> --dry-run=client -o yaml \
  | sed 's/rclone sync \/data/rclone copy/g; s/remote:backup-bucket\/<APP>/remote:backup-bucket\/<APP> \/data/g' \
  | kubectl apply -f -

kubectl wait --for=condition=complete job/<APP>-rclone-restore -n <NAMESPACE> --timeout=12h

# 9. Disable maintenance mode (scale app to 1) and delete old pod to force migration
#    Scale up deploy via Git/ArgoCD, then restart:
kubectl delete pod -n <NAMESPACE> -l app.kubernetes.io/name=<APP>,app.kubernetes.io/component=server

# 10. Cleanup
kubectl delete pod restore-temp -n restore
kubectl delete ns restore
kubectl delete restore <APP>-restore -n backup
kubectl delete job <APP>-rclone-restore -n <NAMESPACE>
```

---

## Template E: Full Cluster Rebuild (Disaster Recovery)

**When to use:** Complete infrastructure loss. Starting from bare metal or a fresh Proxmox install.

**Estimated time:** 8-12 hours (within RTO target).

**Prerequisites:**
-   Access to the Git repository (GitHub)
-   AWS credentials for S3 backup access
-   Proxmox host is operational (fresh install is fine)
-   Network connectivity to AWS S3

```bash
# Phase 1: Provision Infrastructure (2-3 hours)

# 1. Clone the repository
git clone <REPO_URL> platform-stack && cd platform-stack

# 2. Provision VMs with OpenTofu
cd tofu/
tofu init && tofu apply

# 3. Configure VMs with Ansible
cd ../ansible/
ansible-playbook -i inventory site.yml

# 4. Bootstrap Kubernetes
#    (Handled by Ansible roles — kubeadm init + join)

# Phase 2: Deploy Platform (1-2 hours)

# 5. Install ArgoCD
kubectl apply -k kubernetes/bootstrap/<CLUSTER>/

# 6. Wait for ArgoCD to sync all applications
#    ArgoCD will deploy everything from Git.
#    Watch: kubectl get applications -n argocd

# 7. Wait for core infrastructure
#    Longhorn, SeaweedFS, cert-manager, Cloudflare Tunnel
kubectl get pods -A -w

# Phase 3: Restore Data (2-8 hours)

# 8. Install Velero (deployed by ArgoCD, but verify)
kubectl get deploy velero -n backup

# 9. Verify BSL is available
kubectl get bsl -n backup

# 10. Restore critical apps first (priority order)
#     a) Authentication — Template C
#     b) Photo library DB — Template C
#     c) Document vaults — Template B
#     d) SSL certificates — Template A (or wait for cert-manager)

# 11. Restore NFS data via rclone — Template D
#     For each app with NFS data, run the rclone restore.

# Phase 4: Verify (30 minutes)

# 12. Verify all apps are healthy
kubectl get pods -A | grep -v Running | grep -v Completed

# 13. Verify data integrity for critical apps
#     - Log into auth provider, verify SSO
#     - Open photo manager, verify images load
#     - Open notes app, verify vaults sync

# 14. Verify monitoring is collecting data
#     - Check Grafana dashboards
#     - Verify Velero schedules are active
```

---

## Related Documentation

| Document | Relationship |
|---|---|
| [README.md](./README.md) | Backup overview, ABC strategy, RPO/RTO |
| [ARCHITECTURE.md](./ARCHITECTURE.md) | Velero/rclone technical architecture |
| [MONITORING.md](./MONITORING.md) | Periodic restore drills, alerting |
| [CAPACITY_PLANNING.md](./CAPACITY_PLANNING.md) | Backup size estimation, cost model |
