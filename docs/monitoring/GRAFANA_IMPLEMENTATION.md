# Grafana Implementation Guide

> How dashboards are delivered, organized, and managed in this platform.

This document covers the **generic implementation mechanics** — the sidecar pattern, ConfigMap structure, Kustomize layout, and folder annotations that apply to every dashboard. For the overall vision and dashboard catalog, see [README.md](README.md). For individual dashboard details, see each dashboard's dedicated documentation file.

---

## Dashboard Delivery: Sidecar Pattern

Each dashboard is a **ConfigMap** in the `monitoring` namespace. The Grafana sidecar container automatically detects and loads them using a label selector.

### How It Works

```
┌──────────────────────────────────────────┐
│  ConfigMap (monitoring namespace)        │
│  ├── Label: grafana_dashboard: "1"       │  ← Sidecar watches for this
│  ├── Annotation: grafana_folder: "..."   │  ← Determines Grafana folder
│  └── Data: dashboard-name.json           │  ← Full Grafana dashboard JSON
│                                          │
│         ▼ (Sidecar auto-detects)         │
│                                          │
│  Grafana Sidecar Container               │
│  └── Mounts dashboard JSON into Grafana  │
│                                          │
│         ▼                                │
│                                          │
│  Grafana UI                              │
│  └── Dashboard appears in the assigned   │
│      folder, ready to use                │
└──────────────────────────────────────────┘
```

### Key Points

- **No manual import required** — push ConfigMap → dashboard appears in Grafana automatically
- **Label** `grafana_dashboard: "1"` is the trigger — the sidecar ignores ConfigMaps without it
- **Annotation** `grafana_folder` controls which Grafana folder the dashboard appears in
- **Namespace** must be `monitoring` (where Grafana and its sidecar are deployed)

---

## ConfigMap Structure

Each dashboard is delivered as a Kustomize Component:

```yaml
apiVersion: kustomize.config.k8s.io/v1alpha1
kind: Component

configMapGenerator:
  - name: grafana-dashboard-backup-dr          # Unique ConfigMap name
    namespace: monitoring                       # Must match Grafana namespace
    files:
      - backup-dr.json                          # Dashboard JSON file
    options:
      disableNameSuffixHash: true               # Stable name, no hash suffix
      labels:
        grafana_dashboard: "1"                  # Sidecar trigger label
      annotations:
        grafana_folder: "SRE / Operations"      # Grafana folder assignment
```

### Folder Annotations

| Grafana Folder | Annotation Value | Dashboards |
|----------------|------------------|------------|
| Portal | `grafana_folder: "Portal"` | P1, P2, P3 |
| Executive | `grafana_folder: "Executive"` | E1, E2 |
| SRE / Operations | `grafana_folder: "SRE / Operations"` | S1, S2, S3, S4, S5, S6 |
| Developer | `grafana_folder: "Developer"` | D1, D2, D3 |
| DBA | `grafana_folder: "DBA"` | B1, B2 |

### Access Control

Folder-level access is controlled via **Authentik → Grafana RBAC**:
- Authentik groups map to Grafana teams/roles
- Each Grafana folder has team-based permissions
- Different Authentik groups see different folders

---

## Kustomize File Tree

All dashboard ConfigMaps live under:

```
kubernetes/apps/infrastructure/grafana/components/dashboards/
├── kustomization.yaml                # Lists all dashboard ConfigMaps
├── dashboard-node-exporter.yaml      # (existing)
├── dashboard-loki.yaml               # (existing)
├── dashboard-seaweedfs.yaml          # (existing — currently empty {})
│
│── # Phase 1
├── dashboard-backup-dr.yaml          # S1 — Backup & Disaster Recovery
│
│── # Phase 2
├── dashboard-cluster-health.yaml     # S2 — Cluster & Node Health
├── dashboard-platform-overview.yaml  # E1 — Platform Overview
│
│── # Phase 3
├── dashboard-storage.yaml            # S4 — Storage (replaces empty seaweedfs)
├── dashboard-networking.yaml         # S3 — Networking & Ingress
│
│── # Phase 4
├── dashboard-postgresql.yaml         # B1 — PostgreSQL
├── dashboard-cache-docstores.yaml    # B2 — Cache & Document Stores
│
│── # Phase 5
├── dashboard-app-health.yaml         # D1 — Application Health
├── dashboard-security-auth.yaml      # D3 — Security & Auth
│
│── # Phase 6
├── dashboard-log-explorer.yaml       # D2 — Log Explorer
├── dashboard-monitoring-health.yaml  # S5 — Monitoring Self-Health
├── dashboard-capacity-trends.yaml    # E2 — Capacity & Trends
│
│── # Phase 7
├── dashboard-external-infra.yaml     # S6 — External Infrastructure
│
│── # Phase 8
├── dashboard-portal-admin.yaml       # P3 — Home — Admin
├── dashboard-portal-trusted.yaml     # P2 — Home — Trusted
└── dashboard-portal-public.yaml      # P1 — Home — Public
```

---

## Dashboard JSON Conventions

All dashboard JSON files follow these conventions:

| Property | Convention |
|----------|-----------|
| **uid** | Stable, unique, human-readable (e.g., `backup-dr`, `cluster-health`) |
| **title** | Matches the dashboard name in the catalog (e.g., "Backup & Disaster Recovery") |
| **tags** | Include the Grafana folder name + dashboard ID (e.g., `["sre", "s1", "backup"]`) |
| **refresh** | Match the persona's refresh rate (Executive: 1m, SRE: 30s, DBA: 15s) |
| **time range** | Default to `now-6h` for operational, `now-30d` for trends |
| **templating** | Use Grafana variables for node, namespace, pod filters where applicable |
| **annotations** | Include Alertmanager annotations layer for overlaying alert events on graphs |
| **links** | Cross-link to related dashboards (e.g., S2 links to E1 for executive view) |

---

## Alerting Pattern

Alerting is configured through **Mimir Ruler**, not Grafana's built-in alerting:

```
PromQL Alert Rules (Mimir Ruler)
  │
  ├── Recording rules (pre-aggregation for dashboard queries)
  ├── Alerting rules (threshold → fire)
  │
  └──→ Alertmanager (routing, dedup, silencing)
       ├── Stub receivers (no creds yet — routes to void)
       │   ├── Email (SMTP)
       │   ├── Webhook (Slack/Discord)
       │   └── Push (ntfy/Gotify/Pushover)
       │
       └──→ Dashboard "Firing Alerts Table" panels
            (each dashboard has an Active Alerts tab)
```

Each dashboard's detail doc lists the specific alert rules that belong to its domain.
