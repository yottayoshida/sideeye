set -eu
. /ap/defines/plakar/env.sh
rm -rf /s/plakar /s/plakar-in "$HOME/.cache/plakar" && mkdir -p /s/plakar /s/plakar-in/data
plakar -disable-security-check > /s/plakar-in/seed.log 2>&1
echo a > /s/plakar-in/data/a
plakar at /s/plakar/repo create >> /s/plakar-in/seed.log 2>&1
plakar at /s/plakar/repo backup -tag old /s/plakar-in/data >> /s/plakar-in/seed.log 2>&1
echo b > /s/plakar-in/data/b
plakar at /s/plakar/repo backup -tag new /s/plakar-in/data >> /s/plakar-in/seed.log 2>&1
test "$(plakar at /s/plakar/repo ls 2>/dev/null | wc -l)" = 2
