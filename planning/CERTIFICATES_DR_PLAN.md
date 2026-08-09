# Plan: Certificate Consolidation & DR-Ready Backup

> **Status:** Proposed — awaiting approval
> **Goal:** Eliminate re-issuance of TLS/SSL certificates after full disaster recovery
> (avoid Let's Encrypt rate limits and ~20min DNS01 propagation waits), consolidate
> certificate definitions, and make certs selectable for backup via label.

## Background
- The cluster has 2 wildcard `Certificate`s (in the cert-manager app, `networking` ns) that are issued but idle (no ingress references their secrets).
- ~15 per-app leaf certs (immich, authentik, grafana, ...) live in app namespaces and are NOT covered by the old `daily-ssl-certs` velero schedule (backed up `networking`-only, now deleted; renamed to `ssl-certs`).
- After DR, unbacked-up leaf certs would all re-issue: LE limit is 50 certs/registered-domain/week (~1 per 202 min refill); the ~20-min wait is DNS TTL propagation + cert-manager self-check via CoreDNS.
- Root cause: two mixed patterns (wildcard + per-app annotations) with no consistent convention.

## Target State
- One convention: **explicit per-app `Certificate` resources** in each app's cluster overlay, self-contained (ingress + certs, no patches, no annotations).
- A **self-contained dummy template** at `apps/infrastructure/grafana/components/ingress/`, using the self-signed issuer (`selfsigned-default`), referenced as-is by elysia (intentionally inert).
- Every cert labeled `backuplabel.certificate: "true"` (labels + `secretTemplate` labels) so velero backs up exactly the TLS certs + their Secrets.
- Restore = Certificates + Secrets back → cert-manager sees existing certs → **zero re-issue**.

## Phases

### Phase 1 — Template + Grafana migration (hyperion)
1. **Dummy template** — rewrite `apps/infrastructure/grafana/components/ingress/`:
   - `kustomization.yaml` (resources: `ingress-dummy.yaml`, `cert-dummy.yaml`)
   - `ingress-dummy.yaml`: `grafana-dummy`, host `grafana-dummy.example.com`, tls `grafana-dummy-tls`, no cert-manager annotation, comment = "copy to clusters/<name>/grafana/components/ingress"
   - `cert-dummy.yaml`: `Certificate grafana-dummy`, dnsNames `grafana-dummy.example.com`, issuer `selfsigned-default`, labels `backuplabel.certificate: "true"` + same in `secretTemplate`
   - elysia keeps referencing this folder → dummy ingress + self-signed cert, zero LE traffic.
2. **hyperion grafana** — `clusters/hyperion/grafana/components/ingress/`:
   - ONE **per-host Ingress per file**: `ingress-aritrosinha.yaml`, `ingress-strawslabs.yaml`
     (single host + single tls secret each — Traefik treats an ingress TLS block atomically, so
     one host's missing/pending cert must NOT blackout the other host)
   - `cert-aritrosinha.yaml`, `cert-strawslabs.yaml` (real hosts, issuer `letsencrypt-prod-*`,
     labels + secretTemplate)
   - Rewrite `kustomization.yaml` (resources only: 2 ingress + 2 cert)
   - Delete `patch-ingress.yaml`, `patch-remove-cluster-issuer-annotation.json`, `resource-certificate-*.yaml`
   - Remove `../../../apps/infrastructure/grafana/components/ingress` from `clusters/hyperion/grafana/kustomization.yaml`
   - The split is Ingress-only: Certificate names/secretNames unchanged → **no re-issuance, no wait, no LE quota**
3. **Unreference wildcards (keep folders)** in `apps/infrastructure/cert-manager/components/ssl/bundles/`:
   - `personal-prod`: drop the two `../../certificates/...` components
   - `personal-staging`: drop `../../certificates/wildcard-hyperion-staging`
   - The `certificates/` folder stays on disk (unrendered)
4. **Tests** — see Tests section below.

### Phase 2 — Roll out to other apps (hyperion)
For each app: alertmanager, alloy, authentik, couchdb, immich, loki, longhorn, mimir, obsidian (1 host each) + seaweedfs (5 hosts: seaweedfs, filer, s3, admin, volume):
- Copy template → `clusters/hyperion/<app>/components/ingress/`, real values + labels (`backuplabel.certificate: "true"`), issuer `letsencrypt-prod-aritrosinha`
- Remove shared `apps/.../components/ingress` reference (hyperion only) + obsolete host/annotation patches; atomic commit per app
- Keep shared placeholder folders as-is for other clusters (elysia/quanta)
- Exempt: `podinfo` (placeholder example domain) — documented exemption
- Verify per app: cert Ready, Traefik TLS, no annotation-created duplicate certs
- grafana certs already labeled in Phase 1

### Phase 3 — Backup + renewal speed (only after Phases 1–2 verified)
1. **Velero** — `clusters/hyperion/velero/components/schedules/ssl-cert/schedule.yaml`:
   - `includedNamespaces: ["*"]`, `includedResources: [secrets, certificates.cert-manager.io]`
   - `labelSelector: {backuplabel.certificate: "true"}`
   - `excludedResources: [certificaterequests.cert-manager.io, orders.acme.cert-manager.io, challenges.acme.cert-manager.io]`
   - Keep TTL 720h (30d), storageLocation `aws`
   - Document restore: certs + secrets back → zero re-issuance
2. **Uncomment** `dns-recursors` in `clusters/hyperion/cert-manager/kustomization.yaml` (propagation self-check via 1.1.1.1:53/8.8.8.8:53, bypasses CoreDNS cache for legit renewals)

## Tests
- **Test 1 — GitOps (in-place, per phase):**
  - `kustomize build` on affected overlays (no errors, no unmatched-patch warnings)
  - Apply via GitOps: verify wildcard certs removed; `grafana-cert-*` Ready; no unexpected LE orders in cert-manager logs; Traefik serves TLS on real hosts
- **Test 2 — Full DR (from-scratch VMs):**
  - Rebuild VMs → bootstrap cluster → GitOps applies stack
  - With Phase 3 in place: restore `ssl-certs` → verify **zero new issuances** (no new CertificateRequests/Orders; cert timestamps unchanged)
  - **DR runbook step (boot-order race, observed 2026-08-09):** after restoring certs/secrets, run
    `kubectl -n networking rollout restart deployment/traefik` then verify SNI:
    `echo | openssl s_client -connect <lb-ip>:443 -servername <host> 2>/dev/null | openssl x509 -noout -subject`
    (Traefik must boot AFTER the TLS secrets exist; a secret that appears later is not adopted and
    it serves its fallback "TRAEFIK DEFAULT CERT" — which breaks strict tunnel verification → 502.
    Per-host ingress files (Phase 1) keep this failure scoped to the affected host only.)
  - Without backup: verify fresh issuance path works (use STAGING issuer to spare quota)
  - **Test 2 — Append: LE "5-per-identifier" limit (observed 2026-08-09, live cluster):**
    - **Symptom:** `grafana-cert-aritrosinha` stuck: order `errored`,
      `429 urn:ietf:params:acme:error:rateLimited: too many certificates (5) already issued for
      this exact set of identifiers in the last 168h0m0s`, `retry after 2026-08-09 10:21:34 UTC`.
    - **Cause:** 5 LE certificates issued for the IDENTICAL dnsName `grafana.hyperion.aritrosinha.dpdns.org`
      within 7 days — result of repeated Certificate delete→recreate cycles during the migration.
      This is the **5 per exact-identifier per 168h** limit, independent of the 50-per-domain limit.
    - **Measured outcome:** one identifier rate-limited → that cert can't complete until the
      Retry-After timestamp; cert-manager auto-retries (order returns to `valid` within minutes of the
      deadline). Other identifiers (strawslabs) were unaffected — a one-cert, one-time delay, not a reset.
    - **How to detect (on the next rebuild):** watch order state + Retry-After —
      `kubectl -n <ns> get orders.acme.cert-manager.io`,
      `kubectl get events -n <ns> | grep -i 429`
    - **How to avoid burning it:** one-shot renames (pre-seed secrets → never delete+recreate the
      same dns within 7 days); assert the existing cert for the identifier still exists before
      re-creating; NEVER manually re-create a Certificate that a previous git state already deleted.

## DR Drill Checklist (rebuild → restore → verify)

Goal: prove (A) the grafana backup carries its secrets/certs after a full rebuild, and
(B) **every** TLS endpoint serves the restored certs (SSL works for all apps).

> Sequencing note: Argo CD has **no cross-Application ordering** (sync-waves are intra-app only),
> so "restore before cert-manager runs" cannot be enforced via the ApplicationSet. Instead the
> restore is made **order-independent** via `existingResourcePolicy: update` on the
> `ssl-cert-restore` Restore CR (Velero ≥1.11; chart 12.1.0 in use): on a rebuild it overwrites
> any freshly-issued certs/secrets with the backup versions; cert-manager revalidates the
> restored keypair (dnsNames match) → stays Ready, **no new LE orders**.
>
> Stats for the drill: 12 live certs (alertmanager, alloy, loki, longhorn, mimir, seaweedfs×5,
> traefik-dashboard, grafana×2) + grafana credentials secret; dormant apps (authentik, couchdb,
> immich, obsidian) don't exist until re-enabled.

### 0. Preconditions
- Nightly `ssl-certs` schedule has run; note the latest backup name: `velero backup get | head`
- Velero ≥1.11 (cluster runs chart 12.1.0 → server v1.17, OK)

### 1. Baseline snapshot (BEFORE rebuild)
```bash
kubectl get certificate -A -o jsonpath='{range .items[*]}{.metadata.namespace}/{.metadata.name} {.status.notAfter}{"\n"}{end}' | sort > /tmp/baseline-certs.txt
kubectl get secret -A -l backuplabel.certificate=true -o name | sort > /tmp/baseline-secrets.txt
for s in $(kubectl get secret -A -l backuplabel.certificate=true -o name); do
  ns="${s%%/*}"; name="${s##*/}"
  echo "${ns}/${name} $(kubectl -n "$ns" get secret "$name" -o json | jq -r '.data["tls.crt"]' | base64 -d | sha256sum | awk '{print $1}')"
done | sort > /tmp/baseline-fingerprints.txt
curl -sI https://grafana.hyperion.aritrosinha.dpdns.org > /tmp/baseline-grafana-http.txt  # sanity: all reachable now
```

### 2. Backup-side verification (on the live cluster, before rebuild)
```bash
velero backup describe <backup-name> --details | grep -E "Namespaces|Resources|Items"
velero backup describe <backup-name> --details | grep -E "secret|Certificate" | head   # spot-check
```
Every labeled secret + Certificate must appear as an item.

### 3. Rebuild + restore
1. Rebuild cluster → bootstrap Argo CD.
2. As soon as Velero is up (it syncs in the core waves): apply the restore —
   ```bash
   # declarative (from git, after setting backupName in ssl-cert/restore.yaml) or CLI:
   velero restore create --from-backup <backup-name> --existing-resource-policy update
   velero restore get    # wait for Phase: Completed
   velero restore describe <restore-name> | grep -iE "warn|err"   # expect no per-item failures
   ```
3. Let Argo CD finish syncing apps (no ordering work needed thanks to `update` policy).
4. If Traefik booted before its TLS secrets existed → SNI fallback to the default cert; restart once:
   `kubectl -n networking rollout restart deployment/traefik` (see Test 2 boot-order race).

### 4. Check A — grafana backup worked
```bash
kubectl get secret -n monitoring -l backuplabel.certificate=true   # grafana *-tls + grafana creds secret present
kubectl get certificate -n monitoring grafana-cert-aritrosinha grafana-cert-strawslabs \
  -o custom-columns=NAME:.metadata.name,READY:.status.conditions[0].status,NOT_AFTER:.status.notAfter
kubectl get certificate -A -o jsonpath='{range .items[*]}{.metadata.namespace}/{.metadata.name} {.status.notAfter}{"\n"}{end}' | sort \
  | diff /tmp/baseline-certs.txt -   # notAfter must match (expect no diff)
kubectl logs -n monitoring deployment/grafana --tail=50 | grep -iE "error|warn" || true   # boots clean
# login page reachable + restored credentials work
```

### 5. Check B — SSL for all hosts
```bash
kubectl get certificate -A -o jsonpath='{range .items[*]}{.metadata.namespace}/{.metadata.name} {.status.conditions[?(@.type=="Ready")].status} {.status.notAfter}{"\n"}{end}' | sort > /tmp/post-certs.txt
diff /tmp/baseline-certs.txt /tmp/post-certs.txt      # READY: no diff → zero re-issuance
kubectl get orders.acme.cert-manager.io -A --no-headers | wc -l          # expect 0 new orders (after initial install)
for h in alertmanager alloy loki longhorn mimir \
         seaweedfs filer.seaweedfs s3.seaweedfs admin.seaweedfs volume.seaweedfs \
         traefik grafana grafana-hyperion.strawslabs.com; do
  printf "%-45s %s\n" "$h" "$(curl -sI --max-time 10 https://$h | awk 'NR==1{print $2}')"
done                                           # every host: 200
echo | openssl s_client -connect <lb-ip>:443 -servername <host> 2>/dev/null | openssl x509 -noout -subject
```
Fingerprint diff (step 1 files) must match as well — the definitive proof the **backup's keypair**
was restored (a freshly issued cert would differ).

### 6. Post-drill housekeeping
- Confirm labels survived on cert+secret (needed for next backup): `kubectl get secret -A -l backuplabel.certificate=true | wc -l` == baseline-secrets.txt count
- If a host shows "TRAEFIK DEFAULT CERT" → run step 3.4 restart, re-curl
- Record the drill date + any re-issued identifiers in BACKLOG.md

## Risks
| Risk | Mitigation |
|---|---|
| One-time fresh LE issuance on grafana rename (Phase 1) | Trivial quota cost (2 certs); acceptable |
| Dummy template applied by elysia | Self-signed + non-resolving dummy host: inert, zero LE traffic (by design) |
| Per-app migration TLS gap | Atomic per-app commit; quick apply window |
| Duplicate certs during transition (annotation + explicit) | Remove annotation in the SAME commit as adding the cert |
| kustomize silently ignoring unmatched patches | All cluster-local ingress components become patch-free (resources only) |
| Label drift (missed certs in backup) | Labels added at cert creation; grafana covered in Phase 1; verify via `kubectl get secrets -l backuplabel.certificate=true` |
| DNS-01 validation failures on real certs during DR test | Use staging issuer for the from-scratch test; keep 5-failures/hr limit in mind |
| LE 5 certs / exact identifier / 7d (encountered live 2026-08-09) | One-shot renames only; pre-seed secrets; don't delete+recreate same dns within 7 days; treat 429 + Retry-After as auto-resolving when possible |

## Notes
- TTL stays 30 days (not 90d as initially considered) — decided; keep consistent across schedules
- Label key chosen: `backuplabel.certificate: "true"` (`false`/absent = not backed up)
- `certificates/` folder in the cert-manager app is **unreferenced but kept** (no deletion)
- Elysia's grafana ingress/certs become dummy until elysia gets its own copy (accepted)
- copyparty: no ingress wired in hyperion → exempt; gets a cert only when its ingress is enabled
- No new operators/tools required (no ESO involvement; reuse existing cert-manager + velero)
- Related backlog item: BACKLOG.md "New 30day backup schedule for SSL cert"