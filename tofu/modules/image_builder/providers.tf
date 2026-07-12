# -----------------------------------------------------------------------------
# REQUIRED PROVIDERS - IMAGE BUILDER MODULE
# -----------------------------------------------------------------------------

terraform {
  required_providers {
    http = {
      source  = "hashicorp/http"
      version = "3.5.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "3.2.4"
    }
  }
}
