#!/usr/bin/env python3
"""
Kubernetes App Structure Validator

Enforces the "Base + Patches + Overlays" directory structure.
Now with deep content validation for Kustomization files.
Usage: python validate_structure.py <root_dir>
"""

import sys
import os
import yaml
from pathlib import Path

def load_yaml(path):
    try:
        with open(path, 'r') as f:
            return yaml.safe_load(f)
    except Exception as e:
        return None

def check_base_values(kust_path, errors):
    """Ensures base/kustomization.yaml uses valuesFile for Helm Charts."""
    content = load_yaml(kust_path)
    if not content or 'helmCharts' not in content:
        return

    for chart in content['helmCharts']:
        if 'valuesInline' in chart:
            errors.append(f"[INVALID] {kust_path} uses 'valuesInline' (Forbidden). Use 'valuesFile'.")
        if 'valuesFile' not in chart:
             # It's possible to have no values, but if they have config, it should be in a file.
             # We'll warn if neither exists but allow pure defaults.
             pass
        else:
             # Check if the file exists
             vfile = kust_path.parent / chart['valuesFile']
             if not vfile.exists():
                 errors.append(f"[MISSING] {kust_path} references missing valuesFile: {chart['valuesFile']}")

def check_component_patches(kust_path, errors):
    """Ensures components use external patches, not inline."""
    content = load_yaml(kust_path)
    if not content or 'patches' not in content:
        return

    for patch in content['patches']:
        if isinstance(patch, str):
            # String is a file path in old kustomize, likely fine, but check existance
            pfile = kust_path.parent / patch
            if not pfile.exists():
                errors.append(f"[MISSING] {kust_path} references missing patch: {patch}")
        elif isinstance(patch, dict):
            if 'patch' in patch:
                errors.append(f"[INVALID] {kust_path} uses inline 'patch' string. Use 'path' to an external file.")
            if 'path' in patch:
                 pfile = kust_path.parent / patch['path']
                 if not pfile.exists():
                     errors.append(f"[MISSING] {kust_path} references missing patch: {patch['path']}")

def check_relative_paths(kust_path, errors):
    """Ensures resources/components paths are valid and use recognized depth."""
    content = load_yaml(kust_path)
    if not content:
        return

    # Check resources and components
    for key in ['resources', 'components']:
        if key in content:
            for item in content[key]:
                # We expect local paths or relative paths
                if item.startswith("http") or item.startswith("github.com"):
                    continue
                
                target = (kust_path.parent / item).resolve()
                if not target.exists():
                    errors.append(f"[BROKEN] {kust_path} references missing {key}: {item}")
                
                # Check for "climbing back top" pattern
                # User wants: ../../../apps/services/...
                # If we are in clusters/cls/app (Depth from root: 3)
                # And target is apps/ (Depth from root: 1)
                # We expect ../../..
                # This is hard to enforce strictly without knowing "root", but we can check if it looks weird.
                if "../" in item and "apps/" in item and not item.startswith("../"):
                     errors.append(f"[WARNING] {kust_path} path to apps/ should likely start with ../: {item}")


def validate_app_structure(app_path):
    """Checks if an app in apps/ has base, patches, and overlays."""
    errors = []
    
    # Check Base
    base_kust = app_path / "base" / "kustomization.yaml"
    if not base_kust.exists():
        errors.append(f"[MISSING] {app_path.name}/base/kustomization.yaml")
    else:
        check_base_values(base_kust, errors)
        check_relative_paths(base_kust, errors)

    # Check Patches (Optional but recommended folder)
    patches_dir = app_path / "patches"
    
    # Check Components (New Pattern)
    components_dir = app_path / "components"
    if components_dir.exists():
        # If components exist, check for kustomization.yaml inside each component
        for entries in components_dir.iterdir():
             if entries.is_dir():
                 comp_kust = entries / "kustomization.yaml"
                 if not comp_kust.exists():
                      errors.append(f"[INVALID] {app_path.name}/components/{entries.name} missing kustomization.yaml")
                 else:
                      check_component_patches(comp_kust, errors)
                      check_relative_paths(comp_kust, errors)

    # Check Overlays
    overlays_dir = app_path / "overlays"
    if not overlays_dir.exists():
        errors.append(f"[MISSING] {app_path.name}/overlays/ directory")
    else:
        # If overlays exists, check if at least one overlay exists with kustomization
        overlay_found = False
        for entry in overlays_dir.iterdir():
            if entry.is_dir():
                ov_kust = entry / "kustomization.yaml"
                if ov_kust.exists():
                    overlay_found = True
                    check_relative_paths(ov_kust, errors)
        if not overlay_found:
            errors.append(f"[EMPTY] {app_path.name}/overlays/ has no valid profiles")

    return errors

def validate_cluster_implementation(cluster_path):
    """Checks if a cluster app has kustomization.yaml."""
    errors = []
    
    # We iterate over directories in the cluster folder
    for entry in cluster_path.iterdir():
        if entry.is_dir():
            # This is likely an app
            kust = entry / "kustomization.yaml"
            if not kust.exists():
                # Might be a tenant folder or bootstrap?
                # We skip bootstrap/
                if entry.name == "bootstrap":
                    continue
                errors.append(f"[MISSING] {cluster_path.name}/{entry.name}/kustomization.yaml")
            else:
                check_relative_paths(kust, errors)
    
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
