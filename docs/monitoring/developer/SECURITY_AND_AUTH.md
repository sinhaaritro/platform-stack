# D3 — Security & Auth

| | |
|---|---|
| **Folder** | Developer |
| **Dashboard ID** | D3 |
| **Refresh** | 30s |
| **Audience** | You wearing the security hat — auth health, policy compliance, secrets management |

> **Purpose:** Unified security posture view covering the four security-relevant components on the platform: **Authentik** (identity provider / SSO), **Kyverno** (Kubernetes policy engine), **Sealed Secrets** (GitOps-safe secret encryption), and **External Secrets** (external secret store sync). This dashboard answers "is auth working, are policies being enforced, and are secrets in sync?" — the three pillars of platform security posture.

**← Back to [Dashboard Catalog](../README.md#-developer-3-dashboards)**

---

## Data Flow

```
Authentik (port 9300/metrics or custom endpoint)
  │
  ├──→ Alloy prometheus.scrape "authentik"          ← NEEDS TO BE ADDED
  │
Kyverno (port 8000/metrics, admission controller)
  │
  ├──→ Alloy prometheus.scrape "kyverno"            ← NEEDS TO BE ADDED
  │
Sealed Secrets controller (port 8080/metrics)
  │
  ├──→ Alloy prometheus.scrape "sealed-secrets"     ← NEEDS TO BE ADDED
  │
External Secrets Operator (port 8080/metrics)
  │
  ├──→ Alloy prometheus.scrape "external-secrets"   ← NEEDS TO BE ADDED
  │      │
  │      └──→ Mimir (prometheus.remote_write)
  │
  └──→ Loki (all four component logs, already scraped by Alloy)
```

> [!WARNING]
> **Blocker:** None of the four components are currently scraped by Alloy. All four need scrape blocks added to `custom-config`:
> 1. **Authentik** — Exposes Prometheus metrics natively (Django-based, uses `django-prometheus`). Check the actual metrics port in your Helm values.
> 2. **Kyverno** — Exposes admission controller metrics on port 8000. Includes policy violation counts, admission request latency, and webhook health.
> 3. **Sealed Secrets** — The controller exposes metrics on its `/metrics` endpoint. Includes unseal error counts and condition status.
> 4. **External Secrets** — The operator exposes sync status metrics. Includes sync success/failure counts per ExternalSecret resource.

---

## Dashboard Layout

Organized into **5 tabs**. Unlike SRE dashboards which drill down from a summary, D3 groups by security domain since each component has distinct failure modes and metrics.

---

### Tab 1: Security Posture at a Glance

> **Design:** Stat strip. An operator should know if any security component is degraded within 5 seconds.

| Panel | Type | Query (PromQL) | Thresholds | Rationale |
|-------|------|----------------|------------|-----------|
| **Authentik Up** | Stat | `up{job="authentik"}` | 1 🟢, 0 🔴 | Is the identity provider alive? If Authentik is down, no user can log into any service that uses SSO. |
| **Failed Logins (1h)** | Stat (red if >threshold) | `sum(increase(authentik_login_failed_total[1h]))` | <5 🟢, 5-20 🟡, >20 🔴 | Brute-force detection signal. A spike in failed logins could indicate a credential-stuffing attack or a misconfigured client. |
| **Kyverno Policy Violations (1h)** | Stat (red if >0) | `sum(increase(kyverno_policy_results_total{rule_result="fail"}[1h]))` | 0 🟢, 1-5 🟡, >5 🔴 | Policies exist to enforce security invariants. Violations mean something tried to deploy non-compliant resources — investigate whether it's a legitimate workload that needs an exception or an actual security issue. |
| **Sealed Secrets Healthy** | Stat | `sealed_secrets_controller_condition_info{condition="Synced"}` or equivalent | Synced 🟢, else 🔴 | Is the sealed-secrets controller able to decrypt SealedSecrets into Secrets? If this fails, new secret deployments via GitOps are broken. |
| **External Secrets Sync Errors** | Stat (red if >0) | `sum(external_secrets_sync_calls_error_total)` or `count(external_secrets_status{status!="SecretSynced"})` | 0 🟢, ≥1 🔴 | Are ExternalSecret resources successfully syncing from the external store? Sync failures mean pods may be running with stale or missing secrets. |

---

### Tab 2: Authentik (Identity & Auth)

> **Design:** Deep dive into the authentication layer. Authentik is the gateway to every service — its health directly impacts user experience.

| Panel | Type | Query | Rationale |
|-------|------|-------|-----------|
| **Login Rate (success vs failure)** | Time series (stacked) | `rate(authentik_login_total[5m])` split by `result` (success/failure) | Baseline auth traffic. A sudden drop in successful logins with flat failure rate means users can't reach the login page (upstream issue); a spike in failures with flat success means brute-force. |
| **Active Sessions** | Time series | `authentik_sessions_active` or equivalent gauge | How many users are currently authenticated? Useful for capacity planning and spotting session leaks (count climbing without corresponding login rate). |
| **Login Latency** | Time series | `rate(authentik_login_duration_seconds_sum[5m]) / rate(authentik_login_duration_seconds_count[5m])` | Slow logins frustrate users and may indicate database performance issues (Authentik queries PG14) — cross-reference with [B1 — PostgreSQL](../dba/POSTGRESQL.md). |
| **OAuth/OIDC Token Issuance** | Time series | `rate(authentik_token_issued_total[5m])` by provider | Per-provider token issuance rate. If Grafana's OIDC integration stops getting tokens, Grafana dashboards become inaccessible — this panel catches that before user complaints. |
| **Authentik Error Log Stream** | Logs panel | Loki: `{namespace="authentik", container=~"authentik.*"} \|= "ERROR" or \|= "error"` | Root-cause stream for auth failures, LDAP/SCIM sync issues, and flow configuration errors. |

---

### Tab 3: Kyverno (Policy Engine)

> **Design:** Policy enforcement health. Kyverno acts as an admission controller — if it fails, non-compliant resources can be created.

| Panel | Type | Query | Rationale |
|-------|------|-------|-----------|
| **Policy Results (pass/fail/warn)** | Time series (stacked) | `sum(rate(kyverno_policy_results_total[5m])) by (rule_result)` | The ratio of pass to fail shows how clean your deployments are. A sudden spike in failures after a policy update usually means the policy is too strict or a legitimate workload changed. |
| **Violations by Policy** | Table, sorted descending | `sum(increase(kyverno_policy_results_total{rule_result="fail"}[24h])) by (policy_name)` | Which specific policy is being violated most? Focuses remediation effort on the highest-impact policy. |
| **Violations by Namespace** | Bar gauge | `sum(increase(kyverno_policy_results_total{rule_result="fail"}[24h])) by (resource_namespace)` | Which namespace has the most violations? Often reveals a team or workload that needs attention. |
| **Admission Request Latency** | Time series | `histogram_quantile(0.95, sum(rate(kyverno_admission_review_duration_seconds_bucket[5m])) by (le))` | Kyverno sits in the admission webhook path — slow policy evaluation delays every `kubectl apply`. p95 above 1s is worth investigating. |
| **Kyverno Webhook Health** | Stat | `up{job="kyverno"}` combined with `kyverno_controller_reconcile_total` | Is the controller running and processing reconciliation? A downed controller means policies aren't being enforced on new resources. |

---

### Tab 4: Secrets Management

> **Design:** Covers both Sealed Secrets (GitOps encryption) and External Secrets (external store sync). These are the two mechanisms that get secrets into the cluster.

| Panel | Type | Query | Rationale |
|-------|------|-------|-----------|
| **Sealed Secrets Controller Status** | Stat | `up{job="sealed-secrets"}` | Is the controller running? If it's down, new SealedSecret resources won't be decrypted into usable Secrets. |
| **Unseal Errors** | Time series | `rate(sealed_secrets_controller_unseal_errors_total[5m])` | Unseal failures mean a SealedSecret was created with the wrong public key, or the controller's private key has rotated. Either way, the affected workload won't get its secret. |
| **External Secrets Sync Status** | Table | `external_secrets_status` with columns: Name, Namespace, Status, Last Sync Time | Per-ExternalSecret breakdown — shows exactly which secrets are synced and which are failing. A "SecretSyncedError" status needs immediate attention. |
| **External Secrets Sync Rate** | Time series | `rate(external_secrets_sync_calls_total[5m])` split by status (success/error) | Sync frequency and error rate over time. A flat line on success rate combined with climbing errors indicates a connectivity issue with the external secret store. |
| **Secrets Error Log Stream** | Logs panel | Loki: `{namespace=~"sealed-secrets\|external-secrets"} \|= "error" or \|= "ERROR"` | Combined error stream for both secrets controllers — typically surfaces certificate/key issues for sealed-secrets and API connectivity issues for external-secrets. |

---

### Tab 5: Active Alerts

> **Design:** Same pattern as all other dashboards.

| Panel | Type | Source | Rationale |
|-------|------|--------|-----------|
| **Firing Alerts Table** | Table | Alertmanager datasource, filtered to `alertgroup="security"` | Single pane for active security issues, color-coded by severity. |

#### Alert Rules (Mimir Ruler)

| Alert Name | PromQL Condition | For | Severity | Description |
|------------|------------------|-----|----------|-------------|
| `AuthentikDown` | `up{job="authentik"} == 0` | 2m | **Critical** | Identity provider is down — all SSO-protected services are inaccessible. |
| `AuthentikHighFailedLogins` | `sum(increase(authentik_login_failed_total[15m])) > 20` | 5m | **Warning** | High rate of failed login attempts — possible brute-force attack or misconfigured client. |
| `KyvernoPolicyViolation` | `increase(kyverno_policy_results_total{rule_result="fail"}[15m]) > 0` | 0m | **Warning** | A policy violation occurred — a non-compliant resource was attempted. |
| `KyvernoWebhookDown` | `up{job="kyverno"} == 0` | 2m | **Critical** | Kyverno controller is down — policies are not being enforced on new resources. |
| `SealedSecretsUnsealError` | `increase(sealed_secrets_controller_unseal_errors_total[15m]) > 0` | 0m | **Warning** | A SealedSecret failed to unseal — the affected workload won't get its secret. |
| `ExternalSecretsSyncFailing` | `external_secrets_sync_calls_error_total > 0` | 5m | **Critical** | An ExternalSecret resource is failing to sync — pods may have stale or missing secrets. |

---

**← Back to [Dashboard Catalog](../README.md#-developer-3-dashboards)** | **Previous: [D1 — Application Health](APPLICATION_HEALTH.md)** | **Next: [D2 — Log Explorer](LOG_EXPLORER.md)**
