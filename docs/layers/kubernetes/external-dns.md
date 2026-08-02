
Here is a comprehensive documentation guide for **External-DNS**, tailored for a Kubernetes beginner, based on the provided Helm chart configuration and current industry standards.

---

# Introduction to External-DNS

**External-DNS** is a Kubernetes application that automates the management of external Domain Name System (DNS) records.

When you deploy services or applications in Kubernetes, they are often assigned dynamic IP addresses or Load Balancers. To make these applications accessible via a human-readable domain name (like `app.example.com`), you traditionally have to manually log into your DNS provider (such as AWS Route53, Google Cloud DNS, or Azure DNS) and update the records to point to the new Kubernetes resources.

External-DNS runs as a pod inside your cluster. It monitors Kubernetes resources (Services and Ingresses), discovers the hostnames you have requested, and automatically communicates with your DNS provider API to create, update, or delete DNS records to match the state of your cluster.

### How It Works
1.  **Observe:** It watches the Kubernetes API for new `Ingress`, `Service`, or `Gateway API` resources.
2.  **Calculate:** It determines the desired list of DNS records based on hostnames defined in those resources.
3.  **Connect:** It connects to your configured DNS Provider (defined in `provider`).
4.  **Action:** It applies changes (ADD, UPDATE, DELETE) to the DNS provider to ensure the real-world DNS records match your Kubernetes configuration.

---

# Comprehensive Feature List

Below is a list of every major feature available in External-DNS, explained with its function and the corresponding value from your `values.yaml` file.

### 1. Multi-Provider Support
External-DNS supports a wide variety of DNS providers. You do not need to write custom scripts; you simply tell it which provider you use.
*   **Description:** Configures the backend integration that External-DNS will use to publish records.
*   **Related Values:**
    *   `provider.name`: The name of the cloud provider (e.g., `aws`, `google`, `azure`, `cloudflare`).
    *   `provider.webhook`: Used if your provider is not supported natively; allows the use of a sidecar container to bridge the connection.

### 2. DNS Record Ownership (The Registry)
To prevent External-DNS from deleting records it did not create (e.g., existing manual records), it uses a concept called a "Registry."
*   **Description:** External-DNS marks the records it creates so it knows it owns them. The most common method is creating a `TXT` record alongside the `A` record containing a unique ID.
*   **Related Values:**
    *   `registry`: usually set to `txt`.
    *   `txtOwnerId`: A unique string identifying this specific Kubernetes cluster. This ensures that if you have multiple clusters managing the same domain, they don't overwrite each other's records.
    *   `txtPrefix` / `txtSuffix`: Adds a specific prefix or suffix to the ownership TXT record names to avoid naming collisions.

### 3. Synchronization Policies
You can control how aggressive External-DNS is when modifying records.
*   **Description:** Defines the permissions External-DNS has regarding modifying existing DNS records.
*   **Related Values:**
    *   `policy`:
        *   `sync`: Allows full creation and deletion of records (External-DNS makes the DNS provider exactly match the cluster).
        *   `upsert-only`: Allows creation and updates but **prevents deletion**. This is safer for beginners to ensure no records are accidentally lost.
        *   `create-only`: Only creates new records; never updates or deletes.

### 4. Resource Source Selection
You can decide which Kubernetes resources trigger DNS updates.
*   **Description:** Tells External-DNS which API objects to monitor for hostnames.
*   **Related Values:**
    *   `sources`: A list including `service`, `ingress`, or `gateway-httproute`.
    *   `gatewayNamespace`: If using the Kubernetes Gateway API, this defines specifically where to look.

### 5. Domain Filtering
You likely don't want External-DNS scanning every possible domain associated with your account.
*   **Description:** Restricts External-DNS to only manage specific domains or exclude specific subdomains.
*   **Related Values:**
    *   `domainFilters`: A list of allowed domains (e.g., `["example.com"]`). It will ignore resources requesting `google.com`.
    *   `excludeDomains`: A list of domains explicitly ignored.

### 6. Resource Filtering (Label & Annotation)
You may want to deploy External-DNS but only have it act on specific Services or Ingresses, rather than all of them.
*   **Description:** Filters which specific Kubernetes objects are processed based on their metadata.
*   **Related Values:**
    *   `labelFilter`: Only process resources with a specific label.
    *   `annotationFilter`: Only process resources with a specific annotation.

### 7. Event-Based Triggering
*   **Description:** By default, External-DNS polls on an interval. You can configure it to react immediately when a Kubernetes change happens.
*   **Related Values:**
    *   `interval`: How often to poll (default `1m`).
    *   `triggerLoopOnEvent`: If `true`, a change in a Service/Ingress triggers an immediate DNS update attempt, rather than waiting for the next interval.

### 8. Namespaced Operation
*   **Description:** Run External-DNS restricted to a specific namespace rather than having cluster-wide permissions.
*   **Related Values:**
    *   `namespaced`: If `true`, restricts the scope to the namespace the pod is running in.

### 9. Deployment Strategy & Availability
*   **Description:** Controls how the application performs updates and maintains availability.
*   **Related Values:**
    *   `deploymentStrategy`: Typically `Recreate` or `RollingUpdate`.
    *   `livenessProbe` / `readinessProbe`: Health checks to ensure the pod is functioning correctly.
    *   `resources`: CPU and Memory limits/requests.
    *   `securityContext`: Defines privilege levels (e.g., `runAsNonRoot: true`).

### 10. RBAC (Role-Based Access Control)
*   **Description:** Automatically creates the necessary Kubernetes permissions for the application to read Services and Ingresses.
*   **Related Values:**
    *   `serviceAccount.create`: Generates a Service Account identity.
    *   `rbac.create`: Creates ClusterRoles and Bindings granting permission to read K8s API resources.

### 11. Monitoring and Metrics
*   **Description:** Exposes internal metrics (like how many DNS requests failed) for collection by Prometheus.
*   **Related Values:**
    *   `serviceMonitor.enabled`: Creates a `ServiceMonitor` resource for the Prometheus Operator.
    *   `service.port`: The port where metrics and health checks are exposed (default `7979`).

---

# Related & Sister Technologies

To fully understand where External-DNS fits, it is helpful to know the tools it interacts with or is often deployed alongside.

### Dependent Features (External-DNS relies on these)
1.  **Ingress Controllers (e.g., NGINX, Traefik, Istio):**
    *   External-DNS looks at **Ingress** resources managed by these controllers. The Ingress provides the Hostname (`app.example.com`), and the Controller provides the IP address (LoadBalancer IP). External-DNS bridges these two pieces of information to the DNS provider.
2.  **CoreDNS (Internal DNS):**
    *   Kubernetes has its own internal DNS (usually CoreDNS) for `service-name.namespace.svc.cluster.local`. External-DNS does **not** replace CoreDNS. CoreDNS handles internal traffic; External-DNS handles public/external traffic.

### Sister Features (Often used together)
1.  **cert-manager:**
    *   While External-DNS automates the **DNS** records (A/CNAME), `cert-manager` automates **SSL/TLS Certificates** (HTTPS).
    *   **Workflow:** You deploy an Ingress. External-DNS sets up the domain name so traffic reaches the cluster. `cert-manager` detects the new domain, requests a certificate from Let's Encrypt, and secures the connection.

### Alternate Features
1.  **Reflector:**
    *   Some users write scripts to reflect Kubernetes IP changes to DNS, but these are generally manual or fragile compared to External-DNS.
2.  **Operator Patterns:**
    *   Some specific cloud operators (like Crossplane or Google Config Connector) can manage DNS records as Kubernetes resources, but External-DNS remains the standard for synchronizing Ingress/Service hostnames automatically.