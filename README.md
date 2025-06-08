
# Platform Stack

This repository contains the complete, end-to-end infrastructure, configuration, and application code for our suite of services. The goal of this platform is to provide a standardized, automated, and scalable foundation for development, staging, and production environments.

## Core Philosophy

This platform is built on a "separation of concerns" principle, where each layer of the stack is managed by a dedicated tool. This creates a clear, maintainable, and scalable system.

*   **Infrastructure as Code (IaC):** The physical or virtual infrastructure is defined declaratively using **Terraform**.
*   **Configuration Management:** The state of our servers is managed procedurally using **Ansible**.
*   **Container Orchestration:** Production workloads are deployed and managed at scale using **Kubernetes**.
*   **Local Development Parity:** Developers can run a complete, multi-service application on their local machine using **Podman Compose**.

---

## Directory Structure

The repository is organized into four main directories, each representing a distinct layer of the platform.

```
platform-stack/
├── terraform/         # Layer 1: Provisions the core infrastructure (VMs, networks, etc.).
├── ansible/           # Layer 2: Configures the provisioned servers (installs software, sets up K8s).
├── k8s/               # Layer 3: Deploys applications to the Kubernetes cluster for production.
└── compose/           # Layer 4: Defines services for local development on a single machine.
```

---

## The Four Layers of the Platform

### Layer 1: Infrastructure Provisioning with Terraform
*   **Purpose:** To create the raw infrastructure in a cloud provider (e.g., AWS, GCP, Azure).
*   **Location:** `terraform/`

### Layer 2: Server Configuration with Ansible
*   **Purpose:** To take the raw servers from Terraform and configure them into a consistent, ready-to-use state.
*   **Location:** `ansible/`

### Layer 3: Production Orchestration with Kubernetes
*   **Purpose:** To deploy, manage, and scale our containerized applications in a resilient, production-grade environment.
*   **Location:** `k8s/`

### Layer 4: Local Development & Testing with Compose
*   **Purpose:** To provide developers with a fast, isolated, and easy-to-use environment on their local machine that mirrors the production architecture.
*   **Location:** `compose/`

#### Guiding Principles for the `compose` Directory
To ensure modularity and ease of use, every service within the `compose` directory **must** adhere to the following principles:

**1. Service-per-Folder Structure**
   *   Each service resides in its own dedicated folder.
   *   The folder name **must** be the name of the main service it provides (e.g., `ollama`, `open-webui`, `postgres-db`).

**2. Required Files**
   *   Every service folder **must** contain a `compose.yaml` file.
   *   Every service folder **must** contain a `README.md` file.

**3. The 'Public API' vs. 'Internal Implementation'**
   *   The `compose.yaml` file is the **public entry point** for a service. This is the *only* file that can be included by other services.
   *   A service may have additional internal compose files (e.g., `database-setup.yaml`, `logging-sidecar.yaml`) for its own complex setup. These are considered **private implementation details** and **must not** be included by any external service. They can only be included by the main `compose.yaml` within the *same folder*.

**4. Dependency Management Contract**
1.  When a service (`app-service-A`) depends on another (`base-service`), its `compose.yaml` **must** include the dependency using a relative path to the dependency's public entry point.
	```yaml
     # In compose/app-service-A/compose.yaml
     include:
       - ../base-service/compose.yaml
	```
2.  It is forbidden to link to an internal compose file (e.g., `../base-service/internal-details.yaml`).

**5. Comprehensive `README.md`**
    
   The `README.md` for each service must document everything a developer needs to run it. This includes:
   *   A brief description of the service.
   *   **Prerequisites:** Any required host-machine setup (e.g., "Requires NVIDIA Container Toolkit," "Requires Docker buildx").
   *   **Usage:** Step-by-step instructions on how to start, setup (if needed), and stop the service.
   *   **Data Persistence:** Explanation of how data is managed (e.g., named volumes vs. local bind mounts) and how to clear it.

#### Practical Guide: Running an Application Service Locally
1.  **Navigate to the Service Directory:**
    Go to the folder of the application you want to run within the `compose` directory.
    ```sh
    # Replace 'app-service-A' with the name of the service you want to run
    cd compose/app-service-A/
    ```

2.  **Read the Documentation:**
    Before running anything, open and read the `README.md` in this folder to ensure you have met all prerequisites.

3.  **Start the Application Stack:**
    The `compose.yaml` file in this directory is the only one you need to interact with.
    ```sh
    podman-compose up -d
    ```
    This single command will start your chosen application and all of its declared dependencies in the correct order.

4.  **Stop the Stack:**
    When you are finished, run the following command from the same service directory to stop and remove all related containers.
    ```sh
    podman-compose down
    ```
