# D2 — Log Explorer

| | |
|---|---|
| **Folder** | Developer |
| **Dashboard ID** | D2 |
| **Refresh** | 30s |
| **Audience** | You wearing the developer hat — log investigation, error hunting, cross-namespace search |

> **Purpose:** Centralized log search across all namespaces via Loki. Unlike the other dashboards which embed small log panels for specific components, D2 is a full-featured log exploration tool — the Grafana equivalent of `kubectl logs` but with filtering, aggregation, and pattern matching across the entire cluster. This is a pure query-building exercise; all Loki data is already flowing.

**← Back to [Dashboard Catalog](../README.md#-developer-3-dashboards)**

---

## Data Flow

```
All pods across all namespaces
  │
  └──→ Alloy log collection (DaemonSet)  ← ALREADY FLOWING ✅
       │
       └──→ Loki (log storage)
            │
            └──→ Grafana Loki datasource
```

> [!NOTE]
> **No new scrape blocks or exporters needed.** Alloy is already shipping logs from every pod to Loki. D2 is entirely about building useful LogQL queries and presenting them in a developer-friendly layout with pre-built filters and saved patterns.

---

## Dashboard Layout

D2 is **not tabbed** — it uses a single continuous layout optimized for interactive log investigation. The design follows the "funnel" pattern: start wide (cluster-level overview), narrow down (namespace → pod → container), then investigate (raw logs + pattern matching).

---

### Section 1: Log Volume Overview

> **Design:** Understand the shape of log output across the cluster before diving into specific logs.

| Panel | Type | Query (LogQL) | Rationale |
|-------|------|---------------|-----------|
| **Log Volume Heatmap** | Heatmap (time × namespace) | `sum(count_over_time({namespace=~".+"}[5m])) by (namespace)` | Which namespaces are producing the most logs? A sudden spike in one namespace usually means an error loop or a verbose debug setting left on. The heatmap makes time-based patterns (e.g., backup-time log spikes) immediately visible. |
| **Error Rate by Namespace** | Time series (stacked) | `sum(count_over_time({namespace=~".+"} \|= "error" or \|= "ERROR" [5m])) by (namespace)` | Cross-namespace error comparison. If `immich` normally produces 2 errors/min but jumps to 200, this panel shows the spike in context of other namespaces — is it platform-wide or app-specific? |
| **Log Volume Total** | Stat | `sum(count_over_time({namespace=~".+"}[1h]))` | Aggregate log volume over the past hour. Useful as a Loki capacity-planning signal — if this number keeps growing, retention or ingestion limits may need adjustment. |
| **Top 10 Log-Heavy Pods** | Table, sorted descending | `topk(10, sum(count_over_time({namespace=~".+"}[1h])) by (pod))` | Which specific pods are generating the most logs? Often reveals a single noisy pod that should have its log level turned down to reduce Loki storage costs. |

---

### Section 2: Interactive Log Search

> **Design:** The core of D2 — a configurable log panel with Grafana variables for filtering. Variables: `$namespace`, `$pod`, `$container`, `$search` (free-text), `$level` (error/warn/info/debug).

| Panel | Type | Query | Rationale |
|-------|------|-------|-----------|
| **Live Log Stream** | Logs panel (live tail) | `{namespace=~"$namespace", pod=~"$pod", container=~"$container"} \|~ "$search" \| logfmt or json \| level=~"$level"` | The main log viewer. Variables at the top let you progressively filter: start with a namespace, narrow to a pod, then search for a keyword. Supports both `logfmt` and `json` parsing for structured logs. |
| **Log Context Panel** | Logs panel (surrounding lines) | Same query with `\| line_format` for context extraction | Shows surrounding log lines for a selected entry — useful for tracing the sequence of events leading to an error without switching to `kubectl logs --previous`. |

---

### Section 3: Pre-Built Query Patterns

> **Design:** Saved LogQL queries for common investigation patterns. Each panel is a pre-configured log search that answers a specific question.

| Panel | Type | Query | Purpose |
|-------|------|-------|---------|
| **OOM Kill Events** | Logs panel | `{namespace=~".+"} \|~ "OOM\|oom\|Out of memory\|killed process"` | Surfaces OOM kills across the cluster — correlates with the OOM kill stat on [S2 Tab 1](../sre/CLUSTER_AND_NODE_HEALTH.md#tab-1-fleet-health-at-a-glance) but provides the actual log context (which process, how much memory). |
| **Connection Refused / Timeout** | Logs panel | `{namespace=~".+"} \|~ "connection refused\|ECONNREFUSED\|context deadline exceeded\|timeout"` | Network connectivity issues between services — the most common inter-service failure pattern. |
| **Permission Denied / Auth Failures** | Logs panel | `{namespace=~".+"} \|~ "permission denied\|unauthorized\|403\|401\|access denied"` | Security-relevant log entries — failed auth attempts, RBAC denials, filesystem permission errors. |
| **Crash / Panic / Fatal** | Logs panel | `{namespace=~".+"} \|~ "panic\|FATAL\|fatal\|segfault\|signal: killed"` | Application crashes that may not result in a pod restart (e.g., a goroutine panic caught by a recover, or a subprocess crash). |
| **Database Errors** | Logs panel | `{namespace=~".+"} \|~ "deadlock\|lock timeout\|connection pool\|too many connections\|SQLSTATE"` | Database-related errors across all apps — complements [B1 — PostgreSQL](../dba/POSTGRESQL.md) by showing the application-side error messages that metrics alone don't capture. |
| **Certificate / TLS Errors** | Logs panel | `{namespace=~".+"} \|~ "certificate\|x509\|tls\|SSL\|handshake"` | TLS-related errors — expired certs, wrong CA, handshake failures. Complements [S3 Tab 3](../sre/NETWORKING.md#tab-3-tls--certificates-cert-manager). |

---

**← Back to [Dashboard Catalog](../README.md#-developer-3-dashboards)** | **Previous: [D1 — Application Health](APPLICATION_HEALTH.md)**
