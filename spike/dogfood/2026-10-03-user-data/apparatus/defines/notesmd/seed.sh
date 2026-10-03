set -eu
rm -rf /s/notes /s/notes-in && mkdir -p /s/notes/vault/projects /s/notes/vault/daily /s/notes-in /s/aux/home/.config/obsidian
printf '{"vaults":{"v1":{"path":"/s/notes/vault","ts":1,"open":true}}}\n' > /s/aux/home/.config/obsidian/obsidian.json
printf '# Alpha\nThe alpha plan.\n' > /s/notes/vault/projects/alpha.md
printf 'Worked on [[alpha]] today.\nSee [[projects/alpha]].\n' > /s/notes/vault/daily/2026-10-01.md
printf 'Index: [[alpha]], [[beta]]\n' > /s/notes/vault/index.md
