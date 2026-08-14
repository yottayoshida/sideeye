#!/bin/sh
# Campaign-2 Seal B artifact (abook): one normal (non-crash) run per candidate
# form, plus determinism and interactivity probes. Permitted observation under
# ADR 0012: no crash injection, no traces, no damaged stores — every store a
# probe touches was written by abook itself in this same script or is empty /
# absent (documented-normal per abookrc(5): the config and, by the same
# convention, the data directory need not pre-exist). Interactivity probes give
# the child EOF on stdin, the same condition the exploration engine imposes.
#
# Everything is scratch under /tmp/blind2/normal; HOME points inside it so the
# default $HOME/.abook paths (abook(1)) stay inside the scratch area.
#
# Usage (inside the pinned container, repo mounted at /work):
#   sh /work/spike/blind-hunt2/declaration/abook/transcripts/normal-runs.sh \
#     > /work/spike/blind-hunt2/declaration/abook/transcripts/normal-runs.txt 2>&1
set -u
N=/tmp/blind2/normal
rm -rf "$N"
mkdir -p "$N/home" "$N/a" "$N/b" "$N/c"
export HOME=$N/home

say() { printf '\n===== %s =====\n' "$*"; }
run() {  # run <label> -- cmd...
    lbl=$1; shift; [ "$1" = "--" ] && shift
    printf '$ %s\n' "$*"
    "$@" < /dev/null > "$N/out.txt" 2>&1
    rc=$?
    cat "$N/out.txt"
    printf '[%s rc=%s]\n' "$lbl" "$rc"
}

# Two vCard inputs, hand-written here (well-formed per the same RFC 6350
# delimiters khard's carve-out cited; abook's own --formats names "vcard" as an
# input format). base: Ada (subject) + Grace (bystander). next: Grace + Carol
# (Ada absent, Carol incoming) — the overwrite source.
cat > "$N/base.vcf" <<'EOF'
BEGIN:VCARD
VERSION:3.0
FN:Ada Lovelace
N:Lovelace;Ada;;;
EMAIL:ada@example.com
END:VCARD
BEGIN:VCARD
VERSION:3.0
FN:Grace Hopper
N:Hopper;Grace;;;
EMAIL:grace@example.com
END:VCARD
EOF
cat > "$N/next.vcf" <<'EOF'
BEGIN:VCARD
VERSION:3.0
FN:Grace Hopper
N:Hopper;Grace;;;
EMAIL:grace@example.com
END:VCARD
BEGIN:VCARD
VERSION:3.0
FN:Carol Shaw
N:Shaw;Carol;;;
EMAIL:carol@example.com
END:VCARD
EOF
say "0. inputs"
printf -- '--- base.vcf ---\n'; cat "$N/base.vcf"
printf -- '--- next.vcf ---\n'; cat "$N/next.vcf"

say "1. convert vcard->abook into a fresh file (two entries)"
run convert-fresh -- abook --convert --informat vcard --infile "$N/base.vcf" \
    --outformat abook --outfile "$N/a/addressbook"
printf -- '--- resulting native store (%s bytes) ---\n' "$(wc -c < "$N/a/addressbook" | tr -d ' ')"
cat "$N/a/addressbook"

say "2. determinism: the same convert twice, byte-compared"
run convert-again -- abook --convert --informat vcard --infile "$N/base.vcf" \
    --outformat abook --outfile "$N/b/addressbook"
if cmp -s "$N/a/addressbook" "$N/b/addressbook"; then
    echo "byte-identical: yes"
else
    echo "byte-identical: NO"; cmp "$N/a/addressbook" "$N/b/addressbook" || true
fi

say "3. convert abook->vcard (export beside the store), twice, byte-compared"
run export-1 -- abook --convert --informat abook --infile "$N/a/addressbook" \
    --outformat vcard --outfile "$N/a/export.vcf"
printf -- '--- export.vcf ---\n'; cat "$N/a/export.vcf"
run export-2 -- abook --convert --informat abook --infile "$N/a/addressbook" \
    --outformat vcard --outfile "$N/a/export2.vcf"
if cmp -s "$N/a/export.vcf" "$N/a/export2.vcf"; then
    echo "byte-identical: yes"
else
    echo "byte-identical: NO"; cmp "$N/a/export.vcf" "$N/a/export2.vcf" || true
fi

say "4. convert onto an EXISTING outfile (the overwrite shape: next.vcf over base store)"
cp "$N/a/addressbook" "$N/c/addressbook"
cp "$N/c/addressbook" "$N/c/addressbook.before"
printf -- '--- store before (base: Ada+Grace) ---\n'; cat "$N/c/addressbook"
run convert-overwrite -- abook --convert --informat vcard --infile "$N/next.vcf" \
    --outformat abook --outfile "$N/c/addressbook"
printf -- '--- store after ---\n'; cat "$N/c/addressbook"
if cmp -s "$N/c/addressbook.before" "$N/c/addressbook"; then
    echo "store byte-identical across the refusal: yes (cmp)"
else
    echo "store byte-identical across the refusal: NO"; cmp "$N/c/addressbook.before" "$N/c/addressbook" || true
fi

say "5. mutt-query probes (--datafile BEFORE --mutt-query, per abook(1))"
run query-match     -- abook --datafile "$N/a/addressbook" --mutt-query Grace
run query-nomatch   -- abook --datafile "$N/a/addressbook" --mutt-query Zebra
: > "$N/a/empty"
run query-emptyfile -- abook --datafile "$N/a/empty" --mutt-query Grace
run query-nofile    -- abook --datafile "$N/a/no-such-file" --mutt-query Grace

say "6. interactivity probes (EOF stdin, 10s timeout; the engine gives no stdin)"
run tui        -- timeout 10 abook --datafile "$N/a/addressbook"
run add-email  -- timeout 10 abook --add-email
run add-quiet  -- timeout 10 abook --add-email-quiet
printf -- '--- default datafile after add probes: ---\n'
ls -la "$HOME/.abook/" 2>&1 || echo "(no \$HOME/.abook directory was created)"

say "7. package identity"
dpkg-query -W abook
echo "normal-runs: done"
