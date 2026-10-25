set -eu
# VAGRANT_HOME as a user who has run Vagrant for a while has it: the home Vagrant sets up on its first
# command (setup_version, keys, plugin list), and the machine index, the one record of every machine
# Vagrant knows across all projects (`vagrant global-status`, `vagrant destroy <id>` from anywhere).
# Five entries point at project directories that have since been deleted, which `global-status --prune`
# removes one at a time.
rm -rf /s/vagrant.d && mkdir -p /s/vagrant.d
. /ap/defines/vagrant/env.sh
ruby /opt/vagrant-gems/bin/vagrant global-status > /dev/null
mkdir -p /s/vagrant.d/data/machine-index
python3 - <<'PY'
import json
machines = {}
for i, (name, prov, proj) in enumerate([
        ("default", "virtualbox", "billing-api"), ("db", "libvirt", "billing-api"),
        ("web", "virtualbox", "storefront"), ("worker", "docker", "storefront"),
        ("devbox", "vmware_desktop", "dotfiles")]):
    mid = "%032x" % (0x5eed0000 + i)
    machines[mid] = {
        "name": name, "provider": prov, "architecture": None, "state": "running",
        "vagrantfile_name": None, "vagrantfile_path": "/home/alice/src/%s" % proj,
        "local_data_path": "/home/alice/src/%s/.vagrant" % proj,
        "updated_at": "2026-10-%02dT09:00:00Z" % (10 + i), "extra_data": {"box": {"name": "bento/debian-13", "provider": prov, "version": "202610.01.0"}},
    }
json.dump({"version": 1, "machines": machines}, open("/s/vagrant.d/data/machine-index/index", "w"))
PY
