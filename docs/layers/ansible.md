# Add in previous Step of kubeadm install
## Install the missing dependency
Kubernetes uses `conntrack` package to track network connections (NAT) for the pods.
`socat` package is often needed for port forwarding debugging later
```bash
sudo apt update
sudo apt install -y conntrack socat
```

## Fix the IP Address mapping
`127.0.1.1` is a "loopback" address (internal only).
If you initialize the cluster now, the security certificates will be valid only for localhost. When you later try to join "Cluster 2" or "Cluster 3" to this Management Cluster, they will try to talk to `k8s-mgmt-cp`, but since that name resolves to 127.0.1.1, they will try to talk to themselves and fail.

1. Check your real IP:
    ```bash
    ip -4 addr show | grep -v "127.0.0.1" | grep -v "127.0.1.1"
    ```

2. Map to actual LAN IP in Hosts file
    ```bash
    sudo nano /etc/hosts
    ```
    Find the line:
    `127.0.1.1 k8s-mgmt-cp`
    Change it to:
    `YOUR_REAL_IP k8s-mgmt-cp`
    (Example: `192.168.1.50 k8s-mgmt-cp`)
    Save and exit


# Current Role
### Step 1: Create the "Virtual" Identity
We need to map a name to your IP address. We will call the control plane endpoint `k8s-mgmt-cp`.

**Why:** This decouples the cluster configuration from your physical IP. If you add a Load Balancer later for HA, you only need to update this DNS mapping, rather than destroying the cluster.

```bash
# Get current IP and map it to the virtual name in /etc/hosts
echo "$(hostname -i | awk '{print $1}') k8s-mgmt-cp" | sudo tee -a /etc/hosts
```

### Step 2: Pre-Download Kubernetes Images
**Why:** `kubeadm init` tries to download large container images (API Server, Etcd, CoreDNS) during execution. If your internet blips, it fails. Doing this separately ensures we have everything local first.

```bash
sudo kubeadm config images pull
```

### Step 3: Initialize the Cluster
**Why:** This is the main command. It:
1.  Generates Certificates (CA, API, Etcd).
2.  Generates Kubeconfig files.
3.  Starts the Control Plane Static Pods.
4.  **`--control-plane-endpoint`**: Tells the cluster to identify itself as `k8s-mgmt-cp` (essential for HA).
5.  **`--pod-network-cidr`**: Reserves this IP range for internal Pod communication (Required for Calico CNI).

```bash
sudo kubeadm init \
  --control-plane-endpoint="k8s-mgmt-cp:6443" \
  --upload-certs \
  --pod-network-cidr=192.168.0.0/16
```

> **STOP & SAVE:** Once this completes, it will print a "Join Command" at the bottom. **Copy that output to a notepad.** You will need it if you ever add a second node.

### Step 4: Authorize Your User
**Why:** The cluster is running as `root`. Your standard user (`dev`) doesn't have the permission keys (the `admin.conf` file) to talk to it yet. This copies the keys to your home directory.

```bash
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

### Step 5: Install the Network Driver (CNI)
**Why:** Right now, your node status is `NotReady` because the "digital wires" aren't connected. We are installing **Calico**, a standard, robust networking plugin that handles IP assignment and security policies.
Also, without Calico, the cluster has no network. Without a network, ArgoCD (which runs inside a Pod) cannot talk to the Internet to pull your Git repo. You cannot GitOps your way out of a broken network.

```bash
# 1. Download the official manifest (Store in infrastructure/bootstrap/networking)
curl https://raw.githubusercontent.com/projectcalico/calico/v3.29.1/manifests/calico.yaml -o infrastructure/bootstrap/networking/calico.yaml

# 2. Configure the CIDR (Uncomment and set to 192.168.0.0/16)
# This ensures Calico knows exactly which IP range to use for Pods.
sed -i -e 's?# - name: CALICO_IPV4POOL_CIDR?- name: CALICO_IPV4POOL_CIDR?g' \
       -e 's?#   value: "192.168.0.0/16"?  value: "192.168.0.0/16"?g' \
       infrastructure/bootstrap/networking/calico.yaml

# 3. Apply the local file
kubectl apply -f infrastructure/bootstrap/networking/calico.yaml
```

### Step 6: Allow Workloads on the Control Plane (Untaint)
**Why:** By default, Kubernetes says "I am a Manager (Control Plane), I do not run applications." Since you only have 1 node, nothing will run unless we remove this restriction (called a "Taint").

```bash
kubectl taint nodes --all node-role.kubernetes.io/control-plane-
```

# ArgoCD
### Step 7: Install ArgoCD
Keep it on NodePort. Sysadmins often keep the Management UI (ArgoCD) on a specific NodePort (e.g., 30080) restricted by firewall, as a "Backdoor" in case the main Ingress crashes.
We need get the HA version and see if we can switch
```
# 1. Create the namespace for ArgoCD
kubectl create namespace argocd

# 2. Download the official manifest
curl https://raw.githubusercontent.com/argoproj/argo-cd/v2.13.2/manifests/install.yaml -o infrastructure/bootstrap/gitops/argocd.yaml

# 3. Apply the local file
kubectl apply -n argocd -f infrastructure/bootstrap/gitops/argocd.yaml
```

### Retrieve the ArgoCD Password
User name is `admin`
```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo
```




```
Your Kubernetes control-plane has initialized successfully!

To start using your cluster, you need to run the following as a regular user:

  mkdir -p $HOME/.kube
  sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
  sudo chown $(id -u):$(id -g) $HOME/.kube/config

Alternatively, if you are the root user, you can run:

  export KUBECONFIG=/etc/kubernetes/admin.conf

You should now deploy a pod network to the cluster.
Run "kubectl apply -f [podnetwork].yaml" with one of the options listed at:
  https://kubernetes.io/docs/concepts/cluster-administration/addons/

You can now join any number of the control-plane node running the following command on each as root:

  kubeadm join k8s-mgmt-cp:6443 --token 66nnj2.puaittl9ehnaukvx \
        --discovery-token-ca-cert-hash sha256:ba06a12ade0ebb45753791a19921177c1e482c13fad479777797e6efdd5dc424 \
        --control-plane --certificate-key 1cc09772432ff9db76f4aa48c070071a941c07c66c931a4e18c1360cf58208ef

Please note that the certificate-key gives access to cluster sensitive data, keep it secret!
As a safeguard, uploaded-certs will be deleted in two hours; If necessary, you can use
"kubeadm init phase upload-certs --upload-certs" to reload certs afterward.

Then you can join any number of worker nodes by running the following on each as root:

kubeadm join k8s-mgmt-cp:6443 --token 66nnj2.puaittl9ehnaukvx \
        --discovery-token-ca-cert-hash sha256:ba06a12ade0ebb45753791a19921177c1e482c13fad479777797e6efdd5dc424
dev@ruth-02:~$
```


```
dev@ruth-02:~$ kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo
1Z2wujEZTnTw4Zg4
```