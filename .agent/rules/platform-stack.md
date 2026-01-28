---
trigger: always_on
---

### 3. Project Objectives
The goal is to create a seamless, automated infrastructure that:
*   **Manages Hybrid Environments:** Orchestrates resources across on-premise (Proxmox) and Cloud (AWS, Oracle, Google, Azure).
*   **Is Purely Code-Driven:** Zero GUI interactions allowed after the initial bootstrap.
*   **Is Secure:** Internet access is restricted and secured via Cloudflare Tunnels; all nodes are interconnected (likely via a mesh VPN or similar, though not explicitly named, the requirement is "connected to each other").
*   **Is Multi-Tenant:** Segregates workloads for Personal, Business (Multiple entities), App Dev, Media, and AI.

### 4. Technical Stack & Flow
The architecture is defined as follows:

*   **Source of Truth:** Main Git Repository.
*   **Trigger:** `git push` triggers the pipeline.
*   **Orchestration/CI:** GitHub Actions (or open-source equivalent) triggers the chain; execution happens on a local **Code Server**.
*   **Provisioning:** **OpenTofu** (for VMs and LXC containers).
*   **Configuration Management:** **Ansible** (OS setup, K8s prep).
*   **Secret Management:** **Ansible Vault** (encrypting OpenTofu states and Ansible vars).
*   **Kubernetes:**
    *   **Kind:** For Development environments.
    *   **Kubeadm:** For Production clusters.
*   **GitOps:** **ArgoCD** (Monitoring repo for K8s application changes).
*   **Task Management:** **Taskfile** (for defining command shortcuts).
*   **Ingress/Networking:** **Cloudflare Tunnel** (exposing services securely).