set -eu
rm -rf /s/fish && mkdir -p /s/fish/state
mkdir -p "/s/fish/state"
XDG_CONFIG_HOME="/s/fish/state" fish -c 'set -U MARKER_KEPT keep-me' >/dev/null
XDG_CONFIG_HOME="/s/fish/state" fish -c 'set -U MARKER_SECOND also-here' >/dev/null
ls -la "/s/fish/state/fish" 2>/dev/null | head -5
