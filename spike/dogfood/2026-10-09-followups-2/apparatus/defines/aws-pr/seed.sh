set -eu
# 2026-09-16 outside-git's aws-cli define; the binary is PR #10649 at c7999845b3.
# Two profiles with fake keys; the operation rotates the second profile's secret.
rm -rf /s/aws && mkdir -p /s/aws
printf '[default]\nregion = us-east-1\noutput = json\n\n[profile work]\nregion = eu-west-1\n' > /s/aws/config
printf '[default]\naws_access_key_id = FAKE-ID-DEFAULT-0001\naws_secret_access_key = fake-secret-default-for-probe-only-000000\n\n[work]\naws_access_key_id = FAKE-ID-WORK-0000001\naws_secret_access_key = fake-secret-work-for-probe-only-00000000\n' > /s/aws/credentials
