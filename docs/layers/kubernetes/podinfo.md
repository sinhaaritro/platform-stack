# Guide to the Podinfo Helm Chart

## Introduction
**What is this?**
*   **Podinfo:** Think of Podinfo as a "test dummy" web application. It is a small website written in the Go programming language. It is designed to show you how a modern cloud application behaves. It can display a welcome message, show you its internal "health," or intentionally break to test how your system recovers.
*   **Helm Chart:** Think of this as an "installer package" (like an `.exe` or `.dmg` file) for Kubernetes.
*   **values.yaml:** This is the "Settings" menu for the installer. By changing lines in this file, you change how the application runs without needing to write code.

This guide explains how to use the `values.yaml` file to unlock the specific features you need.

---

# Feature List

Here is the complete menu of what this chart can do, ordered from "Basic" to "Expert."

1.  **Visual Customization:** Change the colors, logo, and welcome message of the website.
2.  **Replication (High Availability):** Run multiple copies so the site never goes down.
3.  **External Access (Ingress):** Give the app a web address (domain name) like `www.example.com`.
4.  **Resource Management:** Control how much CPU and RAM the app consumes.
5.  **Chaos Engineering:** Intentionally break the app (errors, slowness) to test monitoring tools.
6.  **Backend Chaining:** Make Podinfo talk to *other* services to test internal networking.
7.  **Auto-Scaling (HPA):** Automatically add more copies when the app gets busy.
8.  **Caching (Redis):** Connect to a database to test storage.
9.  **Observability (Monitoring):** Connect to Prometheus or Linkerd to track traffic.
10. **Advanced Networking (Gateway API):** Use the next-generation replacement for Ingress.
11. **Security Hardening:** Lock down permissions and encrypt traffic (TLS).
12. **Scheduling & Affinity:** Force the app to run on specific servers (nodes).
13. **Custom Configuration:** Inject custom files or environment variables.

---

# Detailed Feature Breakdown

## 1. Visual Customization
**Description:** Change the look of the web interface. Useful for distinguishing between "Dev" (Blue) and "Prod" (Red) environments.

*   **Related Values:** `ui.color`, `ui.message`, `ui.logo`
*   **Related Features:** None.
*   **Example:**
    ```yaml
    ui:
      color: "#ff0000"         # Make the background Red
      message: "Production App" # Custom greeting
      logo: "https://my-company.com/logo.png"
    ```

## 2. Replication (High Availability)
**Description:** Decides how many "clones" of the app run simultaneously.

*   **Related Values:** `replicaCount`
*   **Related Features:**
    *   *Alternative:* **Auto-Scaling (HPA)**. (If HPA is enabled, `replicaCount` is ignored).
    *   *Dependent:* **Pod Disruption Budget**.
*   **Example:**
    ```yaml
    replicaCount: 3 # Run 3 copies at all times
    ```

## 3. External Access (Service & Ingress)
**Description:** How users reach the app. `Service` creates a stable IP inside the cluster; `Ingress` exposes it to the internet with a domain name.

*   **Related Values:** `service.type`, `service.httpPort`, `ingress.enabled`, `ingress.hosts`
*   **Related Features:**
    *   *Alternative:* **Gateway API (HTTPRoute)** (The newer way to do Ingress).
    *   *Related:* **TLS** (For HTTPS/SSL certificates).
*   **Example:**
    ```yaml
    service:
      type: ClusterIP      # Internal IP only
      httpPort: 80         # Listen on port 80

    ingress:
      enabled: true
      className: "nginx"   # Use Nginx controller
      hosts:
        - host: podinfo.example.com
          paths:
            - path: /
              pathType: ImplementationSpecific
    ```

## 4. Resource Management
**Description:** Set the minimum (Requests) and maximum (Limits) CPU and Memory the app can use.

*   **Related Values:** `resources.requests`, `resources.limits`
*   **Related Features:**
    *   *Dependent:* **Auto-Scaling (HPA)** (HPA requires CPU requests to be set to work).
*   **Example:**
    ```yaml
    resources:
      requests:
        cpu: 100m     # Minimum 10% of a core
        memory: 64Mi  # Minimum 64MB RAM
      limits:
        memory: 128Mi # Kill app if it exceeds 128MB
    ```

## 5. Chaos Engineering (Fault Injection)
**Description:** The "Crash Test" feature. Forces the app to behave badly to verify your alerts trigger.

*   **Related Values:** `faults.delay`, `faults.error`, `faults.unhealthy`, `faults.unready`
*   **Related Features:**
    *   *Related:* **Probes** (If you set `faults.unhealthy`, Kubernetes Probes will detect failure and restart the pod).
*   **Example:**
    ```yaml
    faults:
      delay: true  # Add random 0-5s delays to web requests
      error: true  # Make 33% of requests fail with Error 500
    ```

## 6. Backend Chaining
**Description:** Configures Podinfo to call *another* URL when you visit it. Used to test "Service A talking to Service B".

*   **Related Values:** `backend`, `backends`
*   **Related Features:** None.
*   **Example:**
    ```yaml
    # When I visit Podinfo, it will call Google before replying to me
    backend: "http://www.google.com"
    ```

## 7. Auto-Scaling (HPA)
**Description:** Automatically increases the number of pods when traffic (or CPU usage) gets high.

*   **Related Values:** `hpa.enabled`, `hpa.maxReplicas`, `hpa.cpu`
*   **Related Features:**
    *   *Overrides:* **Replication (replicaCount)**.
    *   *Prerequisite:* **Metrics Server** must be installed in the cluster.
*   **Example:**
    ```yaml
    hpa:
      enabled: true
      maxReplicas: 10
      cpu: 80 # Add pods if CPU usage > 80%
    ```

## 8. Caching (Redis)
**Description:** Podinfo can use Redis to store data. This chart can either connect to an existing Redis or install a new one for you.

*   **Related Values:** `cache`, `redis.enabled`, `redis.repository`
*   **Related Features:** None.
*   **Example:**
    ```yaml
    redis:
      enabled: true # Automatically installs a Redis container next to Podinfo
    ```

## 9. Observability (Monitoring)
**Description:** Configures the app to be watched by monitoring tools like Prometheus or Linkerd.

*   **Related Values:** `logLevel`, `serviceMonitor.enabled`, `linkerd.profile.enabled`
*   **Related Features:**
    *   *Prerequisite:* **Prometheus Operator** or **Linkerd** must be installed in the cluster.
*   **Example:**
    ```yaml
    logLevel: info
    serviceMonitor:
      enabled: true # Tell Prometheus to scrape metrics
      interval: 15s
    ```

## 10. Advanced Networking (Gateway API)
**Description:** Uses `HTTPRoute`, the modern replacement for Ingress.

*   **Related Values:** `httpRoute.enabled`, `httpRoute.parentRefs`, `httpRoute.hostnames`
*   **Related Features:**
    *   *Alternative:* **External Access (Ingress)**.
    *   *Prerequisite:* A Gateway Controller (like Istio, Cilium, or Gateway API).
*   **Example:**
    ```yaml
    httpRoute:
      enabled: true
      hostnames:
        - podinfo.local
      parentRefs:
        - name: my-gateway
    ```

## 11. Security Hardening
**Description:** Configurations to make the app secure (encryption and permissions).

*   **Related Values:** `tls.enabled`, `certificate.create`, `serviceAccount.enabled`, `securityContext`
*   **Related Features:**
    *   *Prerequisite:* **Cert-Manager** (for `certificate.create`).
*   **Example:**
    ```yaml
    # Enable internal encryption
    tls:
      enabled: true
      certPath: /data/cert
    
    # Don't run as Root user
    podSecurityContext:
      runAsUser: 1000
    ```

## 12. Scheduling & Affinity
**Description:** precise control over *where* the pods run (e.g., "Only on fast servers" or "Spread them out across zones").

*   **Related Values:** `nodeSelector`, `tolerations`, `topologySpreadConstraints`
*   **Related Features:** None.
*   **Example:**
    ```yaml
    # Only run on nodes labeled "disktype=ssd"
    nodeSelector:
      disktype: ssd
    
    # Ensure pods are spread across different zones (e.g. us-east-1a, 1b)
    topologySpreadConstraints:
      - maxSkew: 1
        topologyKey: topology.kubernetes.io/zone
        whenUnsatisfiable: DoNotSchedule
        labelSelector:
          matchLabels:
            app.kubernetes.io/name: podinfo
    ```

## 13. Custom Configuration & Operations
**Description:** Injecting custom files, arguments, or environment variables into the container.

*   **Related Values:** `extraArgs`, `extraEnvs`, `config.path`, `config.name`
*   **Related Features:** None.
*   **Example:**
    ```yaml
    # Add a custom environment variable
    extraEnvs:
      - name: MY_SPECIAL_KEY
        value: "secret-value"
    
    # Add a command line argument to the binary
    extraArgs:
      - "--api-rate-limit=100"
    ```
