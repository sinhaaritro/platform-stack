# Open WebUI Service

This service runs the Open WebUI, a user-friendly and feature-rich interface for interacting with LLMs running on the platform's central `ollama` service.

## Prerequisites

This service directly depends on the `ollama` service. Before running, you **must ensure you have met all prerequisites** documented in `compose/ollama/README.md`.

The most critical prerequisite is a correctly configured **host environment for GPU access** (e.g., NVIDIA Container Toolkit).

## Networking

This service connects to the shared `stratum_net` network. It automatically discovers and connects to the `ollama` service via the hostname `http://ollama:11434`.

## Data Persistence

This service uses a Podman-managed named volume called `openwebui_data` to store its own application data (user settings, chat history, etc.). This volume will persist when the stack is brought down.

## Usage

A developer only needs to interact with the files in this directory to run a complete stack, including the Ollama dependency.

1.  **Navigate to this Directory:**
    ```sh
    cd compose/open-webui/
    ```

2.  **Start the Full Stack:**
    This command will read the `include:` directives and automatically start both the `open-webui` service and the `ollama` service in the correct order.
    ```sh
    podman-compose up -d
    ```

3.  **Load a Model into Ollama:**
    The WebUI is now running, but it has no models to talk to. You must `exec` into the `ollama` container to load a model.
    ```sh
    podman exec ollama_service ollama run deepseek-r1:latest
    ```
    *(You can replace `deepseek-r1:latest` with any model you wish to use.)*

4.  **Access the WebUI:**
    Open your browser and navigate to the address below. The default port is `11435`, but it can be overridden by creating a `.env` file in this directory with the line `WEBUI_PORT=your_port`.
    
    **http://localhost:3000**

5.  **Stop the Stack:**
    This command will gracefully stop and remove both the `open-webui` and `ollama` containers.
    ```sh
    podman-compose down
    ```

## First-Time Setup: Default Admin User

To avoid the sign-up process during local development, you can create a default admin user automatically on the first run.

1.  **Create a `.env` file** in this directory (`compose/open-webui/`).
2.  **Add the following content** to the `.env` file:
    ```
    # Set the default admin user credentials
    WEBUI_DEFAULT_USER_EMAIL=admin@local.com
    WEBUI_DEFAULT_USER_PASSWORD=admin

    # You can also set a custom port
    WEBUI_PORT=11435
    ```

**IMPORTANT:** This only works when the database volume is created for the first time. If you have already run this service, you must destroy the old volume by running `podman-compose down -v` before starting it again.