# Base MongoDB Service

This service provides a generic MongoDB database for the platform. It is designed to be included as a dependency by application services.

## Networking

This service connects to the shared `stratum_net` and is accessible to other services at the hostname `mongo` on the default port `27017`.

## Data Persistence

This service uses a managed volume named `mongodb_data` to persist database files. To wipe all data, run `podman-compose down -v`.