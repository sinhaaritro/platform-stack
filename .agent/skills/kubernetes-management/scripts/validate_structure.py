#!/usr/bin/env python3
"""
Kubernetes App Structure Validator

Enforces the "Base + Patches + Overlays" directory structure.
Usage: python validate_structure.py <root_dir>
"""

import sys
import os
from pathlib import Path

def validate_app_structure(app_path):
    """Checks if an app in apps/ has base, patches, and overlays."""
    errors = []
    
    # Check Base
    base_kust = app_path / "base" / "kustomization.yaml"
    if not base_kust.exists():
        errors.append(f"[MISSING] {app_path.name}/base/kustomization.yaml")

    # Check Patches (Optional but recommended folder)
    patches_dir = app_path / "patches"
    if not patches_dir.exists():
        # Not an error, but a warning/notice could be useful. 
        # For now, we strictly check STRUCTURE, so if the folder is missing it might be fine 
        # but let's encourage it.
        pass 

    # Check Overlays
    overlays_dir = app_path / "overlays"
    if not overlays_dir.exists():
        errors.append(f"[MISSING] {app_path.name}/overlays/ directory")
    else:
        # If overlays exists, check if at least one overlay exists with kustomization
        overlay_found = False
        for entry in overlays_dir.iterdir():
            if entry.is_dir() and (entry / "kustomization.yaml").exists():
                overlay_found = True
                break
        if not overlay_found:
            errors.append(f"[EMPTY] {app_path.name}/overlays/ has no valid profiles")

    return errors

def validate_cluster_implementation(cluster_path):
    """Checks if a cluster app has kustomization.yaml."""
    errors = []
    # Currently assuming 1 level deep: clusters/[cluster]/[app]
    # But wait, clusters/[cluster] can have [app] directly.
    
    # We iterate over directories in the cluster folder
    for entry in cluster_path.iterdir():
        if entry.is_dir():
            # This is likely an app
            kust = entry / "kustomization.yaml"
            if not kust.exists():
                # Might be a tenant folder? 
                # For now, let's assume flat structure as per doc
                errors.append(f"[MISSING] {cluster_path.name}/{entry.name}/kustomization.yaml")
    
    return errors


def main():
    root = Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()
    k8s_root = root / "kubernetes"
    
    if not k8s_root.exists():
        print("❌ kubernetes/ directory not found.")
        sys.exit(1)

    all_errors = []

    # 1. Validate Apps
    apps_root = k8s_root / "apps"
    if apps_root.exists():
        for category in apps_root.iterdir():
            if category.is_dir():
                for app in category.iterdir():
                    if app.is_dir():
                        all_errors.extend(validate_app_structure(app))

    # 2. Validate Clusters
    clusters_root = k8s_root / "clusters"
    if clusters_root.exists():
        for cluster in clusters_root.iterdir():
            if cluster.is_dir():
                all_errors.extend(validate_cluster_implementation(cluster))

    if all_errors:
        print("❌ Structure Validation Failed:")
        for err in all_errors:
            print(f"  - {err}")
        sys.exit(1)
    else:
        print("✅ Kubernetes App Structure is Valid.")
        sys.exit(0)

if __name__ == "__main__":
    main()
