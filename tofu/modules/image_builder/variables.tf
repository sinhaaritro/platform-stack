# -----------------------------------------------------------------------------
# INPUT VARIABLES - IMAGE BUILDER MODULE
# -----------------------------------------------------------------------------

variable "requested_images" {
  description = "A map from composite keys (e.g. 'ubuntu-24.04') to object containing os_type and os_version."
  type = map(object({
    os_type    = string
    os_version = string
  }))
}

variable "existing_images" {
  description = "List of image filenames already present on the destination hypervisor storage (to skip builds)."
  type        = list(string)
  default     = []
}

variable "local_cache_dir" {
  description = "Local directory on the control machine where images are downloaded and customized."
  type        = string
  default     = "/var/tmp/tofu-artifacts/"
}

variable "default_os_type" {
  description = "Fallback OS type if not specified."
  type        = string
  default     = "ubuntu"
}

variable "default_os_version" {
  description = "Fallback OS version if not specified."
  type        = string
  default     = "24.04"
}
