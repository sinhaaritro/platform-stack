# GPU Test Harness Service

This service provides a pre-configured environment for running one-shot, GPU-accelerated commands for testing and diagnostics.

Its primary purpose is to verify that the host machine's GPU, drivers, and container toolkit are all functioning correctly.

## Prerequisites

- NVIDIA drivers installed on the host.
- NVIDIA Container Toolkit installed and configured for Podman.

## Usage

This service is **not** meant to be started with `podman-compose up`. Instead, you use `podman-compose run` to execute a command inside the pre-configured container.

`podman-compose run` automatically cleans up the container after the command finishes, replicating the `--rm` behavior.

1.  **Navigate to this Directory:**
    ```sh
    cd compose/ubuntu-with-nvidia-gpu/
    ```

2.  **Run the `nvidia-smi` Command:**
    Specify the service name (`ubuntu-with-nvidia-gpu`) followed by the command you want to execute (`nvidia-smi`).
    ```sh
    podman-compose run ubuntu-with-nvidia-gpu nvidia-smi
    ```

    You should see the standard `nvidia-smi` output, listing your GPUs and driver versions.

3.  **Run Another Command:**
    You can run any command inside the container. For example, to get a shell:
    ```sh
    podman-compose run ubuntu-with-nvidia-gpu bash
    ```