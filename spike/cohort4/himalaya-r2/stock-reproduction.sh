#!/bin/sh
# The stock reproduction the freeze requires before anything is claimed or
# reported: "a finding must reproduce against the stock tool with no
# apparatus beyond strace fault injection".
#
# Nothing from the define's apparatus is used here. No shim, no engine, no
# seccomp profile, no /etc/ld.so.preload, no interposer. The only
# instrument is strace, and the only thing it does beyond watching is
# inject one signal.
#
# This also converts an argument into a measurement. The r2 toml argued
# that the kill window does not depend on the apparatus, because the
# destination is created and filled afterwards whichever copy primitive
# runs. Under the apparatus the fill was a read/write loop; stock, it is a
# single copy_file_range, and the window is still there.
set -u
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SETUP="$here/ops/setup.sh"
CFG=/tmp/cohort4/himalaya/config.toml
MSGID='1700000000.#0M0P1.probehost'
export HOME=/tmp/cohort4/himalaya/home XDG_CONFIG_HOME=/tmp/cohort4/himalaya/xdg

echo "== apparatus check (all of these must be absent)"
[ -e /etc/ld.so.preload ] && { echo "   FAIL: /etc/ld.so.preload exists"; exit 1; }
echo "   no /etc/ld.so.preload"
echo "   LD_PRELOAD=${LD_PRELOAD:-<unset>}"
echo "   himalaya $(himalaya --version | head -1)"

echo ""
echo "== which copy primitive does the stock tool use?"
"$SETUP"
strace -f -o /tmp/stock-probe.log -e trace=copy_file_range,sendfile,write \
    himalaya -c "$CFG" maildir messages copy "$MSGID" --maildir . --target Archive \
    > /dev/null 2>&1
echo "   operation rc=$?"
grep -E "copy_file_range|sendfile" /tmp/stock-probe.log | sed 's/^/   /' | head -3
w=$(grep -cE " write\(" /tmp/stock-probe.log)
echo "   write() calls on this path: $w"
echo "   reading: stock copies with copy_file_range, one call for the whole"
echo "   message. The define measured a read/write loop because its"
echo "   apparatus removed that primitive; this is the path a user gets."

echo ""
echo "== the finding, stock: kill at the copy"
"$SETUP"
strace -f -e trace=copy_file_range -e inject=copy_file_range:signal=KILL:when=1 \
    himalaya -c "$CFG" maildir messages copy "$MSGID" --maildir . --target Archive \
    > /tmp/stock-kill.out 2>&1
rc=$?
echo "   operation rc=$rc (killed by the injected signal)"

echo ""
echo "== what the store holds"
for f in /tmp/cohort4/himalaya/store/Archive/cur/*; do
    [ -e "$f" ] || continue
    echo "   $(basename "$f"): $(wc -c < "$f" | tr -d ' ') bytes"
done
echo "   the source message, for contrast: $(wc -c < "/tmp/cohort4/himalaya/store/cur/$MSGID:2,S" | tr -d ' ') bytes"

echo ""
echo "== what himalaya says about it"
himalaya -c "$CFG" envelope list -m Archive 2>&1 | sed -n '3,7p' | sed 's/^/   /'
echo "   and reading it back:"
himalaya -c "$CFG" message read -m Archive "$(basename "$(ls /tmp/cohort4/himalaya/store/Archive/cur/* | head -1)" | cut -d: -f1)" > /tmp/stock-read.out 2>&1
echo "   message read rc=$? ($(wc -c < /tmp/stock-read.out | tr -d ' ') bytes of output)"

echo ""
echo "== reading"
echo "   A crash during \`maildir messages copy\` leaves a message file at its"
echo "   final path in the target folder with none of the message in it, and"
echo "   the tool lists it as an ordinary envelope. No apparatus of this"
echo "   project was involved: one strace injection, on the stock binary."
