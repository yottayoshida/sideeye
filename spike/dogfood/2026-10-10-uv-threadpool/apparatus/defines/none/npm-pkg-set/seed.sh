set -eu
rm -rf /s/npm-pkg-set && mkdir -p /s/npm-pkg-set/state
printf '{\n  "name": "probe-proj",\n  "version": "1.0.0",\n  "description": "first"\n}\n' > /s/npm-pkg-set/state/package.json
