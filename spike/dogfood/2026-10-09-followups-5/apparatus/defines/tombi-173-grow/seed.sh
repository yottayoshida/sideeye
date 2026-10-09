set -eu
# 2026-10-02's seed (tombi-r1): formatting makes the file longer.
rm -rf /s/tombi && mkdir -p /s/tombi/proj && cd /s/tombi/proj
printf '[a]\nb=1\nc   =  "x"\n[d]\ne=[1,2,   3]\n' > a.toml
