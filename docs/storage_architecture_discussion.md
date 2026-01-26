# Storage Architecture Discussion: Generic Disk Mounting

This document outlines the reasoning behind the storage configuration strategy and addresses concerns regarding path specificity and variable placement.

## 1. Variable Placement: Why avoid `group_vars/vm.yml`?

You suggested moving the configuration to `ansible/roles/storage_setup/defaults/main.yml`. Here is the trade-off:

*   **Role Defaults (`defaults/main.yml`)**: These are the lowest priority variables in Ansible. They act as "safe fallbacks." If the role is used without any other configuration, these values are used.
*   **The Problem with Role Defaults for Paths**: If we put `/var/lib/longhorn` in the role's `defaults/main.yml`, then **every VM** that runs this role will attempt to use that path. This makes the "generic" role inherently "Longhorn-aware," which defeats the purpose of modularity.

**Recommendation**: The role's `defaults/main.yml` should only define an empty list (`storage_mounts: []`). This ensures that if the role is accidentally run on a VM without configuration, it does nothing (safe state).

## 2. The "Longhorn Path" Problem

You are correct: **A generic storage role should not know about Longhorn.**

If a VM is running a database, mounting the second disk to `/var/lib/longhorn` is misleading and architecturally "leaky."

### Proposed Solutions for Path Selection:

1.  **Generic Mounting**: Mount the 2nd disk to a standard, non-app-specific path like `/mnt/data/disk1` or `/data/storage`.
    *   *Pros*: Consistent across all VMs.
    *   *Cons*: Kubernetes/Longhorn still needs to be told to look there.
2.  **Symlink Strategy**: Mount to a generic path (e.g., `/data/storage`) and have a separate app-specific task (in the `kubeadm_cluster` role) create a symlink: `/var/lib/longhorn` -> `/data/storage`.
    *   *Pros*: Keeps the storage role pure; keeps Longhorn happy.
3.  **Variable-Driven Mapping (Inventory)**: Define the path at the Inventory level (e.g., `group_vars/k8s_nodes.yml`).
    *   *Note*: You mentioned deleting `group_vars/vm.yml`. If we use `group_vars/k8s_nodes.yml` instead, only the Kubernetes nodes get the Longhorn path. Other VMs (like a standalone Postgres VM) can have their own `group_vars/db_nodes.yml` mapping `/dev/sdb` to `/var/lib/postgresql`.

## 3. Handling Multiple Disks

As requested, the role logic supports multiple disks. By using a list in the variables, we can handle any number of disks:

```yaml
# Example in a host-specific file or group-specific file
storage_mounts:
  - { device: "/dev/sdb", path: "/var/lib/longhorn", fstype: "ext4" }
  - { device: "/dev/sdc", path: "/data/backups", fstype: "xfs" }
```

## Conclusion

To keep the system clean:
1.  **Role Tasks**: Remain strictly generic (Logic: "If device X exists, mount to path Y").
2.  **Role Defaults**: Set `storage_mounts: []` (Do nothing by default).
3.  **Specific Config**: Put the mapping (`/dev/sdb` -> `/var/lib/longhorn`) in **Group-Specific** variables (e.g., `k8s_nodes`) rather than Global/VM-wide variables. This avoids the "Database VM has a Longhorn folder" problem.
