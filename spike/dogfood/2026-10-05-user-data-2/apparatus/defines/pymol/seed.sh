set -eu
rm -rf /s/pm /s/pm-in && mkdir -p /s/pm /s/pm-in
printf 'fragment ala\nfragment gly\nsave /s/pm/model.pse\n' > /s/pm-in/make.pml
/usr/bin/python3 -m pymol -cq /s/pm-in/make.pml > /s/pm-in/make.log 2>&1
printf 'set bg_rgb, white\ncolor red, ala\nsave /s/pm/model.pse\n' > /s/pm-in/edit.pml
