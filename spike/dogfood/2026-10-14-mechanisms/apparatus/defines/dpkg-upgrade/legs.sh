# One broken state per leg of CANDIDATES.md 2.2, each breaking that leg alone, on the completed state.
LEGS="a b"
# Not demo's list file removed: dpkg --verify then fails too, and leg b would go red with it.
break_a() { printf '\nPackage: ghost\nStatus: install reinstreq half-installed\nVersion: 1.0\nArchitecture: all\nMaintainer: x <x@example.invalid>\nDescription: ghost\n' >> /s/dk/admin/status; }
break_b() { printf 'not the packaged bytes\n' > /s/dk/root/usr/share/demo/data2.txt; }
