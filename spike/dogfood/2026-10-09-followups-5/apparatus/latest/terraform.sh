# hashicorp/terraform#39299, the report's steps.
mkdir -p /work/tf && cd /work/tf
printf 'variable "a" {\ndefault="x"\n  type =    string\n}\n\nlocals {\n    b = var.a\nc =   "y"\n}\n' > main.tf
wc -c < main.tf
( ulimit -f 0; TF_LOG=trace /opt/bin/terraform fmt -no-color 2>&1 | grep -E 'Formatting|Failed|Error' ); echo "exit $?"
wc -c < main.tf
