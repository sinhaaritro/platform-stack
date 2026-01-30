# MinIO Object Storage

MinIO provides S3-compatible object storage for the Platform Stack. It is primarily used as the backend for Loki's `SimpleScalable` deployment mode.

## Architecture
- **Storage Backend**: Built on top of **Longhorn** block storage for data persistence and replication.
- **Access**: Accessible internally via `minio.storage.svc:9000`.
- **Initialization**: Automatically creates the necessary buckets for Loki (`loki-chunks`, `loki-ruler`).

## Configuration Highlights
- **User**: admin
- **Persistence**: 20Gi Longhorn Volume
- **Service Type**: ClusterIP (Port 9000 API, Port 9090 Console)
