set -eu
rm -rf /s/terraform && mkdir -p /s/terraform/proj && cd /s/terraform/proj
printf 'variable "a" {\ndefault="x"\n  type =    string\n}\n\nlocals {\n    b = var.a\nc =   "y"\n}\n' > main.tf
