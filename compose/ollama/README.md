# Ollama Service

This service provides the core Ollama AI engine for the platform.
Currently works with NVIDIA GPU only

## Prerequisites

Before running, you **must** have the correct GPU drivers and container toolkit installed on your host machine. This service will not function correctly without them.

- **NVIDIA Users:** Install the [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html).
- **AMD ROCm Users:** Ensure you have a working ROCm setup for containers.

## Networking

This service connects to the shared `stratum_net` network. This allows any other service on the platform to access it by using the hostname `ollama` and port `11434`.

## Data Persistence

This service uses a Podman-managed named volume called `ollama_data` to store downloaded models.

- This volume **persists** even when you run `podman-compose down`.
- To completely wipe all models and start fresh, you must run `down` with the `-v` flag: `podman-compose down -v`

## Usage

1.  **Navigate to this Directory:**
    ```sh
    cd compose/ollama/
    ```

2.  **Start the Service:**
    This command will also implicitly create the shared `stratum_net` network if it doesn't already exist, thanks to the `include` directive.
    ```sh
    podman-compose up -d
    ```

3.  **Stop the Service:**
    ```sh
    podman-compose down
    ```
