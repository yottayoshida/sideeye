set -eu
rm -rf /s/aux/home/.config/ferium /s/ferium-in && mkdir -p /s/ferium-in
for n in p1 p2 p3; do
  ferium profile create --name $n --game-version 1.20.1 --mod-loader fabric --output-dir /s/ferium-in/$n >> /s/ferium-in/seed.log 2>&1
done
ferium profile switch p1 >> /s/ferium-in/seed.log 2>&1
grep -q p2 /s/aux/home/.config/ferium/config.json
