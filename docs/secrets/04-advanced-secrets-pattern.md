# Developer Pattern: Kubernetes Secrets

Rules to follow:

1. SOLID Principal
2. 1 Source of truth
3. DRY
4. GitOps with secrets in repo.
5. No Secret Store in Corporate Vaults
6. Automatic start of pods from scratch

Things Used
1. Sealed Secrets 
2. External Secrets Operator


Used For
1. Moving Secrets across Namesapce to maintain, 1 Source of truth
2. Getting Secrets from another namespace to use in curent application
3. Saving Config files in repo