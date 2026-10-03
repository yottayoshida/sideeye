set -eu
rm -rf /s/nushell /s/nushell-in && mkdir -p /s/nushell /s/nushell-in
printf '{"name":"ledger","entries":[1,2,3,4,5],"owner":"me"}\n' > /s/nushell/a.json
printf 'open /s/nushell/a.json | upsert note "kept" | save -f /s/nushell/a.json\n' > /s/nushell-in/edit.nu
