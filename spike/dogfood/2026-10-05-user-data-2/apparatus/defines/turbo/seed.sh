set -eu
rm -rf /s/aux/home/.config/turborepo /s/turbo-in && mkdir -p /s/aux/home/.config/turborepo /s/turbo-in
printf '{\n  "telemetry_enabled": true,\n  "telemetry_id": "3691f04b0746bce5f7edb6d219ee133c1d6b8346f2c92e408b22b379c9ef5c68",\n  "telemetry_salt": "ee1371b9-85a0-458a-97d2-b7f54c29f2b9",\n  "telemetry_alerted": "2026-09-01T00:00:00Z"\n}' > /s/aux/home/.config/turborepo/telemetry.json
