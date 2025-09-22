#!/bin/bash

# =============================================================================
# PRE-COMMIT HOOK: Check for Unencrypted Ansible Vault Files
#
# This script is designed to be run as a Git pre-commit hook. Its purpose
# is to prevent unencrypted secret files from ever being committed to the
# repository.
#
# It works by:
# 1. Getting a list of all STAGED files for the current commit.
# 2. Filtering that list to find files that match our secret naming
#    convention (ending in '.secrets.tfvars').
# 3. For each of those files, it checks if the first line of content
#    starts with the Ansible Vault header ('$ANSIBLE_VAULT;').
# 4. If any secret file is missing this header, it's considered unencrypted.
#    The script will print a clear error message and exit with a non-zero
#    status code, which automatically ABORTS the commit.
# 5. If all secret files are correctly encrypted, the script exits
#    successfully, allowing the commit to proceed.
# =============================================================================

echo "--- Running Vault Encryption Check ---"

# Get a list of all staged files (added, copied, modified) that match our secret file pattern.
# We check against the git index (`--cached`) to only test what's being committed.
STAGED_SECRET_FILES=$(git diff --cached --name-only --diff-filter=ACM | grep '\.secrets\.tfvars$')

# If the list of secret files is empty, there's nothing to check.
if [ -z "$STAGED_SECRET_FILES" ]; then
    echo "No secret files staged for commit. Skipping check."
    exit 0 # Exit successfully, allowing the commit to proceed.
fi

# Initialize a flag to track if we find any errors.
HAS_ERROR=0

# Loop through each found secret file.
for file in $STAGED_SECRET_FILES; do
    # Check if the first line of the file starts with the Ansible Vault header.
    # The `grep -q` command runs quietly and just returns a status code.
    if ! head -n 1 "$file" | grep -q '^\$ANSIBLE_VAULT;'; then
        # If the header is not found, print a detailed error message.
        echo ""
        echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
        echo "!! COMMIT REJECTED: Unencrypted secret file found in commit:"
        echo "!!   -> $file"
        echo "!!"
        echo "!! This file must be encrypted before you can commit it."
        echo "!! To fix this, run: 'ansible-vault encrypt \"$file\"'"
        echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
        echo ""
        HAS_ERROR=1
    else
        # If the header is found, print a success message for that file.
        echo "  ✔ OK: $file is encrypted."
    fi
done

# After checking all files, if our error flag is set, exit with an error.
if [ "$HAS_ERROR" -ne 0 ]; then
    echo "--- Commit ABORTED due to unencrypted secret files. ---"
    exit 1 # Exit with an error, aborting the commit.
fi

# If we get here, all checks passed.
echo "--- All secret files are properly encrypted. Commit proceeding. ---"
exit 0 # Exit successfully, allowing the commit to proceed.