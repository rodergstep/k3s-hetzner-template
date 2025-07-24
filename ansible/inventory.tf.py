#!/usr/bin/env python

import json
import subprocess

def main():
    # Run `terraform output` to get the master IP
    try:
        result = subprocess.run(
            ["terraform", "output", "-json"],
            capture_output=True,
            text=True,
            check=True,
            cwd="../terraform"  # Run from the ansible directory
        )
        terraform_output = json.loads(result.stdout)
    except (subprocess.CalledProcessError, FileNotFoundError, json.JSONDecodeError) as e:
        print(f"Error running terraform output: {e}")
        return

    master_ip = terraform_output.get("master_ip", {}).get("value")
    worker_ips = terraform_output.get("worker_ips", {}).get("value", [])

    if not master_ip:
        print("Could not find master_ip in terraform output")
        return

    inventory = {
        "master": {
            "hosts": [master_ip],
            "vars": {
                "ansible_user": "((your_ansible_user))"
            }
        },
        "workers": {
            "hosts": worker_ips,
            "vars": {
                "ansible_user": "((your_ansible_user))"
            }
        },
        "_meta": {
            "hostvars": {}
        }
    }

    print(json.dumps(inventory, indent=2))

if __name__ == "__main__":
    main()
