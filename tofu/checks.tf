# -----------------------------------------------------------------------------
# WORKSPACE AND DATA VALIDATION CHECKS
#
# This file contains critical preconditions that are evaluated during the
# 'tofu plan' phase. If any of these checks fail, the plan will be halted,
# preventing an invalid or dangerous apply.
# -----------------------------------------------------------------------------

check "workspace_guardrail" {
  assert {
    # This condition compares the name of the currently selected OpenTofu workspace
    # with the 'environment_name' variable loaded from the .tfvars file.
    # The plan will only proceed if they are an exact match.
    condition     = terraform.workspace == var.environment_name

    # If the condition is false, the plan fails and displays this custom,
    # helpful error message, guiding the user to the correct action.
    error_message = "Workspace Mismatch: You are trying to plan for the '${var.environment_name}' environment, but you are in the '${terraform.workspace}' workspace. Please run 'tofu workspace select ${var.environment_name}' before proceeding."
  }
}