#!/bin/sh
# Cohort-2 hg define (P1) setup: a repository with one pinned changeset of
# two files and one modified working file — the probe's pre-state shape
# (probes/hg.txt), rebuilt fresh for the engine.
set -eu
mkdir -p /tmp/cohort2/hg /tmp/cohort2/hg/pylib
# The pinned config is GENERATED here rather than committed as a loose
# file: the provenance verifier holds setup/check/toml/launcher to byte
# identity (D2) but knows nothing about extra files, so the config's bytes
# live inside a file the verifier does hold. revbranchcache.mmap=no is the
# measured off switch for the commit-path thread (probes/hg.txt).
cat > /tmp/cohort2/hg/hgrc <<'EOF'
[ui]
username = probe <probe@example.invalid>

[storage]
revbranchcache.mmap = no
EOF
export HGRCPATH=/tmp/cohort2/hg/hgrc
# CPython's shutil fast-copies through sendfile, a syscall outside the
# engine's frozen contract — the r2 explore refused with
# unsupported_syscall_observed (hg-r2/explore-r2-transcript.txt). CPython
# 3.13 offers no environment switch, so this sitecustomize (reached via
# PYTHONPATH from the launcher) flips shutil to its read/write fallback:
# identical bytes on disk through supported syscalls. DECLARED APPARATUS,
# owner-approved 2026-08-21: the measured hg does not run a stock copy
# path, and any finding must reproduce against stock hg (strace fault
# injection, the method of the four standing upstream filings) before it
# is claimed or reported.
cat > /tmp/cohort2/hg/pylib/sitecustomize.py <<'EOF'
import shutil
shutil._USE_CP_SENDFILE = False
EOF
R=/tmp/cohort2/hg/repo
rm -rf "$R"
hg init "$R"
printf 'alpha, fixed bytes\n' > "$R/alpha"
printf 'beta, fixed bytes\n'  > "$R/beta"
touch -t 202601010000 "$R/alpha" "$R/beta"
hg -R "$R" add "$R/alpha" "$R/beta"
# --user explicitly: hg prefers an ambient $HGUSER over the hgrc, and both
# setup and the operation inherit the engine's environment.
hg -R "$R" commit -m initial -d "2026-01-01 00:00:00 +0000" --user "probe <probe@example.invalid>"
printf 'alpha, modified fixed bytes\n' > "$R/alpha"
touch -t 202601020000 "$R/alpha"
# The engine's restore flattens file modes (documented since #121), and hg
# caches the filesystem's exec-bit answer AS a mode — an executable
# .hg/wcache/checkisexec. A restored world therefore re-runs the exec
# probe the recording skipped, shifting every later operation index; the
# r3 explore's baseline check caught exactly that (its trace ran past the
# recording's count and the standing kill landed). With no wcache in the
# pre-state, the recording and every world run the same probe from the
# same blank slate — measured: a mode-flattened copy of this pre-state
# produces a syscall-name sequence identical to a mode-preserving copy
# (167 calls, diff clean). The probe's temp names still differ per run;
# classes gate, paths only warn, by the engine's own design.
rm -rf "$R/.hg/wcache"
