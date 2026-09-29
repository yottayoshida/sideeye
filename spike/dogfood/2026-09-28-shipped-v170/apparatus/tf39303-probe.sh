#!/bin/sh
# Mode and symlink behaviour of `terraform fmt`, one binary per box. Every command is echoed.
run() { echo "\$ $*"; sh -c "$*" 2>&1; }
unf='variable "a" {\ndefault="x"\n  type =    string\n}\n'
mk() { printf "$unf" > "$1"; }
terraform version | head -1
echo; echo "## mode"
rm -rf /m && mkdir /m && cd /m
for m in 600 755 664; do mk f$m.tf; chmod $m f$m.tf; done
run 'stat -c "%a %n" *.tf'
run 'terraform fmt'
run 'stat -c "%a %n" *.tf'
echo; echo "## relative symlink, fmt run from the parent (-recursive)"
rm -rf /r && mkdir -p /r/shared /r/mod && mk /r/shared/main.tf && ln -s ../shared/main.tf /r/mod/main.tf
cd /r
run 'terraform fmt -recursive; echo "exit $?"'
run 'ls -l mod shared; find / -xdev -name "main.tf*" -newer /r/shared 2>/dev/null | grep -v "^/r/" ; cat shared/main.tf'
echo; echo "## relative symlink, fmt given the subdirectory"
rm -rf /r && mkdir -p /r/shared /r/mod && mk /r/shared/main.tf && ln -s ../shared/main.tf /r/mod/main.tf
cd /r
run 'terraform fmt mod; echo "exit $?"'
run 'ls -l mod shared; cat shared/main.tf'
echo; echo "## relative symlink, fmt run inside the link's own directory (control)"
rm -rf /r && mkdir -p /r/shared /r/mod && mk /r/shared/main.tf && ln -s ../shared/main.tf /r/mod/main.tf
cd /r/mod
run 'terraform fmt; echo "exit $?"'
run 'ls -l /r/mod /r/shared; cat /r/shared/main.tf'
echo; echo "## ulimit -f 0"
sh /ap/defines/terraform/seed.sh; cd /s/terraform/proj
run 'wc -c < main.tf'
run '( ulimit -f 0; terraform fmt ); echo "exit $?"'
run 'wc -c < main.tf; ls -A'
