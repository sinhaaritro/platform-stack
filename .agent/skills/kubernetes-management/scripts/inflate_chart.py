#!/usr/bin/env python3
"""
Helm Chart Inflator (The X-Ray)

Inflates a Kustomize-wrapped Helm chart into a full YAML file for inspection.
Usage: python inflate_chart.py <path_to_kustomization_dir>
"""

import sys
import subprocess
from pathlib import Path

def inflate(path):
    target_dir = Path(path).resolve()
    if not (target_dir / "kustomization.yaml").exists():
        print(f"❌ No kustomization.yaml found in {target_dir}")
        sys.exit(1)

    output_file = target_dir / "debug_full.yaml"
    
    print(f"🔍 Inflating Helm Chart in {target_dir}...")
    
    try:
        # Run kustomize build
        cmd = ["kustomize", "build", "--enable-helm", "."]
        result = subprocess.run(cmd, cwd=target_dir, capture_output=True, text=True)
        
        if result.returncode != 0:
            print("❌ Kustomize Build Failed:")
            print(result.stderr)
            sys.exit(1)
            
        # Write output
        with open(output_file, 'w') as f:
            f.write(result.stdout)
            
        print(f"✅ Extracted to: {output_file}")
        print("⚠️  WARNING: Do NOT commit this file. Add to .gitignore if needed.")
        
    except FileNotFoundError:
        print("❌ 'kustomize' command not found. Is it installed?")
        sys.exit(1)

def main():
    if len(sys.argv) < 2:
        print("Usage: python inflate_chart.py <path_to_kustomization_dir>")
        sys.exit(1)
        
    inflate(sys.argv[1])

if __name__ == "__main__":
    main()
