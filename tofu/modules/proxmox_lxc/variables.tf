# -----------------------------------------------------------------------------
# PROXMOX LXC MODULE - INPUT VARIABLES
# -----------------------------------------------------------------------------
# This file defines the input "contract" for the proxmox_lxc module.
# It accepts a flat list of simple values, which are resolved and passed
# in by the calling stack.
# -----------------------------------------------------------------------------

# --- Mandatory Inputs ---

variable "vm_id" {
  description = "The unique numeric ID for the LXC container."
  type        = number
}

variable "node_name" {
  description = "The name of the Proxmox node where the container will be created."
  type        = string
}

variable "app_key" {
  description = "The application group key (e.g., 'support_servers') this container belongs to."
  type        = string
}

variable "template_file_id" {
  description = "The Volume ID of the LXC template to use (e.g., 'local:vztmpl/template.tar.zst')."
  type        = string
}

# --- General Container Settings ---

variable "description" {
  description = "A description for the container, visible in the Proxmox UI."
  type        = string
}

variable "tags" {
  description = "A list of tags to apply to the container."
  type        = list(string)
}

variable "on_boot" {
  description = "Specifies whether to container when the host system boots."
  type        = bool
}

variable "started" {
  description = "Specifies whether the container should be running after creation."
  type        = bool
}

variable "unprivileged" {
  description = "Specifies whether the container runs as unprivileged on the host."
  type        = bool
}

# --- Features Configuration ---

variable "nesting" {
  description = "Enable nesting for this container (required for Docker, etc.)."
  type        = bool
}

variable "fuse" {
  description = "Allow the container to mount fuse filesystems."
  type        = bool
}

variable "keyctl" {
  description = "Enable the keyctl syscalls for this container."
  type        = bool
}

# --- OS Configuration ---

variable "os_type" {
  description = "The type of the operating system (e.g., 'debian', 'ubuntu')."
  type        = string
}

# --- Disk Configuration ---

variable "disk_datastore_id" {
  description = "The datastore ID for the container's root disk."
  type        = string
}

variable "disk_size" {
  description = "The size of the root disk in GB."
  type        = number
}

# --- Hardware Configuration ---

variable "cpu_cores" {
  description = "The number of CPU cores for the container."
  type        = number
}

variable "memory" {
  description = "The amount of dedicated memory in MB for the container."
  type        = number
}

# --- Network Configuration ---

variable "vlan_bridge" {
  description = "The network bridge for the container's network interface (e.g., 'vmbr0')."
  type        = string
}

variable "vlan_id" {
  description = "The VLAN ID for the network interface (0 for no tag)."
  type        = number
}

# --- Initialization Configuration ---

variable "hostname" {
  description = "The hostname for the container."
  type        = string
}

variable "ipv4_address" {
  description = "The IPv4 address for the network interface (e.g., 'dhcp' or '1.2.3.4/24')."
  type        = string
}

variable "ipv4_gateway" {
  description = "The IPv4 gateway for the network interface (e.g., '1.2.3.1')."
  type        = string
}

variable "user_account_password" {
  description = "The root password for the container."
  type        = string
  sensitive   = true
}

variable "user_account_keys" {
  description = "A list of public SSH keys for the root user."
  type        = list(string)
  sensitive   = true
}
