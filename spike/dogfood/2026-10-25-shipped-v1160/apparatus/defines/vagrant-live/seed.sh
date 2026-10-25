set -eu
# The vagrant define's home, plus one machine that is still alive: a project whose Vagrantfile and
# .vagrant directory exist and whose VirtualBox VM answers running (a stand-in VBoxManage on PATH,
# declared as apparatus). `global-status --prune` removes the five dead entries and keeps this one,
# saving the index after each removal.
rm -rf /s/vagrant.d /s/vagrantaux && mkdir -p /s/vagrant.d /s/vagrantaux/bin
cp /ap/defines/vagrant-live/VBoxManage /s/vagrantaux/bin/VBoxManage && chmod 755 /s/vagrantaux/bin/VBoxManage
. /ap/defines/vagrant-live/env.sh
ruby /opt/vagrant-gems/bin/vagrant global-status > /dev/null
p=/s/vagrantaux/payments
mkdir -p $p/.vagrant/machines/web/virtualbox
cat > $p/Vagrantfile <<'EOF'
Vagrant.configure("2") do |config|
  config.vm.box = "bento/debian-13"
  config.vm.define "web"
end
EOF
live=00000000000000000000000000c0ffee
printf '8b3c0c5e-2f4c-4d7a-9a51-000000000001' > $p/.vagrant/machines/web/virtualbox/id
printf '%s' "$live" > $p/.vagrant/machines/web/virtualbox/index_uuid
mkdir -p /s/vagrant.d/data/machine-index
python3 - "$live" "$p" <<'PY'
import json, sys
live, proj = sys.argv[1], sys.argv[2]
machines = {}
for i, (name, prov, p) in enumerate([
        ("default", "virtualbox", "billing-api"), ("db", "libvirt", "billing-api"),
        ("web", "virtualbox", "storefront"), ("worker", "docker", "storefront"),
        ("devbox", "vmware_desktop", "dotfiles")]):
    machines["%032x" % (0x5eed0000 + i)] = {
        "name": name, "provider": prov, "architecture": None, "state": "running",
        "vagrantfile_name": None, "vagrantfile_path": "/home/alice/src/%s" % p,
        "local_data_path": "/home/alice/src/%s/.vagrant" % p,
        "updated_at": "2026-10-%02dT09:00:00Z" % (10 + i), "extra_data": {}}
machines[live] = {"name": "web", "provider": "virtualbox", "architecture": None, "state": "running",
    "vagrantfile_name": None, "vagrantfile_path": proj, "local_data_path": proj + "/.vagrant",
    "updated_at": "2026-10-20T09:00:00Z", "extra_data": {"box": {"name": "bento/debian-13", "provider": "virtualbox", "version": "202610.01.0"}}}
json.dump({"version": 1, "machines": machines}, open("/s/vagrant.d/data/machine-index/index", "w"))
PY
