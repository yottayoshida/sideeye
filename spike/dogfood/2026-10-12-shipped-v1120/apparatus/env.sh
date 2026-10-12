# Sourced by run.sh and modes.sh before the engine runs: the environment the 2026-09-16 drivers
# exported (crossed-walls screen.sh:29, screen2.sh:26; outside-git screen.sh:32), so that a
# tool's own files under $HOME — npm's logs and update-notifier stamp, git's user config,
# Bitwarden's app data — land where they did then and not under the box's /root. The engine
# and the operation inherit it, as they did then. A re-measurement that moved HOME as well as
# the engine could not say which of the two changed a result.
AUX=/s/aux
mkdir -p "$AUX/home" "$AUX/tmp" "$AUX/state" "$AUX/data" "$AUX/cache"
export HOME=$AUX/home TMPDIR=$AUX/tmp XDG_STATE_HOME=$AUX/state XDG_DATA_HOME=$AUX/data \
       XDG_CACHE_HOME=$AUX/cache npm_config_update_notifier=false NG_CLI_ANALYTICS=false
