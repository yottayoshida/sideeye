set -eu
rm -rf /s/ha /s/ha-in && mkdir -p /s/ha /s/ha-in
hass --script auth -c /s/ha add alice pw-one > /s/ha-in/seed.log 2>&1
hass --script auth -c /s/ha add bob pw-two >> /s/ha-in/seed.log 2>&1
test -s /s/ha/.storage/auth_provider.homeassistant
