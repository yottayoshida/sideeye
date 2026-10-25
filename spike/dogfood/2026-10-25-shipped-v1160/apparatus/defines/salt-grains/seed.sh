set -eu
# A masterless minion's configuration directory: the minion config and the grains file the user set
# by hand and with `grains.setval`, which every state and pillar targeting on this machine reads.
# `grains.setval` rewrites that file to add one key. The minion's cache, pki and log live outside
# the state (/s/saltaux), so only what the user keeps is judged.
rm -rf /s/salt /s/saltaux && mkdir -p /s/salt /s/saltaux/cache /s/saltaux/pki /s/saltaux/run /s/saltaux/log
cat > /s/salt/minion <<'EOF'
id: web01.example
file_client: local
enable_fqdns_grains: False
enable_gpu_grains: False
grains_cache: False
cachedir: /s/saltaux/cache
pki_dir: /s/saltaux/pki
sock_dir: /s/saltaux/run
pidfile: /s/saltaux/run/salt-minion.pid
log_file: /s/saltaux/log/minion
log_level_logfile: warning
EOF
cat > /s/salt/grains <<'EOF'
datacenter: tokyo-2
environment: production
owner: platform-team
rack: r12-u07
roles:
- web
- cache
backup_window: 02:00-03:00
cost_center: CC-4410
EOF
