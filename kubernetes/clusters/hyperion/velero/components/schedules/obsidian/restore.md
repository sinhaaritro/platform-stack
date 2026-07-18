# Obsidian Database/Config Restore Runbook

**Use Case**: Any scenario — corruption, deletion, or full rebuild of Obsidian data.

**Behavior**: Restores resources into the shared, unmanaged `restore` namespace, then replicates data from the restored PVC to the live PVC using temporary copy pods.

---

## Runbook Steps

### 1. Identify Backup Name
Find the latest daily backup name for Obsidian:
```bash
kubectl get backups.velero.io -n backup -l velero.io/schedule-name=daily-obsidian --sort-by=.metadata.creationTimestamp
```

### 2. Enable Maintenance Mode
Scales the live Obsidian application to `0` replicas to lock files during the restore:
1. In `kubernetes/clusters/ruth/obsidian/kustomization.yaml`, uncomment the maintenance component line:
   ```yaml
   components:
     - ../../../apps/services/obsidian/components/maintenance
   ```
2. Commit and push. Wait for ArgoCD to sync.
3. **Verify**:
   ```bash
   kubectl get deploy obsidian -n personal
   ```
   **Expected output**:
   ```text
   NAME       READY   UP-TO-DATE   AVAILABLE   AGE
   obsidian   0/0     0            0           30d
   ```
   *(Ensure READY shows `0/0`)*

### 3. Update & Apply Restore Configuration
1. Replace `BACKUP_NAME` in `restore.yaml` (at the bottom of this directory).
2. Apply the restore manifest:
   ```bash
   kubectl apply -f restore.yaml
   ```

### 4. Verify Velero Restore Completion
Verify the restore has finished:
```bash
kubectl get restore obsidian-restore -n backup -o jsonpath='{.status.phase}' && echo ""
```
**Expected output**:
```text
Completed
```

### 5. Copy Restored PVC Data to Live PVC
Since Velero restores to the `restore` namespace, we copy files from the restored volume back to the live volume:

1. Start a temporary pod in `personal` namespace mounting the live PVC:
   ```bash
   cat <<'EOF' | kubectl apply -f -
   apiVersion: v1
   kind: Pod
   metadata:
     name: pvc-mount
     namespace: personal
   spec:
     containers:
     - name: mount
       image: alpine
       command: ["sleep", "3600"]
       volumeMounts:
       - name: data
         mountPath: /config
     volumes:
     - name: data
       persistentVolumeClaim:
         claimName: obsidian-config
     restartPolicy: Never
   EOF
   ```
2. Start a temporary pod in `restore` namespace mounting the restored PVC:
   ```bash
   cat <<'EOF' | kubectl apply -f -
   apiVersion: v1
   kind: Pod
   metadata:
     name: pvc-mount
     namespace: restore
   spec:
     containers:
     - name: mount
       image: alpine
       command: ["sleep", "3600"]
       volumeMounts:
       - name: data
         mountPath: /config
     volumes:
     - name: data
       persistentVolumeClaim:
         claimName: obsidian-config
     restartPolicy: Never
   EOF
   ```
3. Wait for both pods to transition to Running:
   ```bash
   kubectl wait pod/pvc-mount -n personal --for=condition=Ready --timeout=60s
   kubectl wait pod/pvc-mount -n restore --for=condition=Ready --timeout=60s
   ```
   **Expected output**:
   ```text
   pod/pvc-mount condition met
   ```
4. Copy the data: `restore volume` -> `local workstation` -> `live volume`:
   ```bash
   kubectl cp restore/pvc-mount:/config ./obsidian-restore-data
   kubectl cp ./obsidian-restore-data personal/pvc-mount:/config
   ```
5. Clean up temporary workstation files and pods:
   ```bash
   kubectl delete pod pvc-mount -n personal
   kubectl delete pod pvc-mount -n restore
   rm -rf ./obsidian-restore-data
   ```

### 6. Disable Maintenance Mode
1. In `kubernetes/clusters/ruth/obsidian/kustomization.yaml`, comment out the maintenance component:
   ```yaml
   components:
     # - ../../../apps/services/obsidian/components/maintenance
   ```
2. Commit and push. ArgoCD will scale the live Obsidian pod back to `1`.

### 7. Verify Application Health
Check that the application has started and the pod is running successfully:
```bash
kubectl get deploy obsidian -n personal
kubectl get pods -n personal -l app=obsidian
```
**Expected output**:
```text
NAME                        READY   STATUS    RESTARTS   AGE
obsidian-769fb9584d-62swm   1/1     Running   0          30s
```

### 8. Cleanup
Once verified, clean up restore resources:
```bash
kubectl delete ns restore
kubectl delete restore obsidian-restore -n backup
```
