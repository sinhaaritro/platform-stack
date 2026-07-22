## Networking & Ingress (Dashboard S3)

**Folder:** SRE / Operations
**Refresh:** 30s
**Audience:** You wearing the ops hat — ingress troubleshooting, certificate management, DNS/tunnel health.

> **Purpose:** Comprehensive visibility into everything between "a request leaves the internet" and "a request reaches a pod" — Traefik (ingress), cert-manager (TLS), MetalLB (L2/BGP load balancing), and external-dns/Cloudflare tunnel (DNS + edge). This is also the dashboard that backfills the two placeholder panels left on the Executive Platform Overview (E1): certificate expiry countdown and the ingress request sparkline.

---

### Data Flow for Networking Metrics

```
Traefik (port 9100/metrics, or 8080 depending on chart)
  │
  ├──→ Alloy prometheus.scrape "traefik"        ← NEEDS TO BE ADDED
  │
cert-manager (port 9402/metrics)
  │
  ├──→ Alloy prometheus.scrape "cert-manager"   ← NEEDS TO BE ADDED
  │
MetalLB speaker/controller (port 7472/metrics)
  │
  ├──→ Alloy prometheus.scrape "metallb"        ← NEEDS TO BE ADDED
  │
external-dns (port 7979/metrics)
  │
  ├──→ Alloy prometheus.scrape "external-dns"   ← NEEDS TO BE ADDED
  │
Cloudflare Tunnel (cloudflared, port 2000/metrics)
  │
  ├──→ Alloy prometheus.scrape "cloudflared"    ← NEEDS TO BE ADDED (may land here or under S6/External Infra — see note below)
  │      │
  │      └──→ Mimir (prometheus.remote_write)
  │
  └──→ Loki (Traefik access logs + cert-manager controller logs, already scraped by Alloy)
```

> [!WARNING]
> **Blocker:** None of the five components above are currently scraped by Alloy. This is the largest single batch of new scrape blocks in the plan so far — five separate targets need to be added to `custom-config` before any panel on this dashboard shows data. Recommend doing this as one PR (all five scrape blocks together) since they share the same Alloy config file and testing pass.

> [!NOTE]
> **Cloudflare Tunnel placement:** `cloudflared` metrics could arguably live on S6 (External Infrastructure, Phase 7) since Cloudflare is an external service. This plan keeps tunnel *health* (is it connected, latency, error rate) on S3 because it's part of the request path for every ingress request today — but moves Cloudflare *account-level* data (threats blocked, analytics, cost) to S6 in Phase 7, where it belongs alongside the rest of the external-service dashboards. Worth confirming this split matches your mental model before building.

---

### Dashboard Layout: S3 — Networking & Ingress

Organized into **5 tabs**, same "glance first, drill down after" pattern as S1/S2/S4.

---

#### Tab 1: Health at a Glance

> **Design:** Stat strip. An operator should know if ingress, TLS, or DNS is broken within 5 seconds — before users start reporting "the site is down."

| Panel | Type | Query (PromQL) | Thresholds | Rationale |
|-------|------|----------------|------------|-----------|
| **Ingress Request Error Rate** | Stat (%) | `sum(rate(traefik_service_requests_total{code=~"5.."}[5m])) / sum(rate(traefik_service_requests_total[5m])) * 100` | <1% 🟢, 1-5% 🟡, >5% 🔴 | The single most important ingress number — if this is climbing, something behind Traefik is unhealthy, regardless of which service. |
| **Certificates Expiring (<14d)** | Stat (red if >0) | `count(certmanager_certificate_expiration_timestamp_seconds - time() < 14 * 86400)` | 0 🟢, 1-2 🟡, ≥3 🔴 | Catches renewal failures *before* a cert actually expires and breaks TLS for users — cert-manager renewal failures are often silent until this point. |
| **MetalLB Speakers Healthy** | Stat (fraction) | `sum(up{job="metallb", component="speaker"}) / count(up{job="metallb", component="speaker"})` | 100% 🟢, <100% 🔴 | If a speaker is down on a node, any LoadBalancer IP announced from that node stops being reachable — this is your L2 failover health check. |
| **Cloudflare Tunnel Connected** | Stat (up/down) | `cloudflared_tunnel_ha_connections` (>0 means at least one active edge connection) | ≥2 🟢, 1 🟡, 0 🔴 | Zero connections means the entire tunnel — and everything exposed through it — is unreachable from outside. |
| **DNS Sync Errors (1h)** | Stat (red if >0) | `sum(increase(external_dns_registry_errors_total[1h]))` | 0 🟢, ≥1 🔴 | external-dns failing to sync means new/changed ingress hostnames silently never get a DNS record. |

---

#### Tab 2: Traefik Ingress Traffic (RED Method)

> **Design:** Rate, Errors, Duration — the standard method for request-driven services, per Traefik router/service.

| Panel | Type | Query | Rationale |
|-------|------|-------|-----------|
| **Request Rate (per router)** | Time series | `sum(rate(traefik_router_requests_total[5m])) by (router)` | Baseline traffic shape per exposed app — useful both for anomaly detection (a sudden spike could be a scraper or an attack) and for the E1 ingress sparkline this feeds. |
| **Error Rate (per service, 4xx/5xx split)** | Time series (stacked) | `sum(rate(traefik_service_requests_total{code=~"4.."}[5m])) by (service)` and same for `5..` | Separates client errors (4xx — often just bad requests or expired links) from server errors (5xx — your problem) per backend service. |
| **Request Latency (p50/p95/p99)** | Time series | `histogram_quantile(0.95, sum(rate(traefik_service_request_duration_seconds_bucket[5m])) by (le, service))` (repeat for p50, p99) | Latency percentiles catch slow backends before they time out entirely — p99 in particular surfaces the "some requests are fine, some hang" pattern that averages hide. |
| **Open Connections** | Time series | `traefik_entrypoint_open_connections` | High or climbing connection counts with flat request rate usually indicates slow or hung backends holding connections open rather than a traffic increase. |
| **Traefik Access Log Errors** | Logs panel | Loki: `{namespace="traefik", container="traefik"} \|= "level=error"` | Root-cause stream for router/middleware misconfigurations that don't necessarily show up as a clean metric (e.g., bad TLS SNI routing, middleware chain errors). |

---

#### Tab 3: TLS & Certificates (cert-manager)

> **Design:** This tab directly backfills the "Certificate Expiry Countdown" placeholder panel on E1 once built.

| Panel | Type | Query | Rationale |
|-------|------|-------|-----------|
| **Certificate Expiry Table** | Table, sorted ascending by time-to-expiry | `certmanager_certificate_expiration_timestamp_seconds` joined with certificate name/namespace | The full list behind the Tab 1 stat — exactly which certificate is closest to expiring and in which namespace, so you know where to look before it becomes urgent. |
| **Certificate Ready Status** | Stat (fraction) | `sum(certmanager_certificate_ready_status{condition="True"}) / count(certmanager_certificate_ready_status)` | Ready ≠ not-expiring — a cert can be "not ready" immediately after a renewal attempt fails, which is an earlier warning sign than the expiry countdown. |
| **Renewal Attempts & Failures** | Time series | `rate(certmanager_certificate_renewal_attempts_total[1h])` vs `rate(certmanager_certificate_renewal_failures_total[1h])` (or equivalent controller sync error metric) | Distinguishes "cert-manager hasn't tried yet" from "cert-manager tried and failed" — the latter needs investigation (ACME rate limits, DNS-01 challenge failures, etc.), the former just needs time. |
| **ACME Challenge Status** | Table | `certmanager_certificate_request_status` filtered to pending/failed | Surfaces stuck HTTP-01/DNS-01 challenges specifically — the most common real-world cause of renewal failures in this kind of home/self-hosted setup. |

---

#### Tab 4: MetalLB & DNS/Tunnel

> **Design:** The layer below Traefik — how traffic physically reaches the cluster at all.

| Panel | Type | Query | Rationale |
|-------|------|-------|-----------|
| **MetalLB Speaker Status (per node)** | Multi-stat | `up{job="metallb", component="speaker"}` | Per-node breakdown behind the Tab 1 fraction — tells you exactly which node's speaker is down. |
| **IP Pool Usage** | Bar gauge | `metallb_allocator_addresses_in_use_total / metallb_allocator_addresses_total` per pool | Running out of addresses in a MetalLB pool silently blocks new LoadBalancer services from getting an IP — worth catching before you try to add a new exposed service and it just hangs in Pending. |
| **BGP/L2 Advertisement Status** | Table | `metallb_speaker_announced` per service/node | Confirms each LoadBalancer IP is actually being announced from a healthy node — a service can have an IP assigned but not actually be announced anywhere, which looks identical to "assigned and working" unless you check this. |
| **external-dns Sync Rate & Errors** | Time series | `rate(external_dns_registry_endpoints_total[5m])`, `rate(external_dns_registry_errors_total[5m])` | Confirms DNS records are actually being created/updated as ingress objects change, not just that the controller pod is up. |
| **Cloudflare Tunnel Connections & Latency** | Time series | `cloudflared_tunnel_ha_connections`, `cloudflared_tunnel_request_errors`, `cloudflared_tunnel_response_by_code` | Tunnel-specific health — connection count dropping to 1 (from a typical 2-4) is an early sign of edge instability before it drops to 0 and the whole tunnel goes down. |

---

#### Tab 5: Active Alerts

> **Design:** Same pattern as S1/S2/S4 — a single table of currently firing networking alerts, backed by Mimir Ruler → Alertmanager.

| Panel | Type | Source | Rationale |
|-------|------|--------|-----------|
| **Firing Alerts Table** | Table | Alertmanager datasource, filtered to `alertgroup="networking"` (covers Traefik, cert-manager, MetalLB, DNS, tunnel) | Single pane for active networking issues, color-coded by severity. |

##### Alert Rules to Configure (Mimir Ruler)

| Alert Name | PromQL Condition | For | Severity | Description |
|------------|-------------------|-----|----------|-------------|
| `TraefikHighErrorRate` | `sum(rate(traefik_service_requests_total{code=~"5.."}[5m])) / sum(rate(traefik_service_requests_total[5m])) > 0.05` | 5m | **Critical** | More than 5% of ingress requests are server errors — a backend is unhealthy. |
| `TraefikHighLatency` | `histogram_quantile(0.95, sum(rate(traefik_service_request_duration_seconds_bucket[5m])) by (le)) > 2` | 10m | **Warning** | p95 request latency over 2s cluster-wide — investigate slow backends. |
| `CertificateExpiringSoon` | `certmanager_certificate_expiration_timestamp_seconds - time() < 7 * 86400` | 1h | **Critical** | A certificate expires within 7 days and has not yet renewed — manual intervention likely needed. |
| `CertificateRenewalFailing` | `increase(certmanager_certificate_renewal_failures_total[6h]) > 0` | 15m | **Warning** | cert-manager has attempted and failed a renewal — check ACME challenge status before it becomes urgent. |
| `MetalLBSpeakerDown` | `up{job="metallb", component="speaker"} == 0` | 5m | **Critical** | A MetalLB speaker is down — LoadBalancer IPs announced from that node are unreachable. |
| `MetalLBPoolExhausted` | `metallb_allocator_addresses_in_use_total / metallb_allocator_addresses_total > 0.90` | 10m | **Warning** | An IP pool is over 90% allocated — new LoadBalancer services will soon fail to get an address. |
| `ExternalDNSSyncErrors` | `increase(external_dns_registry_errors_total[1h]) > 0` | 15m | **Warning** | DNS record sync is failing — new or changed hostnames won't resolve. |
| `CloudflaredTunnelDown` | `cloudflared_tunnel_ha_connections == 0` | 2m | **Critical** | Zero active tunnel connections — everything exposed through Cloudflare is unreachable. |

---

### Phase 3 Task Checklist (Networking & Ingress)

1. Add scrape blocks to Alloy `custom-config` for all five targets: `traefik`, `cert-manager`, `metallb`, `external-dns`, `cloudflared` — recommend as one combined PR since they touch the same config file.
2. Confirm Traefik access logs are being shipped to Loki with the labels needed for the Tab 2 log panel (namespace/container at minimum).
3. Build **S3 — Networking & Ingress** dashboard JSON (5 tabs as above), deliver as `dashboard-networking.yaml` ConfigMap, folder annotation `grafana_folder: "SRE / Operations"`.
4. Add the 8 networking alert rules to Mimir Ruler, routed through the existing stub Alertmanager receivers from Phase 1.
5. Verify Firing Alerts Table on S3 Tab 5 correctly surfaces the new alert rules (test with a synthetic cert-manager renewal failure or a Traefik 5xx injection).
6. Backfill the two E1 (Platform Overview) placeholder panels — Certificate Expiry Countdown and Ingress Request Sparkline — with the real queries from Tab 1/Tab 3 above, removing the "Pending Phase 3" markers.
7. Update `kustomization.yaml` in `kubernetes/apps/infrastructure/grafana/components/dashboards/` to include the new ConfigMap.
8. Confirm with stakeholder whether Cloudflare Tunnel *health* metrics should indeed stay here (as planned) versus moving entirely to S6 in Phase 7 — see design note above.