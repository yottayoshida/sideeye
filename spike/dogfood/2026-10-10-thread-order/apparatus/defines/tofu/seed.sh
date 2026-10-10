set -eu
rm -rf /s/tofu && mkdir -p /s/tofu && cd /s/tofu
printf 'resource "terraform_data" "a" { input = "alpha" }\nresource "terraform_data" "b" { input = "beta" }\nresource "terraform_data" "c" { input = "gamma" }\n' > main.tf
TF_IN_AUTOMATION=1 tofu init -input=false > /dev/null
TF_IN_AUTOMATION=1 tofu apply -auto-approve -input=false > /dev/null
