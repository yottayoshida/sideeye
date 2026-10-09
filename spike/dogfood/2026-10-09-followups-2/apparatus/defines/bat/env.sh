# What 2026-09-16-userview-3's run-r3b.sh (lines 60-61) did before starting the engine, so
# that the define's `apparatus` declaration is met: libfaketime preloaded system-wide and the
# clock pinned. The engine, the seed, the operation and the checker all run under it.
FT=$(find /usr/lib -name 'libfaketime.so*' 2>/dev/null | head -1); echo "$FT" > /etc/ld.so.preload
FAKETIME="@2024-01-01 00:00:00"; export FAKETIME
