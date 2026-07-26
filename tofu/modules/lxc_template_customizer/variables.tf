# -----------------------------------------------------------------------------
# VARIABLES - LXC TEMPLATE CUSTOMIZER MODULE
# -----------------------------------------------------------------------------

variable "lxc_templates" {
  description = "A map of LXC container configurations requiring customized OS rootfs templates."
  type        = any
  default     = {}
}

variable "local_cache_dir" {
  description = "Directory on the control machine where customized container templates are cached."
  type        = string
  default     = "/var/tmp/tofu-artifacts"
}
