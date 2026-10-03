set -eu
rm -rf /s/podman && mkdir -p /s/podman/config/containers
printf '{"Connection":{"Default":"home","Connections":{"home":{"URI":"ssh://me@home.example.invalid:22/run/podman/podman.sock","Identity":"/s/aux/home/.ssh/id_home"},"work":{"URI":"ssh://me@work.example.invalid:22/run/podman/podman.sock","Identity":"/s/aux/home/.ssh/id_work"}}},"Farm":{}}\n' > /s/podman/config/containers/podman-connections.json
