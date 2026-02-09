# Cluster Configuration & Bootstrap Analysis

## 1. ArgoCD Bootstrapping Mechanism

The bootstrapping process controls how ArgoCD discovers and manages the Kubernetes clusters. This logic is centrally defined in the Ansible role for ArgoCD.

*   **Source File**: `ansible/roles/argocd/templates/cluster-bootstrap.yaml.j2`
*   **Mechanism**: **ArgoCD ApplicationSet**
    *   The `ApplicationSet` uses a **Git Generator**.
    *   **Pattern**: It recursively scans the Git repository for any directories matching `kubernetes/clusters/*/*`.
    *   **Application Creation**: For *every* subdirectory found (e.g., `kubernetes/clusters/arr/promtail`, `kubernetes/clusters/ruth/loki`), it creates a distinct ArgoCD Application.

### Destination Logic
The template contains conditional logic to determine where to deploy the application based on the parent directory name (the cluster name).

| Cluster Name | Destination Config | Resulting URL | Type |
| :--- | :--- | :--- | :--- |
| `ruth` | `https://kubernetes.default.svc` | Internal Service | **In-Cluster** (Management) |
| `arr` (or others) | `https://{{cluster_name}}-api.example.com:6443` | External DNS | **External Cluster** |

---

## 2. Configuration Differences: `arr` vs `ruth`

Analyzing the configurations reveals distinct roles for the two clusters:
*   **Ruth**: Validated as the **Management/Infrastructure Cluster**. It hosts central logging (Loki) and uses internal service discovery.
*   **Arr**: Validated as a **Workload/Edge Cluster**. It runs with tighter resource constraints and ships logs externally to Ruth.

### A. Key Structural Differences

| component | `arr` (External) | `ruth` (Management) | Analysis |
| :--- | :--- | :--- | :--- |
| **Loki** | **❌ Absent** | **✅ Present** | `ruth` acts as the central log aggregation server. `arr` does not store logs locally. |
| **Promtail** (Patches) | **Inline Patch** | **3 Separate Files** | `arr` uses a single `kustomization.yaml` with a large inline `patches` block. `ruth` splits this into `secret-patch.yaml`, `debug-patch.yaml`, etc. |
| **System Patches** | **CoreDNS** + Kube-Proxy | Kube-Proxy Only | `arr` likely requires custom CoreDNS config (possibly for the `example.com` resolution or external access) that `ruth` does not need. |

### B. "Duplicate" Configuration (Promtail)

You requested to find "same config done at 2 places". The **Promtail** configuration is nearly identical but structurally divergent.

*   **The Duplicate**: The `scrape_configs` block for determining how to read Kubernetes pod logs.
*   **Location 1 (Arr)**: `kubernetes/clusters/arr/promtail/kustomization.yaml` (Lines 27-62)
*   **Location 2 (Ruth)**: `kubernetes/clusters/ruth/promtail/secret-patch.yaml` (Lines 19-51)

**Difference in Content**:
*   **Arr** pushes to: `http://loki.ruth.example.com/loki/api/v1/push` (External Ingress)
*   **Ruth** pushes to: `http://loki.logging.svc.cluster.local:3100/loki/api/v1/push` (Internal Service)

### C. Resource Constraints (Manifest Differences)

`arr` has significantly stricter resource management applied via Kustomize patches. This suggests it might be running on hardware with limited resources (e.g., a smaller VM or edge device).

| Component | `arr` Resource Limits | `ruth` Resource Limits |
| :--- | :--- | :--- |
| **Cert-Manager** | Replicas: `1`<br>CPU Request: `100m`<br>Mem Limit: `512Mi` | **Default** (No patches) |
| **Sealed-Secrets** | Replicas: `1`<br>CPU Request: `10m`<br>Mem Limit: `128Mi` | **Default** (No patches) |
