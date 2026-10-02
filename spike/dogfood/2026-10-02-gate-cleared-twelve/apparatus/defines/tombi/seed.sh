set -eu
rm -rf /s/tombi && mkdir -p /s/tombi/proj && cd /s/tombi/proj
printf '[a]\nb=1\nc   =  "x"\n[d]\ne=[1,2,   3]\n' > a.toml
