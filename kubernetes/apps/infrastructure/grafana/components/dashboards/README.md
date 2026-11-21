# Grafana Dashboard Catalog

Reusable Grafana dashboard templates. Each dashboard is a **self-contained Kustomize component**: the JSON and its `kustomization.yaml` live in the same directory.

Clusters select the dashboards they want by listing component paths in `clusters/<cluster>/grafana/kustomization.yaml`. Nothing is copied; a dashboard exists once in this catalog.

## Layout

```
dashboards/
├── executive/<slug>/{kustomization.yaml,<dashboard>.json}
├── sre/<slug>/
├── developer/<slug>/
├── dba/<slug>/
└── platform/<slug>/
```

## Available templates

| Persona | Component path | ConfigMap | Folder |
|---|---|---|---|
| Executive | `executive/e1-platform-overview` | `grafana-dashboard-platform-overview` | Executive |
| Executive | `executive/e2-capacity-and-trends` | `grafana-dashboard-capacity-trends` | Executive |
| SRE | `sre/s1-backup-and-disaster-recovery` | `grafana-dashboard-backup-dr` | SRE / Operations |
| SRE | `sre/s2-cluster-and-node-health` | `grafana-dashboard-cluster-health` | SRE / Operations |
| SRE | `sre/s3-networking` | `grafana-dashboard-networking` | SRE / Operations |
| SRE | `sre/s4-storage` | `grafana-dashboard-storage` | SRE / Operations |
| SRE | `sre/s5-monitoring-self-health` | `grafana-dashboard-monitoring-self-health` | SRE / Operations |
| SRE | `sre/s6-external-infrastructure` | `grafana-dashboard-external-infra` | SRE / Operations |
| Developer | `developer/d1-application-health` | `grafana-dashboard-application-health` | Developer |
| Developer | `developer/d2-log-explorer` | `grafana-dashboard-log-explorer` | Developer |
| Developer | `developer/d3-security-auth` | `grafana-dashboard-security-auth` | Developer |
| Developer | `developer/d4-immich` | `grafana-dashboard-immich` | Developer |
| DBA | `dba/b1-postgresql` | `grafana-dashboard-postgresql` | DBA |
| DBA | `dba/b2-cache-and-document-stores` | `grafana-dashboard-cache-doc-stores` | DBA |
| Platform | `platform/node-exporter` | `grafana-dashboard-node-exporter` | (none) |
| Platform | `platform/loki` | `grafana-dashboard-loki` | (none) |

## Using a template in a cluster

```yaml
# clusters/<cluster>/grafana/kustomization.yaml
components:
  - ../../../apps/infrastructure/grafana/components/dashboards/developer/d2-log-explorer
  - ../../../apps/infrastructure/grafana/components/dashboards/sre/s5-monitoring-self-health
```

That is the whole mechanism. Include more paths to add more dashboards. Hyperion currently includes all sixteen; Elysia includes two as an example.

## Rules for adding or changing a template

1. **Never rename the ConfigMap.** Grafana's sidecar keys off the name; renaming causes the dashboard to disappear and be recreated. Add new dashboards with a new name instead.
2. **One dashboard per directory**, with `dashboard.json`-style file names preserved as the ConfigMap key.
3. **Use standard datasource UIDs**: `prometheus` (Mimir), `loki`, `alertmanager`. URLs live in the datasource components, never in a dashboard.
4. **No cluster-specific constants.** Use variables:
   - namespaces: `$namespace` (query variable over `kube_pod_info`), not `personal`
   - portal/external domains: `$domain`, a text variable whose template default is the placeholder `example.com`. The user sets it at runtime; if it is not set, portal links are intentionally broken.
5. **Folder** is set through the `grafana_folder` annotation in the component's `kustomization.yaml`.
6. **Validate locally** before committing:

```bash
kustomize build kubernetes/clusters/hyperion/grafana --enable-helm >/dev/null
kustomize build kubernetes/clusters/elysia/grafana --enable-helm >/dev/null
```

## Notes

- Portal dashboards (P1–P3) are documented in `docs/monitoring/portal/` but not yet implemented. When added, they belong in `portal/<slug>/` and must use `$domain`.
- The Grafana sidecar loads every ConfigMap labelled `grafana_dashboard=1`; the folder annotation determines where it appears.
