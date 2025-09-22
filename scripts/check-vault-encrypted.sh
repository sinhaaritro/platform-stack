#!/bin/bash

# =============================================================================
# PRE-COMMIT HOOK: Check for Unencrypted Ansible Vault Files (v2)
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
#    The script will print a clear error message TO STDERR and exit with a
#    non-zero status code, which automatically ABORTS the commit.
# 5. If all secret files are correctly encrypted, the script exits
#    successfully, allowing the commit to proceed.
# =============================================================================

echo "--- Running Vault Encryption Check ---"

# Get a list of all staged files (added, copied, modified) that match our secret file pattern.
# This command correctly handles multiple files, even if they are committed at the same time.
STAGED_SECRET_FILES=$(git diff --cached --name-only --diff-filter=ACM | grep '\.secrets\.tfvars$')

# If the list of secret files is empty, there's nothing to check.
if [ -z "$STAGED_SECRET_FILES" ]; then
    echo "No secret files staged for commit. Skipping check."
    exit 0 # Exit successfully, allowing the commit to proceed.
fi

# Initialize a list to hold the names of any unencrypted files.
UNENCRYPTED_FILES=()

# Loop through each found secret file.
for file in $STAGED_SECRET_FILES; do
    # Check if the first line of the file starts with the Ansible Vault header.
    if ! head -n 1 "$file" | grep -q '^\$ANSIBLE_VAULT;'; then
        # If the file is unencrypted, add it to our list of errors.
        UNENCRYPTED_FILES+=("$file")
    else
        # If the header is found, print a success message for that file.
        echo "  ✔ OK: $file is encrypted."
    fi
done

# After checking all files, if our list of unencrypted files is NOT empty, report the errors.
if [ ${#UNENCRYPTED_FILES[@]} -ne 0 ]; then
    # Redirect all the following 'echo' commands to Standard Error (>&2)
    # This is the correct stream for error messages and helps some tools display it better.
    echo "" >&2
    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" >&2
    echo "!! COMMIT REJECTED: Found unencrypted secret files in this commit." >&2
    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" >&2
    echo "" >&2
    echo "The following files must be encrypted before you can commit them:" >&2
    for file in "${UNENCRYPTED_FILES[@]}"; do
        echo "  - $file" >&2
    done
    echo "" >&2
    echo "To fix this, run 'ansible-vault encrypt <filename>' for each file listed above." >&2
    echo "" >&2
    exit 1 # Exit with an error, aborting the commit.
fi

# If we get here, all checks passed.
echo "--- All secret files are properly encrypted. Commit proceeding. ---"
exit 0 # Exit successfully, allowing the commit to proceed.