# P2 — Home — Trusted

| | |
|---|---|
| **Folder** | Portal |
| **Dashboard ID** | P2 |
| **Refresh** | 5 min |
| **Audience** | Close/known users — household members, power users |

> **Purpose:** Everything in [P1 — Home — Public](HOME_PUBLIC.md) plus household-relevant status panels: weather, smart home device status, and room-by-room IoT overview. This is the "family control panel" — not a monitoring dashboard, but a *living room screen* that happens to run in Grafana.

**← Back to [Dashboard Catalog](../README.md#-portal-3-dashboards)**

---

## Implementation Decision

> [!IMPORTANT]
> **Same as P1** — implementation approach (Grafana-native vs Homepage/Homarr vs Hybrid) has not been finalized. Panels below assume Grafana-native. See [README](../README.md#-portal-3-dashboards) for options.

---

## Design Philosophy

P2 extends P1's "non-technical user" design:

- **Household-friendly** — a family member should understand every panel without training.
- **Glanceable from across the room** — if this runs on a wall-mounted display or tablet, text must be large enough to read at 2 meters.
- **No alarm fatigue** — status indicators only, no alert banners or flashing panels. A red dot on "Living Room Lights" is informative, not an emergency.

---

## Dashboard Layout

Single-screen. Two sections stacked vertically:

1. **App Cards** (identical to P1)
2. **Household Status** (weather + smart home)

---

### Section 1: App Cards

Identical to [P1](HOME_PUBLIC.md#app-cards). Same three app cards (Immich, Obsidian, Copyparty) with the same status indicators and links.

---

### Section 2: Household Status

> [!NOTE]
> **Data source decision required:** Smart home data can come from multiple sources. The panels below document two options:
> - **Home Assistant API** — If you run Home Assistant, its REST API or WebSocket API can feed a Grafana JSON API datasource. Richest data, most complex setup.
> - **MQTT → Prometheus** — If your IoT devices publish to MQTT, an `mqtt_exporter` can bridge MQTT topics to Prometheus metrics. Simpler, but requires MQTT infrastructure.
>
> This decision is deferred until the Portal phase. The panel specifications are source-agnostic — they describe *what to show*, not *how to query it*.

#### Weather Widget

| Panel | Type | Source | Rationale |
|-------|------|--------|-----------|
| **Current Weather** | Stat (big number) + icon | OpenWeatherMap API via Grafana JSON API datasource, or Home Assistant weather entity | Temperature, conditions (sunny/cloudy/rain), and a weather icon. This is the panel that makes P2 feel like a "home dashboard" rather than a monitoring tool — it sets the household context. |
| **5-Day Forecast** | Bar gauge or sparkline | Same source, 5-day forecast data | Quick glance at the week ahead. Useful for a wall-mounted display. |

#### Smart Home Status

| Panel | Type | Source | Rationale |
|-------|------|--------|-----------|
| **Room Status Grid** | Stat grid (one per room) | Home Assistant entities or MQTT topics: `home/<room>/lights`, `home/<room>/temperature` | Room-by-room overview: "Living Room: 22°C, Lights On" / "Bedroom: 19°C, Lights Off". Each room card shows temperature and light/device status. |
| **Light Status** | Multi-stat | `home_assistant_entity_state{entity_id=~"light.*"}` or MQTT `home/+/lights/state` | Which lights are on/off across the house? Color-coded: On 🟡, Off ⚪. |
| **Fan/Climate Status** | Multi-stat | `home_assistant_entity_state{entity_id=~"fan.*\|climate.*"}` or MQTT topics | Fan speeds, AC status, heater status. Relevant for comfort monitoring. |
| **Door/Window Sensors** | Multi-stat | `home_assistant_entity_state{entity_id=~"binary_sensor.*door\|binary_sensor.*window"}` | Open 🔴, Closed 🟢. Security awareness for household members. |
| **Energy Usage** | Stat | Smart plug power metrics or utility meter integration | Current power draw if smart plugs report wattage. Optional — depends on hardware. |

---

### Implementation Details (Grafana-Native)

| Element | Grafana Feature | Notes |
|---------|----------------|-------|
| **Weather widget** | JSON API datasource → Stat panel | Grafana's JSON API datasource can call any REST API. Configure with OpenWeatherMap API key or Home Assistant long-lived token. |
| **Room cards** | Stat panels in a grid | Same approach as P1 app cards. Map entity states to colors via value mappings. |
| **Smart home data** | JSON API or Infinity datasource | Grafana Infinity datasource supports REST, GraphQL, and JSON — can query Home Assistant directly without an intermediary. |
| **Wall display mode** | Grafana kiosk + auto-refresh | `?kiosk=1&refresh=5m` in the URL. Combined with a Raspberry Pi or tablet, this becomes a dedicated wall display. |

---

**← Back to [Dashboard Catalog](../README.md#-portal-3-dashboards)** | **Previous: [P1 — Home — Public](HOME_PUBLIC.md)** | **Next: [P3 — Home — Admin](HOME_ADMIN.md)**
