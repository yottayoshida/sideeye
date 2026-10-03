set -eu
rm -rf /s/talos /s/talos-in && mkdir -p /s/talos /s/talos-in && cd /s/talos-in
talosctl gen config home https://10.0.0.1:6443 --output-types talosconfig -o /s/talos/config > /dev/null 2>&1
talosctl gen config work https://10.0.0.2:6443 --output-types talosconfig -o /s/talos-in/work > /dev/null 2>&1
talosctl --talosconfig /s/talos/config config merge /s/talos-in/work > /dev/null 2>&1
talosctl --talosconfig /s/talos/config config context home > /dev/null 2>&1
