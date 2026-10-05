set -eu
rm -rf /s/pio /s/pio-in && mkdir -p /s/pio /s/pio-in
printf '{"last_version": "6.2.0", "last_check": {"platformio_upgrade": 1790000000, "prune_system": 1790000000}, "settings": {"enable_telemetry": false, "projects_dir": "/home/me/firmware"}}' > /s/pio/appstate.json
