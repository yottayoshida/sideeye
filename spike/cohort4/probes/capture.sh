#!/bin/sh
# capture.sh <target> <bare|apparatus>: produce one probe transcript, the
# same way every time. The four transcripts in this directory were made by
# this script and no other command, so a difference between them is a
# difference in the run and not in how it was captured.
#
# What it does, in order: run the frozen probe script inside the frozen
# image (the apparatus mode additionally applies seccomp-enosys.json at the
# container boundary, which is where a seccomp profile has to be applied),
# record the RAW exit status with no pipe in the way, then append
# check-transcript.sh's verdict manifest so the transcript carries proof
# that the required conditions were judged rather than merely not failed.
set -u

[ $# -ge 1 ] || { echo "usage: $0 <himalaya|unison> <bare|apparatus> | $0 control | $0 drills" >&2; exit 2; }
target=$1; mode=${2:-}
repo=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
probes="$repo/spike/cohort4/probes"

repo_probes=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

# The two whole-harness transcripts go through this script too, so every
# committed transcript in this directory was produced by one command.
if [ "$target" = drills ]; then
    out="$repo_probes/drills-under-image.txt"
    {
      echo "# Both cohorts' predicate drills, re-run under the frozen cohort-4"
      echo "# image. PROTOCOL.md's harness-continuity requirement: an image change"
      echo "# is a harness change, so no probe verdict counts before this run."
      echo "# Captured by capture.sh on $(date -u +%Y-%m-%dT%H:%M:%SZ)."
      for d in cohort2 cohort4; do
        echo ""
        echo "\$ docker run --rm -v <repo>:/repo:ro sideeye-cohort4 sh /repo/spike/$d/probes/run-drills.sh"
        docker run --rm -v "$repo":/repo:ro sideeye-cohort4 sh "/repo/spike/$d/probes/run-drills.sh" 2>&1
        echo "raw rc=$?"
      done
    } > "$out"
    echo "captured $out"
    exit 0
fi
if [ "$target" = control ]; then
    out="$repo_probes/positive-control.txt"
    {
      echo "# The positive control, which PROTOCOL.md requires to run first: a"
      echo "# synthetic wall-clock write through the same determinism predicate"
      echo "# as the targets, which must split. A harness that has never flagged"
      echo "# anything proves nothing about the probes it passed."
      echo "# Captured by capture.sh on $(date -u +%Y-%m-%dT%H:%M:%SZ)."
      echo ""
      echo "\$ docker run --rm -v <repo>:/repo:ro sideeye-cohort4 sh /repo/spike/cohort4/probes/run-positive-control.sh"
      docker run --rm -v "$repo":/repo:ro sideeye-cohort4 sh /repo/spike/cohort4/probes/run-positive-control.sh 2>&1
      echo "raw rc=$?"
    } > "$out"
    echo "captured $out"
    exit 0
fi

case "$target" in himalaya|unison) ;; *) echo "unknown target: $target" >&2; exit 2 ;; esac
[ -n "$mode" ] || { echo "usage: $0 <himalaya|unison> <bare|apparatus>" >&2; exit 2; }
case "$mode" in
  bare)      out="$probes/$target-bare.txt"; sec="" ;;
  apparatus) out="$probes/$target.txt"; sec="--security-opt seccomp=$repo/spike/cohort4/seccomp-enosys.json" ;;
  *) echo "unknown mode: $mode" >&2; exit 2 ;;
esac
mkdir -p "$probes/raw"

{
  echo "# $target probe, $mode mode. Captured by spike/cohort4/probes/capture.sh"
  echo "# on $(date -u +%Y-%m-%dT%H:%M:%SZ), inside the frozen cohort-4 image."
  case "$mode" in
    bare)
      echo "# BARE is the falsification the frozen plan requires BEFORE the"
      echo "# apparatus is used: no faketime, no pin-getpid, no seccomp. The"
      echo "# determinism split and the kernel-side copy measured here are what"
      echo "# justify the apparatus. This mode is not a probe verdict." ;;
    apparatus)
      echo "# APPARATUS is the accepted probe run: libfaketime via"
      echo "# /etc/ld.so.preload, pin-getpid.so via LD_PRELOAD on the target"
      echo "# invocations only, the container under seccomp-enosys.json. All"
      echo "# conditions the plan requires are judged here." ;;
  esac
  echo ""
  echo "\$ docker run --rm $sec -v <repo>:/repo -e PROBE_OUT=/repo/spike/cohort4/probes/raw sideeye-cohort4 sh /repo/spike/cohort4/probes/run-$target.sh $mode"
  # shellcheck disable=SC2086
  docker run --rm $sec -v "$repo":/repo \
      -e PROBE_OUT=/repo/spike/cohort4/probes/raw \
      sideeye-cohort4 sh "/repo/spike/cohort4/probes/run-$target.sh" "$mode" 2>&1
  echo "raw rc=$?"
  echo ""
  echo "\$ sh spike/cohort4/probes/check-transcript.sh $target $mode <this file>"
} > "$out"

# The manifest check reads the transcript just written, and its own output
# is appended to the same file. Its raw rc decides this script's rc, so a
# probe whose required conditions were not all judged cannot be captured
# as a success.
sh "$probes/check-transcript.sh" "$target" "$mode" "$out" >> "$out" 2>&1
mrc=$?
echo "manifest rc=$mrc" >> "$out"
echo "captured $out (manifest rc=$mrc)"
exit "$mrc"
