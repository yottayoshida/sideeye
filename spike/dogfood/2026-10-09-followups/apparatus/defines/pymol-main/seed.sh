set -eu
# 2026-10-05 user-data-2's pymol define, with PyMOL built from master at edcda80f3a (PR #521).
rm -rf /s/pm /s/pm-in && mkdir -p /s/pm /s/pm-in
printf 'fragment ala\nfragment gly\nsave /s/pm/model.pse\n' > /s/pm-in/make.pml
/opt/pymol-main/bin/python -m pymol -cq /s/pm-in/make.pml > /s/pm-in/make.log 2>&1
printf 'set bg_rgb, white\ncolor red, ala\nsave /s/pm/model.pse\n' > /s/pm-in/edit.pml
