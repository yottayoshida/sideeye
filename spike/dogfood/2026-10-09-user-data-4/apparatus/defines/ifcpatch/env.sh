# The clock pin docs/apparatus.md gives, as 2026-10-07's openssl: libfaketime through
# /etc/ld.so.preload (never LD_PRELOAD, which Sideeye replaces), the time frozen. ifcopenshell writes
# the time into the IFC header's FILE_NAME, so two runs differ there (lab 15). Written when this file
# is sourced, so the define runs in a box of its own.
echo /usr/lib/aarch64-linux-gnu/faketime/libfaketime.so.1 > /etc/ld.so.preload
export FAKETIME='2026-10-01 00:00:00'
