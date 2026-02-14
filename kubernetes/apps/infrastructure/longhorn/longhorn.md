Here is a comprehensive documentation guide for **Longhorn**, tailored for a Kubernetes beginner, based on the provided Helm chart configuration and version 1.11.0.

---

# Introduction to Longhorn

**Longhorn** is a lightweight, distributed block storage system for Kubernetes.

In Kubernetes, Pods are ephemeral (temporary). When a Pod dies, the data inside it is lost unless it is stored in a Persistent Volume. Longhorn solves this by taking the available disk space on your Kubernetes nodes (servers) and aggregating it into a storage pool.

When you ask for a "Volume" (a virtual disk) for your application, Longhorn creates that disk and replicates the data across multiple nodes in your cluster. This ensures that if one node fails, your data remains available on another node, and your application can continue running.

### How It Works
1.  **Manager:** Longhorn runs a "Manager" pod on every node in your cluster.
2.  **Replication:** When you create a volume (e.g., 10GB), Longhorn divides the data into blocks and stores copies (replicas) of these blocks on the physical disks of multiple nodes.
3.  **Controller:** It exposes this storage to Kubernetes as a standard StorageClass.
4.  **Engine:** It handles the input/output (read/write) operations, ensuring data consistency across replicas.

---

# Comprehensive Feature List

Below is a list of the major features available in Longhorn 1.11.0, explained with their function and the corresponding values from your `values.yaml` file.

### 1. Default Storage Class Configuration
Longhorn installs a default `StorageClass` in Kubernetes. When a user requests storage without specifying a type, Longhorn fulfills the request.
*   **Description:** Defines how volumes are created by default, including the filesystem type and replication factor.
*   **Related Values:**
    *   `persistence.defaultClass`: Set to `true` to make Longhorn the default storage provider.
    *   `persistence.defaultFsType`: Usually `ext4` or `xfs`.
    *   `persistence.defaultClassReplicaCount`: The number of copies of data to keep (Default is `3`). High reliability.
    *   `persistence.reclaimPolicy`: Determines if data is deleted (`Delete`) or kept (`Retain`) when a user deletes the Kubernetes Volume Claim.

### 2. Data Locality and Scheduling
Longhorn attempts to keep data close to the workload to improve performance and reduce network traffic.
*   **Description:** "Data Locality" tries to keep a copy of the data on the same physical node where the Pod is running.
*   **Related Values:**
    *   `defaultSettings.defaultDataLocality`:
        *   `disabled`: Replicas are placed anywhere.
        *   `best-effort`: Tries to place a replica on the same node as the pod, but will use other nodes if the local disk is full.
    *   `defaultSettings.replicaSoftAntiAffinity`: Ensures replicas are spread across different nodes/zones so one failure doesn't kill all data.
    *   `defaultSettings.storageOverProvisioningPercentage`: Allows you to promise more storage to Kubernetes than you physically have (Thin Provisioning).

### 3. Backups and Snapshots
Longhorn has a built-in disaster recovery system.
*   **Description:**
    *   **Snapshot:** A point-in-time state of the volume stored locally on the cluster.
    *   **Backup:** A compressed copy of the data sent to external storage (like S3 or NFS) for safety.
*   **Related Values:**
    *   `defaultBackupStore`:
        *   `backupTarget`: The URL for the external storage (e.g., `s3://my-bucket` or `nfs://server/path`).
        *   `backupTargetCredentialSecret`: The Kubernetes Secret containing S3 keys or credentials.
    *   `persistence.recurringJobSelector`: Automates the schedule for taking snapshots or backups (e.g., every night at 2 AM).
    *   `defaultSettings.snapshotMaxCount`: Limits the number of local snapshots to prevent filling up the disk.

### 4. V2 Data Engine (SPDK)
*   **Description:** Longhorn traditionally uses the V1 engine. Version 1.11.0 includes a V2 engine based on SPDK (Storage Performance Development Kit). This is a high-performance mode designed for NVMe drives, bypassing the standard kernel bottlenecks for faster speeds.
*   **Related Values:**
    *   `defaultSettings.v2DataEngine`: Set to `true` to enable high-performance mode.
    *   `defaultSettings.dataEngineHugepageEnabled`: V2 requires "Hugepages" (a memory management feature) to be enabled on the nodes.
    *   `defaultSettings.dataEngineCPUMask`: Dedicates specific CPU cores to storage processing.

### 5. ReadWriteMany (RWX) Support
Standard block storage is "ReadWriteOnce" (attached to one node). Longhorn allows "ReadWriteMany".
*   **Description:** Allows a single volume to be mounted by multiple Pods on different nodes simultaneously. Longhorn achieves this by spinning up a lightweight user-space NFS server inside the cluster.
*   **Related Values:**
    *   `persistence.nfsOptions`: Configuration for the internal NFS mount.
    *   `defaultSettings.endpointNetworkForRWXVolume`: Can isolate this traffic to a specific network interface.

### 6. The Longhorn UI (Dashboard)
Longhorn provides a graphical interface to view volume health, trigger backups, and manage nodes.
*   **Description:** A web dashboard for management.
*   **Related Values:**
    *   `service.ui.type`: How to expose the UI (e.g., `ClusterIP`, `NodePort`, or `LoadBalancer`).
    *   `ingress.enabled`: Enables an Ingress controller (like NGINX) to route traffic to the UI via a domain name (e.g., `longhorn.example.com`).
    *   `ingress.tls`: Enables HTTPS for the dashboard.

### 7. Maintenance and Auto-Salvage
*   **Description:** If a node loses network connectivity or crashes, volumes may become "degraded." Longhorn includes logic to attempt to fix this automatically.
*   **Related Values:**
    *   `defaultSettings.autoSalvage`: If all replicas are lost (e.g., network partition), this feature tries to recover the volume using the last known good data.
    *   `defaultSettings.autoDeletePodWhenVolumeDetachedUnexpectedly`: If a volume disconnects, this kills the Pod so Kubernetes can restart it on a healthy node.

### 8. Node and Disk Selector (Tagging)
*   **Description:** You might have some nodes with fast SSDs and others with slow HDDs. You can tag nodes/disks and tell Longhorn to put specific data on specific hardware.
*   **Related Values:**
    *   `persistence.defaultNodeSelector`: Restricts the default storage class to specific nodes.
    *   `persistence.defaultDiskSelector`: Restricts storage to disks with specific tags (e.g., `ssd`, `nvme`).

### 9. Backing Images
*   **Description:** Allows you to create a volume pre-filled with data from an external image (like a VM template or an ISO). This is useful for Virtual Machine workloads on Kubernetes.
*   **Related Values:**
    *   `persistence.backingImage`:
        *   `name`: The name of the image.
        *   `dataSourceType`: Where to get the image (e.g., `download`, `upload`).

### 10. Monitoring (Prometheus)
*   **Description:** Longhorn exposes metrics (IOPS, throughput, latency, storage usage) that can be scraped by monitoring tools.
*   **Related Values:**
    *   `metrics.serviceMonitor.enabled`: Creates a `ServiceMonitor` resource for the Prometheus Operator to automatically start collecting data.

---

# Related & Sister Technologies

To understand Longhorn's place in the ecosystem, it helps to know what it relies on and what competes with it.

### Dependent Features (Longhorn needs these)
1.  **iSCSI (Internet Small Computer Systems Interface):**
    *   Longhorn relies on the `open-iscsi` client being installed on the Linux operating system of your Kubernetes nodes. It uses this protocol to attach the virtual disk to the node.
2.  **NFSv4 Client:**
    *   Required on the host nodes if you plan to use **ReadWriteMany (RWX)** volumes or if you use NFS as your Backup Target.
3.  **Hugepages (Linux Kernel):**
    *   Strictly required if you enable the **V2 Data Engine** (SPDK).

### Sister Features (Often used together)
1.  **Velero:**
    *   While Longhorn has its own backup mechanism, Velero is a general-purpose Kubernetes backup tool. Velero can be configured to trigger Longhorn snapshots or back up the Kubernetes manifests alongside the Longhorn data.
2.  **Rancher:**
    *   Longhorn is developed by SUSE (the creators of Rancher). It integrates natively into the Rancher Cluster Manager UI, making it the "default" choice for Rancher users.

### Alternate Features (Competitors)
1.  **Rook / Ceph:**
    *   The main competitor. Ceph is much more complex and heavy but scales to petabytes of data and supports Object Storage (S3) natively. Longhorn is generally considered easier to install and manage for small-to-medium clusters.
2.  **OpenEBS:**
    *   Another container-attached storage solution. Similar to Longhorn but offers different storage engines (Mayastor, Jiva, cStor).
3.  **Cloud Provider Storage (EBS / PD / Azure Disk):**
    *   If you are on AWS/Google/Azure, you can use their native block storage. However, Longhorn is still useful in the cloud if you want faster detach/attach times or if you want **Cross-Availability-Zone** replication (which standard cloud disks often don't support cheaply).