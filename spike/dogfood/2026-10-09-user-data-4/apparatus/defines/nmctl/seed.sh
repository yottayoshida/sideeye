set -eu
# One context already set (nmctl writes ~/.netmaker/config.yml, master key and all); the
# operation adds a second, which rewrites the whole file (lab 8: O_RDWR|O_CREAT|O_TRUNC).
rm -rf /s/aux/home/.netmaker /s/nm-in && mkdir -p /s/nm-in
nmctl context set c0 --endpoint=https://api.example.org --master_key=k0-not-a-real-key > /s/nm-seed.log 2>&1
grep -q k0-not-a-real-key /s/aux/home/.netmaker/config.yml
