#!/bin/sh
# pre-define trials for the himalaya define: what may the checker use?
#
# Two questions, both of which cohort 3 answered the expensive way and
# this define answers before it is written:
#
#   1. Does the reader the checker wants WRITE? papis's `list` minted and
#      persisted a random papis_id into a document that had lost one, so
#      any byte assertion placed after it would have judged the checker's
#      own side effect. Trials A-E snapshot the store around every reader
#      invocation, on healthy and on torn states alike.
#
#   2. Is there a documented recovery to run before the assert? The cohort
#      rule asks for one. papis had a candidate that failed on inspection;
#      himalaya's command surface is enumerated here rather than recalled.
#
# Trials C and D matter most: a maildir reader is entitled to RENAME files
# (new/ to cur/, flag normalisation), and the states this checker will be
# handed are torn ones. A reader that repairs, renames or deletes what it
# reads cannot run before the byte assertions.
#
# Engine-free, kill-free: normal executions only.
set -u
W=/tmp/trials-himalaya
rm -rf "${W:?}"; mkdir -p "$W"
MSGID='1700000000.#0M0P1.probehost'
FAILS=0

note() { echo ""; echo "== $*"; }
say()  { echo "   $*"; }

msg_bytes() {
    cat <<'EOF'
Return-Path: <probe@example.invalid>
Date: Sat, 01 Mar 2026 09:00:00 +0000
From: Probe Author <probe@example.invalid>
To: Probe Target <target@example.invalid>
Subject: Existing message, fixed bytes
Message-ID: <existing0001@example.invalid>

This is the existing message. Its bytes are part of the freeze.
EOF
}

# A store in the shape the define will use, plus a config outside it.
build() { # dir archive-content(empty|whole|torn0|torn-partial)
    d=$1
    rm -rf "${d:?}"; mkdir -p "$d/store/cur" "$d/store/new" "$d/store/tmp" \
        "$d/store/Archive/cur" "$d/store/Archive/new" "$d/store/Archive/tmp" "$d/home/.config"
    msg_bytes > "$d/store/cur/$MSGID:2,S"
    case "$2" in
        empty) ;;
        whole) msg_bytes > "$d/store/Archive/cur/1767225600.#0M0P4242.host:2,S" ;;
        torn0) : > "$d/store/Archive/cur/1767225600.#0M0P4242.host:2,S" ;;
        torn-partial) msg_bytes | head -c 120 > "$d/store/Archive/cur/1767225600.#0M0P4242.host:2,S" ;;
    esac
    printf '[accounts.probe]\ndefault = true\nmaildir.root = "%s"\n' "$d/store" > "$d/config.toml"
}

# A fingerprint of the whole store: every path, its size, and its bytes.
fingerprint() { # dir
    ( cd "$1/store" && find . | sort | while read -r p; do
        if [ -f "$p" ]; then printf '%s %s %s\n' "$p" "$(wc -c < "$p" | tr -d ' ')" "$(cksum < "$p" | cut -d' ' -f1)"
        else printf '%s DIR\n' "$p"; fi
      done )
}

run_reader() { # label dir content reader-args...
    label=$1; d=$2; content=$3; shift 3
    build "$d" "$content"
    fingerprint "$d" > "$d/before"
    HOME="$d/home" XDG_CONFIG_HOME="$d/home/.config" \
        himalaya -c "$d/config.toml" "$@" > "$d/out" 2> "$d/err"
    rc=$?
    fingerprint "$d" > "$d/after"
    if cmp -s "$d/before" "$d/after"; then mut=no; else mut=YES; fi
    say "$label: rc=$rc, store mutated: $mut"
    say "  stdout (first 2 lines): $(head -2 "$d/out" | tr '\n' '|')"
    [ -s "$d/err" ] && say "  stderr (first line): $(head -1 "$d/err")"
    if [ "$mut" = YES ]; then
        say "  what changed:"; diff "$d/before" "$d/after" | sed 's/^/    /'
        FAILS=$((FAILS + 1))
    fi
}

note "himalaya $(himalaya --version | head -1)"

note "trial A: envelope list on the target folder, healthy store with a whole copy"
run_reader "A" "$W/a" whole envelope list -m Archive

note "trial B: message read of the copied message, healthy store"
build "$W/b" whole
id_b=$(HOME="$W/b/home" XDG_CONFIG_HOME="$W/b/home/.config" \
    himalaya -c "$W/b/config.toml" envelope list -m Archive 2>/dev/null \
    | sed -n 's/.*│ \([0-9][0-9.#A-Za-z]*\) .*/\1/p' | head -1)
say "id as the reader names it: ${id_b:-<none parsed>}"
if [ -n "$id_b" ]; then
    run_reader "B" "$W/b2" whole message read -m Archive "$id_b"
else
    say "B: skipped, the id could not be parsed from the listing"
fi

note "trial C: envelope list on a TORN store (zero-length message in the target folder)"
run_reader "C" "$W/c" torn0 envelope list -m Archive

note "trial D: envelope list on a TORN store (message cut mid-headers)"
run_reader "D" "$W/d" torn-partial envelope list -m Archive

note "trial E: envelope list on the target folder when the copy never happened"
run_reader "E" "$W/e" empty envelope list -m Archive

note "trial G: what does the reader SHOW for a torn message, against a whole one and an absent one?"
# The load-bearing question for the property. If the reader lists a torn
# message as a message, then a crash can leave the store holding an
# envelope the tool presents as real and whose content is gone, and the
# checker's byte assertions are the only thing that can tell.
rows() { # dir content
    build "$1" "$2"
    HOME="$1/home" XDG_CONFIG_HOME="$1/home/.config" \
        himalaya -c "$1/config.toml" envelope list -m Archive 2>/dev/null > "$1/out"
    # Data rows are the ones carrying the minted id; the rest is the frame.
    grep -c '1767225600' "$1/out"
}
for c in whole torn0 torn-partial empty; do
    n=$(rows "$W/g-$c" "$c")
    say "$c: $n row(s) naming the copied message"
done
say "and what the reader prints for the zero-length one:"
HOME="$W/g-torn0/home" XDG_CONFIG_HOME="$W/g-torn0/home/.config" \
    himalaya -c "$W/g-torn0/config.toml" envelope list -m Archive 2>&1 | sed -n '4,6p' | sed 's/^/     /'
say "and its message read:"
HOME="$W/g-torn0/home" XDG_CONFIG_HOME="$W/g-torn0/home/.config" \
    himalaya -c "$W/g-torn0/config.toml" message read -m Archive '1767225600.#0M0P4242.host' > "$W/g-torn0/read.out" 2>&1
say "  rc=$?, bytes of output: $(wc -c < "$W/g-torn0/read.out" | tr -d ' ')"

note "trial F: is there a documented recovery? the top-level command surface"
build "$W/f" whole
HOME="$W/f/home" XDG_CONFIG_HOME="$W/f/home/.config" \
    himalaya -c "$W/f/config.toml" --help 2>&1 | sed -n '/^Commands:/,/^$/p' | sed 's/^/   /'
say "and the maildir subtree:"
HOME="$W/f/home" XDG_CONFIG_HOME="$W/f/home/.config" \
    himalaya -c "$W/f/config.toml" maildir --help 2>&1 | sed -n '/^Commands:/,/^$/p' | sed 's/^/   /'

note "readers that mutated the store: $FAILS"
echo "(a nonzero count is not a failure of this script: it is the fact the"
echo " checker has to be ordered around, exactly as papis's list was.)"
