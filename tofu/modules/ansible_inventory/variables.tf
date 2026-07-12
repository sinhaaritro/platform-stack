# -----------------------------------------------------------------------------
# INPUT VARIABLES - ANSIBLE INVENTORY MODULE
# -----------------------------------------------------------------------------

variable "stack_name" {
  description = "The name of the stack (e.g., 'proxmox_meru'). Used to name the generated inventory file."
  type        = string
}

variable "vm_list" {
  description = "The normalized map of enabled VMs from the resource normalizer module."
  type        = any
}

variable "vm_outputs" {
  description = "The computed outputs from the VM creation module (containing IP addresses), keyed by VM name."
  type        = any
}

variable "inventory_dir" {
  description = "The directory path where the Ansible inventory file should be written."
  type        = string
}
