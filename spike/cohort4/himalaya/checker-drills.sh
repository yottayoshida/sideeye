#!/bin/sh
# Checker drills for the himalaya define: every leg seen red once, on its
# own, and the whole checker green on the state the un-killed operation
# leaves. The cohort rule is that an assertion nobody has watched fail is
# not yet an assertion.
#
# Each case builds a store, damages exactly one thing, runs the committed
# check.sh against it through SIDEEYE_STATE_DIR, and requires the checker
# to fail WITH THE EXPECTED LEG NAMED. A case that goes red through some
# other leg is a failure of the drill, not a pass: it would mean the leg
# under test is dead and another one is carrying it.
#
# Engine-free: no kill, no engine, no shim. Only the checker runs.
set -u
CHECK=$(cd "$(dirname "$0")/ops" && pwd)/check.sh
P=/tmp/cohort4/himalaya
W=/tmp/drills-himalaya
MSGID='1700000000.#0M0P1.probehost'
FAILS=0

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

# The ambient the checker's leg C compares against, and the store shape
# every case starts from.
setup_ambient() {
    rm -rf "${P:?}/store" "${P:?}/home" "${P:?}/xdg"
    mkdir -p "$P/home" "$P/xdg"
    cat > "$P/config.toml" <<EOF
[accounts.probe]
default = true
maildir.root = "$P/store"
EOF
}

build() { # dir with-copy(yes/no)
    d=$1
    rm -rf "${d:?}"
    mkdir -p "$d/cur" "$d/new" "$d/tmp" "$d/Archive/cur" "$d/Archive/new" "$d/Archive/tmp"
    msg_bytes > "$d/cur/$MSGID:2,S"
    [ "$2" = yes ] && msg_bytes > "$d/Archive/cur/1767225600.#0M1P77.somehost:2,S"
    return 0
}

# run <name> <expect: green|leg-substring> <dir>
run() {
    name=$1; expect=$2; d=$3
    out=$(SIDEEYE_STATE_DIR="$d" sh "$CHECK" 2>&1); rc=$?
    if [ "$expect" = green ]; then
        if [ "$rc" -eq 0 ]; then echo "drill ok   $name: checker green as required"
        else echo "drill FAIL $name: checker went red on a state it must accept: $out"; FAILS=$((FAILS+1)); fi
        return 0
    fi
    if [ "$rc" -eq 0 ]; then
        echo "drill FAIL $name: checker stayed GREEN on damage it must catch"
        FAILS=$((FAILS+1)); return 0
    fi
    case "$out" in
        *"$expect"*) echo "drill ok   $name: red through the expected leg: $out" ;;
        *) echo "drill FAIL $name: red, but through the WRONG leg (wanted '$expect'): $out"; FAILS=$((FAILS+1)) ;;
    esac
}

setup_ambient
echo "== the two states the operation itself can leave (both must be green)"
build "$W/green-absent" no;  run "green/copy-absent"  green "$W/green-absent"
build "$W/green-present" yes; run "green/copy-present" green "$W/green-present"

echo ""
echo "== guard"
build "$W/g1" yes; rm -rf "$W/g1/Archive/tmp"
run "guard/missing-dir" "has lost its Archive/tmp directory" "$W/g1"
build "$W/g2" yes; : > "$W/g2/stray"
run "guard/stray-root-entry" "entries this operation cannot produce" "$W/g2"
build "$W/g3" yes; : > "$W/g3/cur/another:2,S"
run "guard/extra-source-message" "source folder holds entries" "$W/g3"
build "$W/g4" yes; : > "$W/g4/Archive/tmp/leftover"
run "guard/staged-leftover" "new/ or tmp/ is not empty" "$W/g4"
build "$W/g5" yes; msg_bytes > "$W/g5/Archive/cur/1767225600.#0M2P78.somehost:2,S"
run "guard/two-copies" "cannot produce more than one" "$W/g5"

echo ""
echo "== leg D: the copy is all-or-nothing"
build "$W/d1" yes; : > "$W/d1/Archive/cur/1767225600.#0M1P77.somehost:2,S"
run "legD/zero-length-copy" "leg D: the copy is present but its bytes" "$W/d1"
build "$W/d2" yes; msg_bytes | head -c 120 > "$W/d2/Archive/cur/1767225600.#0M1P77.somehost:2,S"
run "legD/cut-mid-headers" "leg D: the copy is present but its bytes" "$W/d2"
build "$W/d3" yes; mv "$W/d3/Archive/cur/1767225600.#0M1P77.somehost:2,S" "$W/d3/Archive/cur/1767225600.#0M1P77.somehost"
run "legD/flags-lost" "leg D: the copy has lost the source's maildir flag suffix" "$W/d3"
build "$W/d4" yes; rm "$W/d4/Archive/cur/1767225600.#0M1P77.somehost:2,S"
ln -s /nowhere "$W/d4/Archive/cur/1767225600.#0M1P77.somehost:2,S"
run "legD/dangling-symlink" "leg D: the target folder holds an entry that is not a plain file" "$W/d4"

echo ""
echo "== leg E: the source is conserved"
build "$W/e1" yes; printf 'clobbered\n' > "$W/e1/cur/$MSGID:2,S"
run "legE/source-rewritten" "leg E: the source message's bytes changed" "$W/e1"

echo ""
echo "== leg C: the outside-root configuration is conserved"
build "$W/c1" yes
cp "$P/config.toml" "$W/config.saved"
printf 'tampered\n' >> "$P/config.toml"
run "legC/config-changed" "leg C: the outside-root account configuration changed" "$W/c1"
cp "$W/config.saved" "$P/config.toml"

echo ""
echo "== leg R: himalaya's own reader agrees"
# Leg R cannot be reached by damaging the store: every state that makes
# the reader disagree with the disk is caught by an earlier leg first
# (a second message trips the guard's entry count, a torn copy trips leg
# D's bytes). A leg nobody has watched fail is not an assertion, so its
# predicate is exercised directly instead, by putting a reader in front
# of the real one that answers wrongly on purpose. Same philosophy as the
# decoy shim this repository uses to pin a phrase dyld will not produce.
build "$W/r1" yes
run "legR/preconditions-green" green "$W/r1"

mkdir -p "$W/fake"
cat > "$W/fake/himalaya" <<'FAKE'
#!/bin/sh
# A reader that lists nothing, whatever is on disk.
case "$*" in
    *"envelope list"*) printf '┌──┐\n└──┘\n'; exit 0 ;;
    *) exit 0 ;;
esac
FAKE
chmod 755 "$W/fake/himalaya"
build "$W/r2" yes
out=$(SIDEEYE_STATE_DIR="$W/r2" PATH="$W/fake:$PATH" sh "$CHECK" 2>&1); rc=$?
case "$rc:$out" in
    0:*) echo "drill FAIL legR/reader-lists-nothing: checker stayed green"; FAILS=$((FAILS+1)) ;;
    *"leg R: the target folder holds one message but the reader lists 0"*)
        echo "drill ok   legR/reader-lists-nothing: red through the expected leg: $out" ;;
    *) echo "drill FAIL legR/reader-lists-nothing: red through the WRONG leg: $out"; FAILS=$((FAILS+1)) ;;
esac

cat > "$W/fake/himalaya" <<'FAKE'
#!/bin/sh
# A reader that lists the message and then cannot read it back.
case "$*" in
    *"envelope list"*) printf '┌──┐\n│ 1767225600.#0M1P77.somehost ┆ x │\n└──┘\n'; exit 0 ;;
    *"message read"*) echo "cannot read this message" >&2; exit 1 ;;
    *) exit 0 ;;
esac
FAKE
build "$W/r3" yes
out=$(SIDEEYE_STATE_DIR="$W/r3" PATH="$W/fake:$PATH" sh "$CHECK" 2>&1); rc=$?
case "$rc:$out" in
    0:*) echo "drill FAIL legR/reader-cannot-read: checker stayed green"; FAILS=$((FAILS+1)) ;;
    *"leg R: the copy is on disk but the reader cannot read it back"*)
        echo "drill ok   legR/reader-cannot-read: red through the expected leg: $out" ;;
    *) echo "drill FAIL legR/reader-cannot-read: red through the WRONG leg: $out"; FAILS=$((FAILS+1)) ;;
esac
echo "   (trial G in pre-define-trials.txt is the measurement that leg R"
echo "    cannot substitute for leg D: a zero-length copy lists as an"
echo "    ordinary envelope, 0 B and blank columns, rc 0.)"

echo ""
echo "== drills failed: $FAILS"
[ "$FAILS" -eq 0 ] || exit 1
exit 0
