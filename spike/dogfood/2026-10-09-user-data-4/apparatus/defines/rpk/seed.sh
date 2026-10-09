set -eu
# Two rpk profiles, created by rpk itself; `profile use a` rewrites rpk.yaml (lab 18: a temporary
# name opened O_TRUNC, renamed over rpk.yaml, no fsync).
rm -rf /s/aux/home/.config/rpk /s/rpk-in && mkdir -p /s/rpk-in
rpk profile create a > /s/rpk-seed.log 2>&1
rpk profile create b >> /s/rpk-seed.log 2>&1
grep -q 'current_profile: b' /s/aux/home/.config/rpk/rpk.yaml
