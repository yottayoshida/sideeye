printf '/opt/pin/pin-random.so\n/usr/lib/aarch64-linux-gnu/faketime/libfaketime.so.1\n' > /etc/ld.so.preload
export FAKETIME='2026-01-01 00:00:00'
