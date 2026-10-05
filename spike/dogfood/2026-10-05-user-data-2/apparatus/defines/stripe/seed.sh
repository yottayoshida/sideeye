set -eu
rm -rf /s/aux/home/.config/stripe /s/stripe-in && mkdir -p /s/aux/home/.config/stripe /s/stripe-in
printf "color = ''\nmachine_uuid = '0b6f2c1e-1d2a-4c3b-9e8f-7a6b5c4d3e2f'\nproject-name = 'default'\n\n[default]\n  color = 'on'\n  device_name = 'laptop'\n  test_mode_api_key = 'sk_test_aaaa'\n  test_mode_pub_key = 'pk_test_aaaa'\n\n[work]\n  test_mode_api_key = 'sk_test_bbbb'\n" > /s/aux/home/.config/stripe/config.toml
