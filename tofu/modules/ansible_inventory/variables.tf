# -----------------------------------------------------------------------------
# INPUT VARIABLES - ANSIBLE INVENTORY MODULE
# -----------------------------------------------------------------------------

variable "stack_name" {
  description = "The name of the stack (e.g., 'proxmox_meru'). Used to name the generated inventory file."
  type        = string
}

variable "host_list" {
  description = "A unified list of all hosts (VMs and LXCs) with their configuration. Each host object must contain: name, tags, app_key, node_name, type, ansible_groups, ipv4_address, user_account_username."
  type        = any
}

variable "inventory_dir" {
  description = "The directory path where the Ansible inventory file should be written."
  type        = string
}
