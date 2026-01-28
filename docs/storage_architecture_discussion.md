# VM Storage Architecture & Allocation Breakdown

This document provides a detailed breakdown of every active virtual machine in the ecosystem, defining its function and partitioning its data across the three storage tiers: **Boot Pool** (`local-thin`), **Data Pool** (`data-storage`), and **Network Storage** (`NFS`).

## Storage Tiers & Usage Theory

1.  **Boot Pool (`local-thin`)**:
    *   **Role**: Operating System, Kubernetes Binaries, System Logs, Container Runtimes.
    *   **Risk**: If this fills up, the Node crashes or Evicts pods (as seen with `ruth-02`).
    *   **Content**: `/`, `/var/log`, `/var/lib/kubelet` (Ephemeral Pod Data), `/var/lib/containerd` (Images).

2.  **Data Pool (`data-storage`)**:
    *   **Role**: Persistent Application Data (Longhorn).
    *   **Mount**: `/data/storage` (Used by Longhorn for PVCs).
    *   **Content**: Databases (Postgres, Redis), App Configs, Prometheus Metrics, Loki Chunks.

3.  **NFS Share (`truenas-01`)**:
    *   **Role**: Bulk Media and Backup Archival.
    *   **Mount**: Mounted into Pods via PVC (ReadWriteMany) or HostPath.
    *   **Content**: Photos (Immich), Movies/TV (Arr), Backups (Velero/Restic).

---

## 1. Cluster `ruth` (Management & Heavy Apps)

### **ruth-01** (Master / Monitoring)
*   **Function**: Kubernetes Control Plane, Monitoring Brain, GitOps Controller.
*   **Key Applications & Pods**:
    *   **`argocd`**: `argocd-server`, `argocd-repo-server`, `argocd-application-controller` (Redis/Repo data).
    *   **`prometheus-stack`**: `prometheus-server` (TSDB), `grafana`, `alertmanager`.
    *   **`traefik`**: Ingress Controller pods.
    *   **`metallb-system`**: Speaker/Controller pods.
*   **Storage Breakdown**:
    *   **`local-thin` (16 GB)**:
        *   **OS & Binaries**: ~6 GB
        *   **Images**: `quay.io/argoproj/argocd`, `quay.io/prometheus/prometheus` (~4 GB)
        *   **Headroom**: ~4 GB
    *   **`data-storage` (20 GB)**:
        *   **Longhorn PVCs**: `prometheus-db` (~10 GB), `grafana-storage` (<1 GB).
    *   **`NFS`**:
        *   **Backups**: Cluster state snapshots.

### **ruth-02** (Immich AI / Database)
*   **Function**: AI Processing (Machine Learning), Shared Databases.
*   **Key Applications & Pods**:
    *   **`immich`**: `immich-server`, `immich-microservices`, `immich-machine-learning` (Heavy ML models).
    *   **`databases`**: `postgresql` (Vector DB), `redis`.
*   **Storage Breakdown**:
    *   **`local-thin` (16 GB - Critical)**:
        *   **OS & Binaries**: ~6 GB
        *   **Images**: `ghcr.io/immich-app/immich-machine-learning` (Huge layers), `postgres:14-alpine` (~5 GB).
        *   **Pod Ephemeral**: `/tmp` processing for ML uploads (~2 GB).
        *   **Headroom**: ~3 GB
    *   **`data-storage` (40 GB)**:
        *   **Longhorn PVCs**: `immich-postgres` (~20 GB), `immich-redis` (~1 GB).
        *   **ML Cache**: Cached model weights (~5 GB).
    *   **`NFS`**:
        *   **Immich Library**: `/mnt/media/photos` (~1 TB+).

### **ruth-03** (Logs / Obsidian)
*   **Function**: Log Aggregation, Document Sync.
*   **Key Applications & Pods**:
    *   **`loki`**: `loki-write`, `loki-read`, `loki-backend` (Log ingestion).
    *   **`obsidian-livesync`**: `couchdb` pod.
    *   **`promtail`**: Log collector agent.
*   **Storage Breakdown**:
    *   **`local-thin` (16 GB)**:
        *   **OS & Binaries**: ~6 GB
        *   **Images**: `grafana/loki`, `couchdb` (~3 GB).
        *   **Logs**: System journals (~4 GB).
    *   **`data-storage` (20 GB)**:
        *   **Longhorn PVCs**: `loki-chunks` (~15 GB), `couchdb-data` (~2 GB).

---

## 2. Cluster `arr` (Media Stack)

### **arr-01** (Master / Controller)
*   **Function**: Kubernetes Control Plane for Media.
*   **Key Applications & Pods**:
    *   **`traefik`**: Ingress for media apps.
    *   **`cert-manager`**: `cert-manager`, `cainjector`, `webhook` (TLS mgmt).
    *   **`longhorn-manager`**: Storage orchestration.
*   **Storage Breakdown**:
    *   **`local-thin` (12 GB)**:
        *   **OS & Binaries**: ~5 GB
        *   **Images**: `traefik`, `quay.io/jetstack/cert-manager-controller` (~2 GB).
    *   **`data-storage` (10 GB)**:
        *   **Etcd**: K8s state (~2 GB).
    *   **`NFS`**: None.

### **arr-02** (Media Worker 1 - Downloads)
*   **Function**: Bulk Downloading & Management.
*   **Key Applications & Pods**:
    *   **`sonarr`**: Series management pod.
    *   **`radarr`**: Movie management pod.
    *   **`sabnzbd` / `qbittorrent`**: Downloader pods.
    *   **`prowlarr`**: Indexer manager.
*   **Storage Breakdown**:
    *   **`local-thin` (12 GB)**:
        *   **OS & Binaries**: ~5 GB
        *   **Images**: `lscr.io/linuxserver/sonarr`, `radarr` (Checking for updates frequently) (~3 GB).
    *   **`data-storage` (20 GB)**:
        *   **Longhorn PVCs**: `sonarr-config` (SQLite DBs), `radarr-config` (~5 GB).
    *   **`NFS`**:
        *   **Downloads**: `/mnt/media/downloads` (~500 GB).
        *   **Library**: `/mnt/media/tv`, `/mnt/media/movies`.

### **arr-03** (Media Worker 2 - Streaming)
*   **Function**: Transcoding & Requests.
*   **Key Applications & Pods**:
    *   **`plex` / `jellyfin`**: Media server pods.
    *   **`overseerr`**: Request UI pod.
    *   **`tautulli`**: Plex monitoring.
*   **Storage Breakdown**:
    *   **`local-thin` (12 GB)**:
        *   **OS & Binaries**: ~5 GB
        *   **Images**: `plexinc/pms-docker` (Very large) (~2 GB).
        *   **Transcode Buffer**: **CRITICAL** - `/tmp` or `EmptyDir`. If transcoding 4K, this can eat 10GB+ rapidly. **MUST MAP TO NFS OR LARGE PVC**.
    *   **`data-storage` (20 GB)**:
        *   **Longhorn PVCs**: `plex-config` (Metadata/Posters/BIFs) (~15 GB).
    *   **`NFS`**:
        *   **Library**: Read-only access to `/mnt/media`.

---

## 3. Static & Support VMs

### **hiking-bear (1010)**
*   **Function**: Workstation.
*   **Apps**: VSCode Remote, Docker, Kubectl, Ansible.
*   **`local-thin`**: 20 GB.

### **sandbox-01 (1099)**
*   **Function**: Testing using Kind.
*   **Apps**: `kind-control-plane` container.
*   **`local-thin`**: 20 GB.

### **cf-tunnel (2050)** & **adguard (2051)**
*   **Apps**: `cloudflared`, `adguardhome`.
*   **Storage**: Minimal logging.
