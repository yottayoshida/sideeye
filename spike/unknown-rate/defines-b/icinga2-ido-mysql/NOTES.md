# icinga2-ido-mysql — wall W1 (does not install)

Measured while authoring (debian:bookworm-slim, 2026-08-16):
`apt-get install -y --no-install-recommends icinga2-ido-mysql` fails
(rc=100 — unsatisfiable in the pinned container without the icinga2/mysql
stack). W1.
