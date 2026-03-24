# Validation & Tooling

This document describes the automated validation tools available for enforcing the Kubernetes app structure standards defined in this project.

## Table of Contents

1. [Structure Validator](#1-structure-validator)
2. [What It Checks](#2-what-it-checks)
3. [Reading the Output](#3-reading-the-output)
4. [Chart Inflation Script](#4-chart-inflation-script)

---

## 1. Structure Validator

The structure validator ensures that all Kubernetes apps follow the **Base + Patches + Overlays** directory pattern.

### Usage

```sh
python .agent/skills/kubernetes-management/scripts/validate_structure.py .
```

Run this from the repository root. The script scans the entire `kubernetes/` directory.

### When to Run

- **After creating a new app** — to confirm the folder structure is correct.
- **After moving or renaming files** — to catch broken references.
- **Before committing** — as a final sanity check.

---

## 2. What It Checks

The validator performs two passes: one over the **Apps Catalog** and one over the **Cluster Inventory**.

### Apps Catalog Checks (`kubernetes/apps/`)

| Check | Severity | Description |
|---|---|---|
| Base exists | `MISSING` | Every app must have `base/kustomization.yaml` |
| `valuesFile` used | `INVALID` | Helm charts must use `valuesFile`, never `valuesInline` |
| Values file exists | `MISSING` | If `valuesFile` is specified, the referenced file must exist |
| Component structure | `INVALID` | Every subdirectory in `components/` must have its own `kustomization.yaml` |
| No inline patches | `INVALID` | Components must use `path:` to external patch files, not inline `patch:` strings |
| Overlays exist | `MISSING` | Every app must have an `overlays/` directory |
| Valid overlay profiles | `EMPTY` | At least one overlay must contain a `kustomization.yaml` |
| Relative paths resolve | `BROKEN` | All `resources` and `components` paths must point to existing targets |

### Cluster Inventory Checks (`kubernetes/clusters/`)

| Check | Severity | Description |
|---|---|---|
| Kustomization exists | `MISSING` | Every app directory under a cluster must have `kustomization.yaml` |
| Relative paths resolve | `BROKEN` | All `resources` and `components` paths must point to existing targets |

---

## 3. Reading the Output

### Success

```
✅ Kubernetes App Structure is Valid.
```

### Failure

```
❌ Structure Validation Failed:
  - [MISSING] radarr/base/kustomization.yaml
  - [INVALID] sonarr/base/kustomization.yaml uses 'valuesInline' (Forbidden). Use 'valuesFile'.
  - [BROKEN] CLS1/immich/kustomization.yaml references missing resources: ../../../apps/services/immich/overlays/prod
```

**Fix the reported issues before committing.** Severity tags indicate the type:

| Tag | Meaning |
|---|---|
| `MISSING` | A required file or directory does not exist |
| `INVALID` | A file exists but violates a structural rule |
| `BROKEN` | A reference path does not resolve to a real target |
| `EMPTY` | A required directory exists but has no valid content |
| `WARNING` | A non-critical issue that may indicate a mistake |

---

## 4. Chart Inflation Script

For debugging, a separate script renders the full Kustomize output to inspect generated resources:

```sh
python .agent/skills/kubernetes-management/scripts/inflate_chart.py [path_to_kustomization_dir]
```

- Produces a `debug_full.yaml` with the complete rendered output.
- Useful for finding exact resource names and field paths for patches.
- **Must be deleted before committing** — it is a debug artifact only.

See [Debugging Guide](./04-debugging-guide.md) for the full debugging workflow.
