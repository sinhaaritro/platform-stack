# PostgreSQL Base Service

This service provides a generic PostgreSQL database. It is designed to be included as a dependency by other application services.

## Prerequisites

This service has no host-level prerequisites.

## Configuration

This service is configured via environment variables, which **must** be set in a `.env` file within the *application's* directory (e.g., `compose/n8n/.env`).

- `POSTGRES_USER`: The database username.
- `POSTGRES_PASSWORD`: The database password.
- `POSTGRES_DB`: The name of the database to create.

## Data Persistence

Database data is stored in a Podman-managed named volume. By default, the volume name is prefixed with the project name (e.g., `n8n_postgres_data`). This ensures that each application stack gets its own isolated database instance.

This volume persists when the stack is brought down. To completely wipe the database, run `podman-compose down -v`.