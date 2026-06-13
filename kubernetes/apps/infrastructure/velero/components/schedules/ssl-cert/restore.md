# SSL Certificates Restore Runbook

**Use Case**: Any scenario — loss, corruption, deletion, or full rebuild of SSL TLS Certificates.

**Behavior**: Restores secrets into the shared, unmanaged `restore` namespace, then replicates only the TLS secrets into the live `networking` namespace.

---

## Runbook Steps

### 1. Identify Backup Name
Find the latest backup name for SSL certificates:
```bash
kubectl get backups.velero.io -n backup -l velero.io/schedule-name=daily-ssl-certs --sort-by=.metadata.creationTimestamp
```

### 2. Update Restore Configuration
1. Replace `BACKUP_NAME` in `restore.yaml` (at the bottom of this directory) with the identified backup name.
2. Apply the restore manifest:
   ```bash
   kubectl apply -f restore.yaml
   ```

### 3. Verify Velero Restore Completion
Verify the restore has finished successfully:
```bash
kubectl get restore ssl-cert-restore -n backup -o jsonpath='{.status.phase}' && echo ""
```
**Expected output**:
```text
Completed
```

### 4. Copy TLS Secrets to Live Namespace
Since Velero restores to the `restore` namespace, extract only TLS secrets, map them to the live `networking` namespace, and apply them:
```bash
kubectl get secret -n restore --field-selector type=kubernetes.io/tls -o yaml \
  | sed 's/namespace: restore/namespace: networking/' \
  | kubectl apply -f -
```
**Verify**:
Verify that the TLS secrets exist in the `networking` namespace:
```bash
kubectl get secrets -n networking --field-selector type=kubernetes.io/tls
```
**Expected output**:
```text
NAME                     TYPE                DATA   AGE
aritro-net-production    kubernetes.io/tls   2      1m
```

### 5. Cleanup
Once verified, clean up temporary resources:
```bash
kubectl delete ns restore
kubectl delete restore ssl-cert-restore -n backup
```
