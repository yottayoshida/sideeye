set -eu
rm -rf /s/gofumpt && mkdir -p /s/gofumpt/proj && cd /s/gofumpt/proj
printf 'package main\n\nimport "fmt"\n\nfunc main() {\n\n\tvar x = 1\n\tfmt.Println(x)\n\n}\n' > main.go
