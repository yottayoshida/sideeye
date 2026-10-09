set -eu
rm -rf /s/aux/home/.config/infracost /s/infracost-in && mkdir -p /s/aux/home/.config/infracost /s/infracost-in
printf 'version: "0.1"\ncurrency: EUR\nenable_cloud: null\nenable_cloud_upload: null\n' > /s/aux/home/.config/infracost/configuration.yml
printf 'version: "0.1"\napi_key: ico-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\npricing_api_endpoint: https://pricing.example.internal\n' > /s/aux/home/.config/infracost/credentials.yml
