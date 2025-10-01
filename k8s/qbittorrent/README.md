
---

### **Notes for qBittorrent Proxy Setup**

This guide assumes you have already deployed the `lscr.io/linuxserver/qbittorrent` container to Kubernetes.

#### **Objective 1:**
Successfully logged into the Web UI for the first time

The user is admin
The password is randomly generated so the only way to see it is
```bash
# Get the pod name
QBIT_POD=$(kubectl get pods -n qbittorrent -l app=qbittorrent -o jsonpath='{.items[0].metadata.name}')
# Get the logs
kubectl logs -n qbittorrent $QBIT_POD
```

#### **Objective 2:**
Configure the running qBittorrent instance to route all its traffic through the Gluetun SOCKS5 proxy located at `192.168.0.28:1080`.

---
#### **Step 1: Open qBittorrent Connection Settings**

1.  Navigate to the qBittorrent Web UI at **http://qbittorrent.localhost**.
2.  Log in with your new password.
3.  Go to the top menu and select **Tools -> Options**. (It looks like a gear icon).
4.  In the Options window, click on the **"Connection"** icon on the left-hand side.

---
#### **Step 2: Configure the SOCKS5 Proxy Server**

This is the most critical section.

1.  Scroll down to the **"Proxy Server"** section.
2.  **Type:** Select **`SOCKS5`** from the dropdown menu.
3.  **Host:** Enter the IP address of your Gluetun LXC container: **`192.168.0.28`**.
4.  **Port:** Enter the port that Gluetun is listening on: **`1080`**.
5.  **Authentication:** Leave the "Authentication" checkbox **unchecked**. The `qmcgaw/gluetun` container does not require a username/password for its proxy by default.

---
#### **Step 3: Configure What to Proxy**

This section tells qBittorrent which of its traffic should be sent through the proxy. For maximum privacy, we will proxy everything.

1.  Check the box for **"Use proxy for peer connections"**.
2.  Check the box for **"Use proxy for host name lookup"**. This forces DNS requests through the VPN as well.
3.  Check the box for **"Use proxy for tracker connections"**.
4.  Check the box for **"Use proxy for RSS feed"** (if you plan to use it).

---
#### **Step 4: Save Settings**

1.  Click the **"Save"** button at the bottom right of the Options window.

The settings will apply immediately. From this point forward, all of qBittorrent's network activity will be routed through your Gluetun VPN container.

---
#### **(Optional) Step 5: Verify the Connection**

A good way to verify that your traffic is being tunneled is to add a known torrent tracking service that can show you the IP address it sees.

1.  Find a "Check My Torrent IP" magnet link or torrent file online.
2.  Add it to qBittorrent.
3.  The tracker status for that torrent will report the IP address it sees. This IP address should be the public IP of your **VPN server**, not your home IP address.