set -eu
# scw refuses `config set` when its config file does not exist (lab 1), and `scw init` is
# interactive and reaches the network; so the file is seeded by hand with the keys the
# command will rewrite. The clock-stamped update check lands under XDG_CACHE_HOME, outside --state.
rm -rf /s/aux/home/.config/scw /s/scw-in && mkdir -p /s/aux/home/.config/scw /s/scw-in
printf 'default_region: nl-ams\ndefault_zone: nl-ams-1\nsend_telemetry: false\nprofiles:\n  prod:\n    default_region: fr-par\n    default_zone: fr-par-1\n' > /s/aux/home/.config/scw/config.yaml
chmod 0600 /s/aux/home/.config/scw/config.yaml
grep -q nl-ams /s/aux/home/.config/scw/config.yaml
