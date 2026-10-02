#!/bin/sh
# The terraform define's checker, on a seed that formatting makes shorter (135 bytes to 86):
# terraform must still parse main.tf, and both blocks must still be in it, formatted or not.
f=/s/terraform/proj/main.tf
terraform fmt -write=false -list=false "$f" > /dev/null 2>&1 || { echo "terraform cannot parse main.tf" >&2; exit 1; }
grep -q '^variable "a"' "$f" || { echo "the variable block is gone" >&2; exit 1; }
grep -q '^locals' "$f" || { echo "the locals block is gone" >&2; exit 1; }
