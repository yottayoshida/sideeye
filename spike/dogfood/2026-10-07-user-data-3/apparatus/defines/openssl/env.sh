# The clock pin docs/apparatus.md gives: libfaketime through /etc/ld.so.preload (never LD_PRELOAD,
# which Sideeye replaces), the time frozen. `openssl ca -revoke` writes the revocation time into
# index.txt, so two runs differed there (transcripts/entry-candidates.txt); the gate's next step
# asked for this pin. Written when this file is sourced, so the define runs in a box of its own.
echo /usr/lib/aarch64-linux-gnu/faketime/libfaketime.so.1 > /etc/ld.so.preload
export FAKETIME='2026-10-01 00:00:00'
