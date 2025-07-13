# Proxmox Provider Variables
variable "proxmox_url" {
  type        = string
  description = "The URL for the Proxmox API (e.g., https://192.168.1.10:8006/api2/json)."
}

variable "proxmox_user" {
  type        = string
  description = "The user for Proxmox API authentication (e.g., tofu-user@pve)."
  sensitive   = true
}

variable "proxmox_password" {
  type        = string
  description = "The password for the Proxmox user."
  sensitive   = true
}

variable "target_node" {
  type        = string
  description = "The name of the Proxmox node where VMs will be created."
}

# VM Definitions
variable "laboon_vms" {
  type = map(object({
    vmid = number
    ip   = string
  }))
  description = "A map of the Laboon VMs to create, with their specific VMID and IP address."
}

variable "laboon_cluster_enabled" {
  type        = bool
  description = "A master switch to enable (create) or disable (destroy) the entire Laboon cluster."
  default     = true
}

# Virtual Machine Configuration
variable "template_name" {
  type        = string
  description = "The name of the VM template to clone."
}

variable "vm_cores" {
  type        = number
  description = "The number of CPU cores for each VM."
  default     = 2
}

variable "vm_memory" {
  type        = number
  description = "The amount of memory in MB for each VM."
  default     = 2048 # 2GB
}

variable "storage_pool" {
  type        = string
  description = "The Proxmox storage pool to use for VM disks."
  default     = "local-lvm"
}

variable "vm_disk_size" {
  type        = string
  description = "The size of the primary disk for each VM (e.g., '20G')."
  default     = "16G"
}

# Network Configuration
variable "network_bridge" {
  type        = string
  description = "The Proxmox network bridge to attach the VMs to (e.g., vmbr0)."
}

variable "gateway_ip" {
  type        = string
  description = "The IP address of the network gateway (e.g., 192.168.0.1)."
}

variable "cidr_mask" {
  type        = number
  description = "The CIDR subnet mask for the IP addresses (e.g., 24 for /24)."
  default     = 24
}

# Cloud-Init Configuration
variable "cloud_init_user" {
  type = object({
    username  = string
    password  = string
    ssh_key   = string
    upgrade   = bool
  })
  description = "An object containing the user, password, and SSH public key for Cloud-Init."
  sensitive   = true
}

# User/SSH Configuration
variable "ssh_public_key" {
  type        = string
  description = "The content of your SSH public key for passwordless login."
  # It's better to keep the key out of the main repo if it's public,
  # but for this private setup, it's okay.
  sensitive   = true
}