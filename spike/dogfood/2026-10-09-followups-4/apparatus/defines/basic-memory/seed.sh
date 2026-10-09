set -eu
rm -rf /s/bm /s/bm-in /s/aux/home/.basic-memory && mkdir -p /s/bm /s/bm-in
basic-memory project add notes /s/bm --default > /s/bm-in/seed.log 2>&1
basic-memory tool write-note --project notes --title Plans --folder notes --content '# Plans
- renew passport
- book the dentist' >> /s/bm-in/seed.log 2>&1
test -s /s/bm/notes/Plans.md
