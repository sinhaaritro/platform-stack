# SSL Certificates Restore Runbook

**Use Case**: Any scenario — loss, corruption, deletion, or full rebuild of SSL TLS Certificates.

**Behavior**: Restores labeled Certificates and their TLS Secrets **in-place** across all namespaces using `existingResourcePolicy: update`. Cert-manager revalidates the restored keypair (dnsNames match) → stays Ready, **no new LE orders**.

> **Prerequisite**: Velero and Cert Manager must be running in the cluster. The restore can run as soon as Velero is up — it is order-independent (apps and cert-manager do not need to be running first).

---

## Runbook Steps

### 1. Identify Backup Name
Find the latest backup name from the `ssl-certs` schedule:
```bash
kubectl get backups.velero.io -n backup -l velero.io/schedule-name=ssl-certs --sort-by=.metadata.creationTimestamp
```

### 2. Restore

**Option A — CLI (no git change needed):**
```bash
velero restore create --from-backup <backup-name> --existing-resource-policy update
```

**Option B — Declarative (via GitOps):**
1. Edit `kubernetes/clusters/hyperion/velero/components/schedules/ssl-cert/restore.yaml` — replace `BACKUP_NAME` on line 7 with the identified backup name.
2. Push to git and let ArgoCD sync, or apply manually:
   ```bash
   kubectl apply -f kubernetes/clusters/hyperion/velero/components/schedules/ssl-cert/restore.yaml
   ```

### 3. Verify Restore Completion
```bash
kubectl get restore ssl-cert-restore -n backup -o jsonpath='{.status.phase}' && echo ""
```
**Expected**: `Phase: Completed` with no warnings or errors.

To inspect details if PartiallyFailed or Failed:
```bash
kubectl get restore ssl-cert-restore -n backup -o jsonpath='{.status}' | python3 -m json.tool
```

To see the Errors
```bash
kubectl get restore ssl-cert-restore -n backup -o json | python3 -c "import sys,json; d=json.load(sys.stdin); [print(json.dumps(v,indent=2)) for k,v in d.get('status',{}).items() if 'error' in k.lower() or 'warning' in k.lower()]"
kubectl logs -n backup -l app.kubernetes.io/name=velero --tail=50 | grep -i "ssl-cert-restore"
```

### 4. Verify Certificates Are Ready
Confirm all restored certificates are in Ready state:
```bash
kubectl get certificate -A -l backuplabel.certificate=true \
  -o custom-columns=NAMESPACE:.metadata.namespace,NAME:.metadata.name,READY:.status.conditions[0].status,NOT_AFTER:.status.notAfter
```
**Expected**: All show `READY: True` with the original `notAfter` timestamps (not freshly issued).

Confirm no new LE orders were created (should be 0):
If 0, then cert-manager made zero outgoing calls to Let's Encrypt when the cluster came up.
```bash
kubectl get orders.acme.cert-manager.io -A --no-headers | wc -l
```

### 5. Verify TLS Is Served
```bash
for h in alertmanager.hyperion.aritrosinha.dpdns.org \
         alloy.hyperion.aritrosinha.dpdns.org \
         loki.hyperion.aritrosinha.dpdns.org \
         longhorn.hyperion.aritrosinha.dpdns.org \
         mimir.hyperion.aritrosinha.dpdns.org \
         seaweedfs.hyperion.aritrosinha.dpdns.org \
         filer.seaweedfs.hyperion.aritrosinha.dpdns.org \
         s3.seaweedfs.hyperion.aritrosinha.dpdns.org \
         admin.seaweedfs.hyperion.aritrosinha.dpdns.org \
         volume.seaweedfs.hyperion.aritrosinha.dpdns.org \
         traefik.hyperion.aritrosinha.dpdns.org \
         grafana.hyperion.aritrosinha.dpdns.org \
         grafana-hyperion.strawslabs.com; do
  printf "%-55s %s\n" "$h" "$(curl -sI --max-time 10 https://$h | awk 'NR==1{print $2}')"
done
```
**Expected**: All hosts return `200`.

### 6. Traefik Boot-Order Race (if needed)
If any host shows `TRAEFIK DEFAULT CERT` instead of the real certificate, Traefik booted before the TLS secrets existed. Fix with a restart:
```bash
kubectl -n networking rollout restart deployment/traefik
```
Then re-run the curl loop from Step 5.

### 7. Cleanup (CLI restore only)
If you used the CLI restore (Option A), clean up the restore object:
```bash
kubectl delete restore ssl-cert-restore -n backup
```
If you used the declarative restore (Option B), reset `BACKUP_NAME` in `restore.yaml` and push to git.
```bash
kubectl apply -f kubernetes/clusters/hyperion/velero/components/schedules/ssl-cert/restore.yaml
```