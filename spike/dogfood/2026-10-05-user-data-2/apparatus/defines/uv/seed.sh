set -eu
rm -rf /s/uvd /s/uv-in && mkdir -p /s/uvd /s/uv-in
XDG_DATA_HOME=/s/uvd /opt/py/bin/uv auth login https://pkgs.example.internal/simple --username alice --password pw1 > /s/uv-in/seed.log 2>&1
XDG_DATA_HOME=/s/uvd /opt/py/bin/uv auth login https://mirror.example.org/simple --username bob --password pw2 >> /s/uv-in/seed.log 2>&1
test -s /s/uvd/uv/credentials/credentials.toml
