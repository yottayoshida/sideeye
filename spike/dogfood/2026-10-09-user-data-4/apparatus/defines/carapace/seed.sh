set -eu
# Two styles already set; the operation sets a third, which rewrites styles.json (lab 10:
# O_WRONLY|O_CREAT|O_TRUNC, then the write).
rm -rf /s/aux/home/.config/carapace /s/cpc && mkdir -p /s/cpc
carapace --style 'carapace.Value=bold,magenta' > /s/cpc-seed.log 2>&1
carapace --style 'carapace.Description=dim' >> /s/cpc-seed.log 2>&1
grep -q Description /s/aux/home/.config/carapace/styles.json
