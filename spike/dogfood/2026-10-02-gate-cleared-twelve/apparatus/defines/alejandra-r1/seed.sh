set -eu
rm -rf /s/alejandra && mkdir -p /s/alejandra/proj && cd /s/alejandra/proj
printf '{pkgs,...}: {a=1;\n  b =   [ 1 2  3];\n    c = pkgs.hello;}\n' > a.nix
