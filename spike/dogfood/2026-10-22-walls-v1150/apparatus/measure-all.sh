#!/bin/sh
set -u
here="$(cd "$(dirname "$0")" && pwd)"; scratch=${1:?usage: measure-all.sh <scratch dir> [target ...]}; shift
while read -r target campaign box proc define; do
    [ -n "$target" ] || continue
    if [ $# -gt 0 ]; then
        case " $* " in *" $target "*) ;; *) continue ;; esac
    fi
    echo "=== $target $(date -u +%FT%TZ)"
    sh "$here/measure.sh" "$scratch" "$target" "$campaign" "$box" "$proc" "$define"
done <<'EOF'
logrotate 2026-10-14-mechanisms sideeye-m1014 gate-all.sh logrotate
electrum 2026-10-03-user-data sideeye-ud1003 gate-all.sh electrum
basic-memory 2026-10-05-user-data-2 sideeye-ud1005 gate-all.sh basic-memory
goaccess 2026-10-07-user-data-3 sideeye-ud1007 gate-all.sh goaccess
codex 2026-10-09-followups-4 sideeye-fu4-1009 run.sh codex-scratch
lz4 2026-10-09-followups-4 sideeye-fu4-1009 run.sh lz4-bd
Bitwarden 2026-10-09-followups-3 sideeye-fu3-1009 run.sh bitwarden
flatpak 2026-10-09-followups-3 sideeye-fu3-1009 run.sh flatpak-fat
ostree 2026-10-09-followups-3 sideeye-fu3-1009 run.sh ostree-fat
prek 2026-10-09-followups-3 sideeye-fu3-1009 run.sh prek
rustic 2026-10-09-followups-3 sideeye-fu3-1009 run.sh rustic
steamguard 2026-10-09-followups-3 sideeye-fu3-1009 run.sh steamguard
vercel 2026-10-09-followups-3 sideeye-fu3-1009 run.sh vercel
rrdtool 2026-10-02-unjudged-on-v170 sideeye-uj170 run.sh rrdtool
EOF
