# Introduction

**SeaweedFS** is a high-performance distributed storage system.
*   It handles billions of files efficiently.
*   It allows you to access files via a standard "File System" (like folders on your laptop) OR via the "S3 API" (like cloud storage).
*   It is highly modular, consisting of a "Master" (the brain), "Volume Servers" (the hard drives), and a "Filer" (the catalog).

This chart installs all these components to create a unified storage cloud.

---

# Feature List (Simple to Advanced)

1.  **Core Storage (Master & Volume):** The basic setup to store and track data.
2.  **S3 Compatibility:** Access your data using standard S3 tools and libraries.
3.  **The Filer (File System View):** Organize data into directories and files.
4.  **Persistence (Saving Data):** Configure where the actual data lives (Hard Drive vs. Cloud Volume).
5.  **Replication (Data Safety):** Configure how many copies of your data exist.
6.  **All-In-One Mode:** Run everything in a single pod for quick testing.
7.  **External Database (High Availability):** Connect the Filer to MySQL/Postgres for a production-grade catalog.
8.  **Security & Authentication:** Password protect your S3 and Admin portals.
9.  **Topology Awareness:** Tell SeaweedFS which racks/zones servers are in to optimize data placement.
10. **Maintenance (Workers & Admin):** specialized tools to balance disks and clean up deleted files.
11. **SFTP Access:** Upload files using older FTP clients securely.

---

# Detailed Feature Breakdown

## 1. Core Storage (Master & Volume)
**Description:** The absolute minimum required. The **Master** manages the cluster, and **Volume** servers actually store the binary data.

*   **Related Values:** `master.enabled`, `volume.enabled`, `volume.dataDirs`
*   **Related Features:** None.
*   **Example:**
    ```yaml
    master:
      enabled: true
      replicas: 3 # Run 3 brains for safety
    volume:
      enabled: true
      replicas: 2 # Run 2 storage servers
      minFreeSpacePercent: 5 # Stop writing if disk is 95% full
    ```

## 2. S3 Compatibility
**Description:** Enable an S3-compatible gateway. This allows apps written for AWS S3 to save files to your cluster by just changing the endpoint URL.

*   **Related Values:** `s3.enabled`, `s3.port`, `s3.enableAuth`
*   **Related Features:**
    *   *Dependent:* **Filer** (S3 usually relies on Filer to manage bucket metadata).
*   **Example:**
    ```yaml
    s3:
      enabled: true
      enableAuth: false # Set true to require Access Key / Secret Key
    ```

## 3. The Filer (File System View)
**Description:** Without the Filer, SeaweedFS is just a blob store (IDs only). The Filer gives you filenames, folders, and directories.

*   **Related Values:** `filer.enabled`, `filer.replicas`
*   **Related Features:**
    *   *Dependent:* **Database Backend** (See Section 7).
*   **Example:**
    ```yaml
    filer:
      enabled: true
      redirectOnRead: true # Clients read directly from Volume servers (faster)
    ```

## 4. Persistence (Saving Data)
**Description:** By default, this chart might try to use `hostPath` (writing directly to the Kubernetes node's disk) or `emptyDir` (temporary). For production, you usually want `persistentVolumeClaim` (PVC) so data survives if a node dies.

*   **Related Values:** `volume.dataDirs`, `master.data`, `filer.data`
*   **Related Features:** None.
*   **Example:**
    ```yaml
    volume:
      dataDirs:
        - name: data
          type: "persistentVolumeClaim" # Request storage from K8s
          size: "1Ti"
          storageClass: "standard"
    master:
      data:
        type: "persistentVolumeClaim"
        size: "10Gi"
    ```

## 5. Replication (Data Safety)
**Description:** SeaweedFS has a unique replication setting formatted as `XYZ`.
*   `000`: No replication.
*   `001`: 1 extra copy on a different server in the same rack.
*   `010`: 1 extra copy in a different rack.

*   **Related Values:** `global.enableReplication`, `global.replicationPlacement`, `master.defaultReplication`
*   **Related Features:** None.
*   **Example:**
    ```yaml
    global:
      enableReplication: true
      replicationPlacement: "001" # Keep 1 backup copy on a different server
    ```

## 6. All-In-One Mode
**Description:** Disables the separate Master/Volume/Filer pods and runs a single Pod containing everything. Perfect for local testing or very small setups.

*   **Related Values:** `allInOne.enabled`
*   **Related Features:**
    *   *Exclusive:* If you enable this, you usually disable `master`, `volume`, and `filer` to save resources.
*   **Example:**
    ```yaml
    allInOne:
      enabled: true
    master:
      enabled: false
    volume:
      enabled: false
    filer:
      enabled: false
    ```

## 7. External Database (High Availability Filer)
**Description:** The Filer keeps the catalog of "Filename -> File ID". By default, it uses a small internal database (LevelDB). If you want multiple Filers (HA), they must share an external database (like MySQL or Postgres).

*   **Related Values:** `filer.extraEnvironmentVars`
*   **Related Features:**
    *   *Prerequisite:* An existing MySQL/Postgres database running elsewhere.
*   **Example:**
    ```yaml
    filer:
      extraEnvironmentVars:
        WEED_MYSQL_ENABLED: "true"
        WEED_MYSQL_HOSTNAME: "my-sql-service"
        WEED_MYSQL_PASSWORD: "password"
        # Disable the default LevelDB
        WEED_LEVELDB2_ENABLED: "false"
    ```

## 8. Security & Authentication
**Description:** Secure the S3 interface and internal communications.

*   **Related Values:** `global.securityConfig`, `s3.existingConfigSecret`, `admin.secret`
*   **Related Features:** None.
*   **Example:**
    ```yaml
    s3:
      enabled: true
      enableAuth: true
      existingConfigSecret: "my-s3-creds" # You must create this K8s secret manually first
    global:
      enableSecurity: true # Enables gRPC TLS between components
    ```

## 9. Topology Awareness
**Description:** If your Kubernetes cluster spans multiple Data Centers (DC) or Racks, you can tell SeaweedFS where nodes are. This ensures replication doesn't put all copies in the same room.

*   **Related Values:** `volume.dataCenter`, `volume.rack`, `volume.nodeSelector`
*   **Related Features:** None.
*   **Example:**
    ```yaml
    # You might need to install the chart twice with different values
    # for different zones, or use the "volumes" map.
    volume:
      dataCenter: "us-east-1"
      rack: "rack-a"
    ```

## 10. Maintenance (Admin & Workers)
**Description:**
*   **Admin:** A UI dashboard to view cluster health.
*   **Worker:** Background processes that "vacuum" (delete old data) and balance disks.

*   **Related Values:** `admin.enabled`, `worker.enabled`, `worker.capabilities`
*   **Related Features:** None.
*   **Example:**
    ```yaml
    admin:
      enabled: true # Dashboard at port 23646
    worker:
      enabled: true
      capabilities: "vacuum,balance" # Allow it to clean and move data
    ```

## 11. SFTP Access
**Description:** Provides an SFTP server interface to upload files.

*   **Related Values:** `sftp.enabled`, `sftp.user`, `sftp.password`
*   **Related Features:** None.
*   **Example:**
    ```yaml
    sftp:
      enabled: true
      port: 2022
    ```

---

# Important Context & Gotchas

### 1. The "HostPath" Default
In the `values.yaml`, you will see:
```yaml
data:
  type: "hostPath"
  hostPathPrefix: /ssd
```
**Warning:** This configuration ties your data to a specific physical node in your cluster. If that node crashes and is replaced, **you lose your data**.
For production, you **must** change `type` to `persistentVolumeClaim` (PVC) or ensure you have strict Node Affinity and local disk management strategies in place.

### 2. Filer Store Performance (LevelDB vs MySQL)
The default installation uses **LevelDB** inside the Filer pod.
*   **Pros:** Fast, zero configuration.
*   **Cons:** You cannot run multiple Filer replicas (no High Availability). If the pod dies, the file catalog is inaccessible until it restarts.
*   **Recommendation:** For Production, disable LevelDB and configure `extraEnvironmentVars` to point to an external Postgres, MySQL, or Etcd cluster.

### 3. Updates and Rolling Restarts
SeaweedFS components (Master/Volume) are StatefulSets.
*   **Update Partition:** The values `updatePartition: 0` are used to control manual rolling updates.
*   **Strategy:** Be careful when upgrading the chart. If using `hostPath`, Kubernetes might schedule the pod on a new node during an upgrade, detaching it from its data on the old node.

### 4. Database Initialization
If you use a SQL backend (MySQL/Postgres) for the Filer, you usually need to create the table manually *before* the Filer starts.
**SQL Command:**
```sql
CREATE TABLE IF NOT EXISTS `filemeta` (
  `dirhash`   BIGINT NOT NULL,
  `name`      VARCHAR(766) NOT NULL,
  `directory` TEXT NOT NULL,
  `meta`      LONGBLOB,
  PRIMARY KEY (`dirhash`, `name`)
) DEFAULT CHARSET=utf8mb4;
```