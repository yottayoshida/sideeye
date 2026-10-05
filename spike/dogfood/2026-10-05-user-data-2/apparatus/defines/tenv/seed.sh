set -eu
rm -rf /s/tenv /s/tenv-in && mkdir -p /s/tenv/Terraform /s/tenv-in
printf '>=1.5.0' > /s/tenv/Terraform/constraint
