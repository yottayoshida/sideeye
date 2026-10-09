# h2cli names its backup drumkit.xml.<date>_<time>.bak, so two runs differ in a name; the clock pin
# docs/apparatus.md gives, as 2026-10-07's openssl. Written when this file is sourced, so the define
# runs in a box of its own.
echo /usr/lib/aarch64-linux-gnu/faketime/libfaketime.so.1 > /etc/ld.so.preload
export FAKETIME='2026-10-01 00:00:00'
