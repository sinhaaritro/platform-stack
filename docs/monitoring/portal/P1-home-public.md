# P1 — Home — Public

| | |
|---|---|
| **Folder** | Portal |
| **Dashboard ID** | P1 |
| **Refresh** | 5 min |
| **Audience** | Generic end users — family, friends, anyone with basic access |

> **Purpose:** The simplest possible landing page. A non-technical user opens Grafana and sees a clean grid of app cards with status indicators and direct links — nothing else. No metrics, no graphs, no admin tools. If an app is down, the status dot turns red. That's the extent of information a public user needs.

**← Back to [Dashboard Catalog](../README.md#-portal-3-dashboards)**

---

## Implementation Decision

> [!IMPORTANT]
> **This dashboard's implementation approach has not been finalized.** Three options are documented in the [README](../README.md#-portal-3-dashboards). The panel specifications below assume **Option A (Grafana-native)** — all content delivered as a standard Grafana dashboard JSON. If Option B (Homepage/Homarr) or Option C (Hybrid) is chosen, this doc serves as the *content specification* regardless of the delivery mechanism.

---

## Design Philosophy

P1 is **not a monitoring dashboard**. It is a **service directory** with live status. Design principles:

- **Zero learning curve** — a family member who has never seen Grafana should understand this page instantly.
- **No Grafana chrome** — hide the sidebar, header, and time picker if possible (Grafana kiosk mode or a custom theme).
- **Mobile-first** — many end users will access this from phones. Cards must stack vertically on narrow screens.
- **Visual identity** — each app has its own icon and color, not generic Grafana panel borders.

---

## Dashboard Layout

Single-screen, no tabs, no rows. A grid of **app cards**, each containing an icon, name, description, status indicator, and a clickable link to the app.

---

### App Cards

| Card | Icon | App Name | Description | Status Query | Link |
|------|------|----------|-------------|--------------|------|
| **Immich** | 📷 (or Immich logo) | Immich | Photos & videos | `up{job="traefik"} * on() group_left() (traefik_service_server_up{service=~".*immich.*"} > 0)` or simplified: `probe_success{target=~".*immich.*"}` | `https://photos.<domain>` |
| **Obsidian** | 📝 (or Obsidian logo) | Obsidian LiveSync | Notes sync | `up{job="couchdb"}` (CouchDB backing Obsidian sync) | `https://obsidian.<domain>` |
| **Copyparty** | 📁 (or folder icon) | Copyparty | File sharing | `probe_success{target=~".*copyparty.*"}` or Traefik service status | `https://files.<domain>` |

### Status Indicator Logic

Each card has a colored dot:
- 🟢 **Online** — the app's backend is responding (Traefik reports healthy upstream, or a blackbox probe succeeds)
- 🔴 **Offline** — the app is unreachable

> [!NOTE]
> **Status source options:**
> 1. **Traefik service health** — `traefik_service_server_up` reports per-backend health. Already scraped from [S3](../sre/NETWORKING.md). Most accurate since it reflects what users actually experience through the ingress.
> 2. **Blackbox Exporter** — `probe_success` from Prometheus Blackbox Exporter. Requires deploying blackbox-exporter and configuring probe targets. More flexible (can probe any URL including external services) but adds another component.
> 3. **kube-state-metrics pod status** — `kube_pod_status_phase{phase="Running"}`. Already available from [S2](../sre/CLUSTER_AND_NODE_HEALTH.md). Less accurate for end users since a pod can be "Running" but its HTTP endpoint can still be broken.
>
> **Recommendation:** Use Traefik service health (option 1) since it's already scraped and most accurately reflects "can a user reach this app."

### Implementation Details (Grafana-Native)

| Element | Grafana Feature | Notes |
|---------|----------------|-------|
| **App cards** | Stat panels in a grid layout | Each stat panel shows the app name as title, description as panel description, and maps the status query to a color (green/red via value mappings). |
| **App icons** | Panel title with emoji or `<img>` in Text panel | Grafana Text panels (HTML mode) support inline images. Alternatively, use panel title emojis. |
| **App links** | Data links on each Stat panel | Click the card → opens the app URL in a new tab. Grafana "Data links" or "Panel links" support external URLs. |
| **Kiosk mode** | Grafana URL with `?kiosk=1` | Hides sidebar and top nav. Combined with auto-login via Authentik, a public user sees only the dashboard. |
| **Mobile layout** | Responsive grid | Grafana dashboards are responsive by default. Set panel widths to 8 (3-column on desktop, stacks on mobile). |

---

**← Back to [Dashboard Catalog](../README.md#-portal-3-dashboards)** | **Next: [P2 — Home — Trusted](P2-home-trusted.md)**
