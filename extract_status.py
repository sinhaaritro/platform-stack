import sys, json; print(json.dumps([r for r in json.load(sys.stdin)['status']['resources'] if r['name'] == 'authentik-postgresql'], indent=2))
