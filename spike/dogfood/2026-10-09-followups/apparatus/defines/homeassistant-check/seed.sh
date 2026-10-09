set -eu
# 2026-10-05 user-data-2's Home Assistant define, unchanged, with the checker the scratch declaration needs.
rm -rf /s/ha /s/ha-in && mkdir -p /s/ha /s/ha-in
hass --script auth -c /s/ha add alice pw-one > /s/ha-in/seed.log 2>&1
hass --script auth -c /s/ha add bob pw-two >> /s/ha-in/seed.log 2>&1
test -s /s/ha/.storage/auth_provider.homeassistant
# The checker, outside --state (apparatus/defines/homeassistant-check/check.sh).
install -m 755 /ap/defines/homeassistant-check/check.sh /s/ha-check.sh
