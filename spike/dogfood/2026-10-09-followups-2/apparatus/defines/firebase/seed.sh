set -eu
rm -rf /s/aux/home/.config/configstore /s/firebase-in && mkdir -p /s/aux/home/.config/configstore /s/firebase-in
printf '{\n\t"user": {\n\t\t"email": "alice@example.com"\n\t},\n\t"tokens": {\n\t\t"refresh_token": "1//example-refresh-token"\n\t},\n\t"previews": {\n\t\t"webframeworks": true\n\t}\n}' > /s/aux/home/.config/configstore/firebase-tools.json
printf '{\n\t"optOut": false,\n\t"lastUpdateCheck": 1790000000000\n}' > /s/aux/home/.config/configstore/update-notifier-firebase-tools.json
