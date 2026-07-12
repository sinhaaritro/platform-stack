# -----------------------------------------------------------------------------
# MODULE OUTPUTS - IMAGE BUILDER MODULE
# -----------------------------------------------------------------------------

output "built_images" {
  description = "A map from OS-version keys (e.g. 'ubuntu-24.04') to their local qcow2 file paths and filenames."
  value = {
    for key, def in local.final_image_defs : key => {
      local_path = def.target_path
      filename   = def.target_filename
    }
  }
}

output "debug_info" {
  description = "Diagnostic data representing the internal image pipeline configurations and decisions."
  value = {
    "INPUT_PARAMETERS" = {
      "local_cache_dir" = var.local_cache_dir
      "default_os_type" = var.default_os_type
    }
    "STEP_1_GATHER_INFO" = {
      "detected_os_requests"        = var.requested_images
      "os_registry_resolutions"     = local.os_images
      "files_detected_on_destination" = var.existing_images
    }
    "STEP_2_DECISION_MAKING" = {
      "upstream_manifest_hashes"   = local.image_state
      "computed_image_definitions" = local.final_image_defs
      "build_necessity_decisions"  = {
        for k, v in local.build_decisions : k => (v == 1 ? "Build & Customization Required" : "Already Present on Destination or Cache (No Build)")
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
  }
}
