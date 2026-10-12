printf '/usr/lib/aarch64-linux-gnu/faketime/libfaketime.so.1\n' > /etc/ld.so.preload
export FAKETIME="2026-01-01 00:00:00"
export TMPDIR=/s/fc/.tmp HOME=/s/fc/.home XDG_CONFIG_HOME=/s/fc/.home/.config XDG_DATA_HOME=/s/fc/.home/.local/share \
       XDG_STATE_HOME=/s/fc/.home/.local/state XDG_CACHE_HOME=/s/fc/.home/.cache
