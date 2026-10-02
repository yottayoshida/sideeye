set -eu
# One store made once and copied into the judged root before every engine run, so each world
# starts from the same bytes rather than from a fresh `gopass setup` with a fresh age key — the
# 2026-09-27 run made the golden store once in run.sh and copied it in gp-setup.sh. The golden
# store is rebuilt only when it is missing.
G=/s/gopass/golden
if [ ! -d "$G/.local/share/gopass/stores/root" ]; then
    rm -rf "$G" && mkdir -p "$G"
    GOPASS_HOMEDIR=$G GOPASS_AGE_PASSWORD=testpassphrase /usr/local/bin/gopass --yes setup \
        --crypto age --storage fs --name tester --email tester@example.com > /s/gopass/golden-setup.txt 2>&1
    printf 'first\n' | GOPASS_HOMEDIR=$G GOPASS_AGE_PASSWORD=testpassphrase /usr/local/bin/gopass \
        insert -f seed/entry0 >> /s/gopass/golden-setup.txt 2>&1
fi
rm -rf /s/gopass/gp && mkdir -p /s/gopass/gp/.local/share/gopass/stores/root
cp -a "$G/.config" /s/gopass/gp/
cp -a "$G/.local/share/gopass/stores/root/." /s/gopass/gp/.local/share/gopass/stores/root/
