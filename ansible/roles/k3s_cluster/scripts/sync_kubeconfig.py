#!/usr/bin/env python3
import yaml
import os
import argparse
import base64

def merge_kubeconfig(cluster_name, master_ip, encoded_config):
    # 1. Decode and Load remote config
    print(f"--- [DEBUG] Decoding k3s.yaml for {cluster_name} ---")
    raw_remote = base64.b64decode(encoded_config).decode('utf-8')
    remote_yaml = yaml.safe_load(raw_remote)

    # 2. Update server IP and Rename metadata
    print(f"--- [DEBUG] Updating server endpoint to {master_ip} ---")
    remote_yaml['clusters'][0]['cluster']['server'] = f"https://{master_ip}:6443"
    remote_yaml['clusters'][0]['name'] = cluster_name
    remote_yaml['users'][0]['name'] = cluster_name
    remote_yaml['contexts'][0]['name'] = cluster_name
    remote_yaml['contexts'][0]['context']['cluster'] = cluster_name
    remote_yaml['contexts'][0]['context']['user'] = cluster_name

    # 3. Load or initialize local config
    kube_path = os.path.expanduser('~/.kube/config')
    print(f"--- [DEBUG] Reading local config at {kube_path} ---")
    if os.path.exists(kube_path) and os.path.getsize(kube_path) > 0:
        with open(kube_path, 'r') as f:
            local_yaml = yaml.safe_load(f)
    else:
        print("--- [DEBUG] No existing kubeconfig found, initializing fresh... ---")
        local_yaml = {
            'apiVersion': 'v1', 
            'clusters': [], 
            'contexts': [], 
            'users': [], 
            'kind': 'Config', 
            'preferences': {}
        }

    # 4. Helper to merge lists by name key
    def merge_by_name(local_list, remote_item):
        for i, item in enumerate(local_list):
            if item['name'] == remote_item['name']:
                print(f"--- [DEBUG] Overwriting existing {remote_item['name']} entry ---")
                local_list[i] = remote_item
                return
        print(f"--- [DEBUG] Adding new {remote_item['name']} entry ---")
        local_list.append(remote_item)

    merge_by_name(local_yaml['clusters'], remote_yaml['clusters'][0])
    merge_by_name(local_yaml['users'], remote_yaml['users'][0])
    merge_by_name(local_yaml['contexts'], remote_yaml['contexts'][0])
    
    # Set current context if not set
    if not local_yaml.get('current-context'):
        print(f"--- [DEBUG] Setting default context to {cluster_name} ---")
        local_yaml['current-context'] = cluster_name

    # 5. Write back safely
    os.makedirs(os.path.dirname(kube_path), exist_ok=True)
    with open(kube_path, 'w') as f:
        yaml.dump(local_yaml, f, default_flow_style=False)
    print(f"--- [SUCCESS] Kubeconfig local sync complete for {cluster_name} ---")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description='Merge k3s config into local kubeconfig')
    parser.add_argument('--cluster-name', required=True)
    parser.add_argument('--master-ip', required=True)
    parser.add_argument('--base64-config', required=True)
    
    args = parser.parse_args()
    merge_kubeconfig(args.cluster_name, args.master_ip, args.base64_config)
