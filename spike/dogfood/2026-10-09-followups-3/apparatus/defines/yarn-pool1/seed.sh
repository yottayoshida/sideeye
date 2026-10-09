set -eu
# A project with a two-key .yarnrc.yml; `yarn config set` (project scope, no -H) rewrites it
# (lab 8, on the home-scope file: O_WRONLY|O_CREAT|O_TRUNC). Yarn's own caches land under
# XDG/HOME, outside --state.
rm -rf /s/yarn /s/aux/home/.yarnrc.yml /s/aux/home/.yarn && mkdir -p /s/yarn
printf '{ "name": "proj", "version": "1.0.0", "packageManager": "yarn@4.18.1" }\n' > /s/yarn/package.json
printf 'nodeLinker: node-modules\nenableTelemetry: false\n' > /s/yarn/.yarnrc.yml
grep -q nodeLinker /s/yarn/.yarnrc.yml
