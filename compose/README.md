# Local Development Environment (Layer 4)

This directory contains all services available for local development using Podman Compose.

## Core Networking Strategy: A Shared Network

To simplify development and service-to-service communication, all services in this directory operate on a **single, shared network** named `stratum_net`.

This network is defined once in the `compose/compose.yaml` file at this level.

### The Contract for All Services

Every service within this `compose/` directory **must** adhere to the following networking contract:

1.  **Include the Base Network Definition:** Each service's primary `compose.yaml` file must begin by including the top-level network definition file.

    ```yaml
    # In compose/my-service/compose.yaml
    include:
      - ../compose.yaml
    ```

2.  **Connect to the Shared Network:** Each service must explicitly connect to the shared network.

    ```yaml
    # In compose/my-service/compose.yaml
    services:
      my-service:
        # ... other service configuration ...
        networks:
          - stratum_net
    ```

This architecture ensures that any service can reliably communicate with any other service by simply using its service name as the hostname.
