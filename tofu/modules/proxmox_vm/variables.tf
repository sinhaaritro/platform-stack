# -----------------------------------------------------------------------------
# PROXMOX VM MODULE - INPUT VARIABLES
# -----------------------------------------------------------------------------
# This file defines the input "contract" for the proxmox_vm module.
# It accepts a flat list of simple values, which are resolved and passed
# in by the calling stack.
# -----------------------------------------------------------------------------

# --- Mandatory Inputs ---
variable "vm_id" {
  description = "The unique numeric ID for the virtual machine."
  type        = number
}

variable "name" {
  description = "The hostname for the virtual machine."
  type        = string
}

variable "node_name" {
  description = "The name of the Proxmox node where the VM will be created."
  type        = string
}

variable "app_key" {
  description = "The application group key (e.g., 'web_server') this VM belongs to. Used for outputs."
  type        = string
}

variable "source_image_path" {
  description = "The Volume ID of the master disk image to import (e.g., 'datastore:import/image.qcow2')."
  type        = string
}

# --- General VM Settings ---
variable "description" {
  description = "A description for the VM, visible in the Proxmox UI."
  type        = string
}

variable "tags" {
  description = "A list of tags to apply to the VM."
  type        = list(string)
}

variable "on_boot" {
  description = "Specifies whether the VM should start on host boot."
  type        = bool
}

variable "started" {
  description = "Specifies whether the VM should be running after creation."
  type        = bool
}

# --- Hardware Configuration ---
variable "cpu_cores" {
  description = "The number of CPU cores for the VM."
  type        = number
}

variable "cpu_sockets" {
  description = "The number of CPU sockets for the VM."
  type        = number
}

variable "memory" {
  description = "The amount of dedicated memory in MB for the VM."
  type        = number
}

# --- Disk Configuration ---
variable "disk_datastore_id" {
  description = "The datastore ID for the VM's main and EFI disks."
  type        = string
}

variable "disk_size" {
  description = "The final size of the main disk in GB."
  type        = number
}

variable "disk_ssd" {
  description = "Whether to emulate the main disk as an SSD."
  type        = bool
}

# --- Network Configuration ---
variable "vlan_bridge" {
  description = "The network bridge for the VM's network interface (e.g., 'vmbr0')."
  type        = string
}

variable "vlan_id" {
  description = "The VLAN ID for the network interface (0 for no tag)."
  type        = number
}

# --- Cloud-Init Configuration ---
variable "ipv4_address" {
  description = "The IPv4 address for cloud-init (e.g., 'dhcp' or '1.2.3.4/24')."
  type        = string
}

variable "user_account_username" {
  description = "The username for the default cloud-init user."
  type        = string
}

variable "user_account_password" {
  description = "The password for the default cloud-init user."
  type        = string
  sensitive   = true
}

variable "user_account_keys" {
  description = "A list of public SSH keys for the default cloud-init user."
  type        = list(string)
  sensitive   = true
}
