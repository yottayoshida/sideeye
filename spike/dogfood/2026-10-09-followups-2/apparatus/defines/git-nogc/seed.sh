set -eu
rm -rf /s/git && mkdir -p /s/git/state
cd /s/git/state
git init -q .
git config user.name probe
git config user.email probe@example.invalid
git config gc.autoPackLimit 2
for i in 1 2 3; do
  printf 'line %s\n' "$i" > "f$i.txt"
  git add "f$i.txt"
  git -c gc.auto=0 -c maintenance.auto=false commit -q -m "c$i"
  git repack -q
done
printf 'change\n' >> f1.txt
git add f1.txt
