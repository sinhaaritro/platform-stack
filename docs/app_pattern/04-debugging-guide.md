# Debugging Guide

This document provides a systematic approach to diagnosing and fixing broken Kubernetes applications managed by this platform.

## Table of Contents

1. [Decision Tree: Global vs. Local](#1-decision-tree-global-vs-local)
2. [Path A: Global Issue](#2-path-a-global-issue)
3. [Path B: Local Issue](#3-path-b-local-issue)
4. [Local Chart Inflation](#4-local-chart-inflation)
5. [Operational Notes](#5-operational-notes)

---

## 1. Decision Tree: Global vs. Local

Before writing any fix, ask: **"Is this a Global Issue or a Local Issue?"**

```
Application is broken. What kind of issue?
│
├── Global Issue
│   (Buggy config, wrong image, broken values)
│   → Fix in apps/services/[app]/base/ or apps/services/[app]/patches/
│   → Affects ALL clusters using this app
│
└── Local Issue
    (Wrong ingress host, quota mismatch, cluster-specific config)
    → Fix in clusters/[cluster]/[app]/
    → Affects ONLY this cluster
```

---

## 2. Path A: Global Issue

A global issue originates from the shared app definition and affects every cluster that uses the app.

| Fix Location | When |
|---|---|
| `apps/services/[app]/base/values.yaml` | Wrong default values, chart version bump |
| `apps/services/[app]/base/kustomization.yaml` | Chart source change, namespace fix |
| `apps/services/[app]/patches/[feature].yaml` | Broken feature patch |

**Impact:** Every cluster and overlay that references this base or patch will be affected. Test thoroughly before committing.

---

## 3. Path B: Local Issue

A local issue is scoped to a single cluster and does not require changes to the shared catalog.

**Fix Location:** `clusters/[cluster]/[app]/`

**Method:**
1. Edit the cluster's `kustomization.yaml`.
2. Add or modify a `patch-[logic].yaml` file.

**Impact:** Only the target cluster is affected. Other clusters remain untouched.

---

## 4. Local Chart Inflation

When you need to see the **full rendered YAML** to determine the correct patch path for a resource, use the chart inflation script.

### Usage

```sh
python .agent/skills/kubernetes-management/scripts/inflate_chart.py [path_to_kustomization_dir]
```

### Workflow

1. Run the command against the directory containing the `kustomization.yaml` you want to inspect.
2. Inspect the generated `debug_full.yaml` to find exact resource names, field paths, and structures.
3. Write your patch based on the actual rendered output.
4. **Delete `debug_full.yaml` before committing.** This file is for debugging only and must never be checked into Git.

---

## 5. Operational Notes

- **kubectl Access:** Never assume `kubectl` works locally against the target cluster. Use Ansible tunneling via `task -d ansible k8s:cmd` to run commands against remote clusters.
- **Always validate** your fix using the structure validator (see [Validation & Tooling](./05-validation-and-tooling.md)) before committing.
- **Prefer patches over value edits.** Even for bug fixes, use the patching model to keep changes traceable and reversible.
