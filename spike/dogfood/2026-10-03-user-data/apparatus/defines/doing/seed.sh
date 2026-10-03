set -eu
rm -rf /s/doing /s/doing-in && mkdir -p /s/doing /s/doing-in /s/aux/home/.config/doing
printf -- '---\ndoing_file: /s/doing/doing.md\ncurrent_section: Currently\nbackup_dir: /s/doing-in/backups\n' > /s/aux/home/.config/doing/config.yml
printf 'Currently:\n\t- 2026-10-01 09:00 | met the auditors <aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa>\n\t- 2026-10-02 10:30 | reconciled september <bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb>\n' > /s/doing/doing.md
