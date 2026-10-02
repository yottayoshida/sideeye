set -eu
rm -rf /s/terraform && mkdir -p /s/terraform/proj && cd /s/terraform/proj
printf 'variable "a" {\n        default   =   "x"\n        type      =    string\n}\n\nlocals {\n            b   =   var.a\n            c   =   "y"\n}\n' > main.tf
