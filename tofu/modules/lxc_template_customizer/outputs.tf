# -----------------------------------------------------------------------------
# OUTPUTS - LXC TEMPLATE CUSTOMIZER MODULE
# -----------------------------------------------------------------------------

output "customized_templates" {
  description = "Map of customized LXC template details keyed by container name."
  value = {
    for key, info in local.template_info : key => {
      target_filename = info.filename
      local_path      = info.target_path
      hash_suffix     = info.hash_suffix
      template_url    = info.url
    }
  }
}
