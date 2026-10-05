set -eu
rm -rf /s/az /s/az-in && mkdir -p /s/az /s/az-in
printf '[core]\noutput = json\ncollect_telemetry = false\n\n[defaults]\nlocation = japaneast\ngroup = rg-home\n' > /s/az/config
