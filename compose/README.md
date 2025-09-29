Of course. Here is the detailed information that was removed from the main `README.md`, now formatted as a new, self-contained `README.md` for your `compose/` directory.

This file provides the necessary rules and instructions for any developer working within this part of the repository.

***

# Local Development with Compose

This directory provides a way to run services locally for development and testing using Podman Compose. The goal is to provide a fast, isolated, and easy-to-use environment on a local machine that mirrors the production architecture as closely as possible.

## Guiding Principles for the `compose` Directory

To ensure modularity and ease of use, every service within the `compose` directory **must** adhere to the following principles. This creates a predictable and scalable local development experience.

**1. Service-per-Folder Structure**
   *   Each service resides in its own dedicated folder.
   *   The folder name **must** be the name of the main service it provides (e.g., `ollama`, `open-webui`, `postgres-db`).

**2. Required Files**
   *   Every service folder **must** contain a `compose.yaml` file.
   *   Every service folder **must** contain its own `README.md` file explaining how to use it.

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
2.  It is forbidden to link to an internal compose file (e.g., `../base-service/internal-details.yaml`). This ensures that services are loosely coupled and respect each other's boundaries.

**5. Comprehensive Service `README.md`**
    
   The `README.md` for each individual service folder must document everything a developer needs to know to run it. This includes:
   *   A brief description of the service.
   *   **Prerequisites:** Any required host-machine setup (e.g., "Requires NVIDIA Container Toolkit," "Requires Docker buildx").
   *   **Usage:** Step-by-step instructions on how to start, perform any initial setup (if needed), and stop the service.
   *   **Data Persistence:** A clear explanation of how data is managed (e.g., named volumes vs. local bind mounts) and how to back up or clear it.

---

## Practical Guide: Running an Application Service Locally

Follow these steps to run any application defined in this directory.

1.  **Navigate to the Service Directory:**
    Go to the folder of the application you want to run.
    ```sh
    # Replace 'app-service-a' with the name of the service you want to run
    cd compose/app-service-a/
    ```

2.  **Read the Documentation:**
    Before running anything, open and read the `README.md` in this folder to ensure you have met all prerequisites and understand what the service does.

3.  **Start the Application Stack:**
    The `compose.yaml` file in the service's directory is the only one you need to interact with. It will automatically pull in all required dependencies.
    ```sh
    podman-compose up -d
    ```

4.  **Stop the Stack:**
    When you are finished, run the following command from the same service directory to stop and remove all related containers defined in the stack.
    ```sh
    podman-compose down
    ```