set -eu
rm -rf /s/juju /s/juju-in && mkdir -p /s/juju-in
printf 'credentials:\n  aws:\n    work:\n      auth-type: access-key\n      access-key: FAKE-ACCESS-ID-00001\n      secret-key: example-secret-1\n    home:\n      auth-type: access-key\n      access-key: FAKE-ACCESS-ID-00002\n      secret-key: example-secret-2\n' > /s/juju-in/creds.yaml
JUJU_DATA=/s/juju juju add-credential aws -f /s/juju-in/creds.yaml --client > /s/juju-in/seed.log 2>&1
test -s /s/juju/credentials.yaml
