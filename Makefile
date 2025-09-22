# =============================================================================
# Makefile for the Platform Stack Project
#
# This file automates common setup and operational tasks.
# =============================================================================

# .PHONY defines targets that are actions, not files.
.PHONY: help install-hooks

# The default command, run when you just type 'make'.
help:
	@echo "Available commands:"
	@echo "  install-hooks  - Installs Git pre-commit hooks for repository safety."
	@echo ""

# --- HOOK MANAGEMENT ---
install-hooks:
	@echo "--> Installing Git pre-commit hooks..."
	@# This command creates a symbolic link from our version-controlled script
	@# to the location where Git expects to find the pre-commit hook.
	@# The '-sf' flags mean 'symbolic' and 'force' (overwrite if it already exists),
	@# making this command safe to run multiple times.
	@ln -sf ../../scripts/check-vault-encrypted.sh .git/hooks/pre-commit
	@echo "--> Hooks installed successfully."
	@echo "--> The vault encryption check will now run before every commit."