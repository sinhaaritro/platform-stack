# -----------------------------------------------------------------------------
# MODULE OUTPUTS
# -----------------------------------------------------------------------------
# Returns the fully resolved image paths on the Proxmox datastore and diagnostic data.
# -----------------------------------------------------------------------------

output "image_paths" {
  description = "A map from composite OS-version keys (e.g., 'ubuntu-24.04') to their Proxmox datastore import paths."
  value       = local.image_paths
}

output "debug_info" {
  description = "Diagnostic data representing the internal image pipeline configurations, input parameters, and decisions."
  value = {
    "INPUT_PARAMETERS" = {
      "target_node"      = var.target_node
      "target_datastore" = var.target_datastore
      "local_cache_dir"  = var.local_cache_dir
      "default_os_type"  = var.default_os_type
    }
    "STEP_1_GATHER_INFO" = {
      "detected_os_requests"       = local.requested_images
      "os_registry_resolutions"    = local.os_images
      "files_detected_on_datastore" = local.existing_files_on_proxmox
    }
    "STEP_2_DECISION_MAKING" = {
      "upstream_manifest_hashes"  = local.image_state
      "computed_image_definitions" = local.final_image_defs
      "build_necessity_decisions" = {
        for k, v in local.build_decisions : k => (v == 1 ? "Build & Customization Required" : "Already Present on Storage (No Build)")
      }
    }
    "STEP_3_PREPARE_LOCAL_IMAGE" = {
      "local_builder_targets" = {
        for k, def in local.final_image_defs : k => {
          local_path  = def.target_path
          script_name = def.customize_script
        }
      }
    }
    "STEP_4_UPLOAD_IMAGE" = {
      "module_output_image_paths" = local.image_paths
    }
  }
}
