# migrationtools — wall W3 (no command of its own)

Debian description: "Migration scripts for LDAP"; `implemented-in::perl`,
`use::converting`, `works-with::db`. Installed 48-1 in the trixie image.
Freshness: the word-match grep names `spike/unknown-rate/b-candidates.txt` —
the first group's pool, in which this package sat unselected and unread —
and nothing else; not contact.

The package ships no executable on the path and no manual page (`dpkg -L`:
`/etc/migrationtools/migrate_common.ph` and the scripts under
`/usr/share/migrationtools/` — `migrate_aliases.pl`, `migrate_passwd.pl`,
`migrate_all_nis_offline.sh`, …). Their output is LDIF printed to standard
output (`migrate_passwd.pl` is 47 `print` statements) for a directory server
to import. No documented non-interactive command at the package's own
surface changes a file, the first group's gnupg-agent shape and debian-cd's
in this group. W3.
