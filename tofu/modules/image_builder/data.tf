# -----------------------------------------------------------------------------
# DATA SOURCES - IMAGE BUILDER MODULE
# -----------------------------------------------------------------------------

data "http" "checksums" {
  for_each = local.os_images

  url = each.value.checksum_url

  lifecycle {
    postcondition {
      condition     = self.status_code == 200
      error_message = "Error validating OS version '${each.key}'. The URL '${self.url}' returned status ${self.status_code}. Please check if this is a valid release version."
    }
  }
}
