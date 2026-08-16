#!/bin/sh
# A-group launcher for the dogfood recipes (#84 sweep). The recipes are the
# committed defines for timewarrior and todoman and already run both judge
# legs (a: L0 only, b: + checker) in one invocation, writing
# $RUN/{a,b}/report.json. This wrapper only points RUN into the artifact
# dir; the sweep registers two trials per invocation, one per leg.
#
# Usage: dogfood.sh <timew|todoman> <artifact-dir>
set -u
tool=${1:?tool}; art=${2:?artifact dir}
case "$tool" in
  timew|todoman) : ;;
  *) echo "dogfood.sh: unknown recipe: $tool" >&2; exit 3 ;;
esac
mkdir -p "$art" || exit 3
RUN="$art/run" sh /work/spike/dogfood-"$tool".sh > "$art/transcript.txt" 2>&1
rc=$?
echo "dogfood/$tool exit=$rc (per-leg verdicts live in the reports)"
exit $rc
