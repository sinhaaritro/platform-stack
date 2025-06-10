# n8n Automation Service

This service runs n8n, a powerful workflow automation tool.

## Prerequisites

This service directly depends on the `postgres` service. It has no additional host-level prerequisites.

## Usage

1.  **Navigate to this Directory:**
    ```sh
    cd compose/n8n/
    ```

2.  **Customize Configuration (Optional):**
    Edit the `.env` file in this directory to change the port or database credentials.

3.  **Start the Full Stack:**
    This command will automatically start both the `n8n` service and the `postgres` database in the correct order.
    ```sh
    podman-compose up -d
    ```

4.  **Access n8n:**
    Open your browser and navigate to the address below. You will be prompted to create an owner account on your first visit.
    
    **http://localhost:5678**

5.  **Stop the Stack:**
    This command will stop and remove both the `n8n` and `postgres` containers. The data will persist in their respective volumes.
    ```sh
    podman-compose down
    ```