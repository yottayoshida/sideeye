# apt-utils — define (explored): apt-ftparchive generate

Debian description: "package management related utility programs";
`implemented-in::c++`, `use::organizing`, `works-with::software:package`.
Installed 3.0.3 in the trixie image. Freshness: no tracked file outside the
selection names it (`b2-author.sh`, 2026-09-18).

Three programs; the representative one is `apt-ftparchive` — man
apt-ftparchive: "the command line tool that generates the index files that
APT uses to access a distribution source"; the `packages` command "emit[s]
a package record to stdout", while `generate config_file` is "an elaborate
means to 'script' the generation process for a complete archive … When doing
a full generate it automatically performs file-change checks and builds the
desired compressed output files". The `generate` form writes the index files
itself, so the operation is one static command line (`op.txt`): generate the
`Packages`, `Packages.gz`, `Contents-arm64` and `Contents-arm64.gz` of a
one-package archive under the state directory. `setup.sh` seeds the archive:
a minimal `.deb` built with `dpkg-deb` (part of dpkg, present in every
Debian image) from a five-line control file, in `pool/`, and the
configuration naming the state directory as `ArchiveDir`.

Measured while authoring (container, 3.0.3): the `.deb`'s tar carries file
modification times, so `setup.sh` pins them (`SOURCE_DATE_EPOCH` and `touch`
to 2000-01-01) before building, or each run's `Packages` would carry a
different checksum. With that, two `generate` runs over the same pool left
byte-identical index files (the `.gz` included), exit 0.

**Authoring run (2026-09-18, v1.5.0 in the trixie image):** `preflight --twice`
accepted — 16 state-changing operations observed, "two runs 2002 ms apart
left equal state under --state". No explore was run before the sweep.
