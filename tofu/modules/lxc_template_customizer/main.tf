# -----------------------------------------------------------------------------
# RESOURCE ORCHESTRATION - LXC TEMPLATE CUSTOMIZER MODULE
# -----------------------------------------------------------------------------
# Downloads and customizes LXC rootfs templates (Alpine, Debian, Ubuntu)
# on the control machine before uploading to Proxmox storage datastores.
# Hash-based caching: uses template checksum or URL sha256 to derive a 
# deterministic cache key and target filename.
# -----------------------------------------------------------------------------

locals {
  template_info = {
    for key, lxc in var.lxc_templates : key => {
      url         = lxc.template_url
      hash        = coalesce(lxc.template_checksum, sha256(lxc.template_url))
      hash_suffix = substr(coalesce(lxc.template_checksum, sha256(lxc.template_url)), 0, 8)
      filename    = "ssh-${substr(coalesce(lxc.template_checksum, sha256(lxc.template_url)), 0, 8)}-${basename(lxc.template_url)}"
      target_path = "${var.local_cache_dir}/ssh-${substr(coalesce(lxc.template_checksum, sha256(lxc.template_url)), 0, 8)}-${basename(lxc.template_url)}"
      os_type     = coalesce(lxc.os_type, "alpine")
    }
  }
}

resource "null_resource" "lxc_template_customizer" {
  for_each = local.template_info

  triggers = {
    template_url = each.value.url
    content_hash = each.value.hash
    file_state   = fileexists(each.value.target_path) ? "exists" : "missing"
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command = templatefile("${path.module}/templates/customize_lxc_${contains(["debian", "ubuntu"], lower(each.value.os_type)) ? "debian" : "alpine"}.sh.tftpl", {
      template_url    = each.value.url
      cache_dir       = var.local_cache_dir
      target_filename = each.value.filename
    })
  }
}
