#!/bin/sh
# Launch the onboarding-clock driver against a box it builds and creates itself
# (PROTOCOL.md). One run per run directory; a second attempt needs a fresh name.
#
#   sh spike/onboarding-clock/run-clock.sh run3      # the next unused name
#
# That is the whole operator procedure now. It used to be three commands, with
# the first two typed by hand — and run 2 was taken against a box a `docker run`
# had failed to replace, because a hand-typed step that fails is outside this
# script's `set -e` (#383). Both steps moved in: the image is built here and the
# container is created by `box.sh`, which refuses to inherit one.
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

# The box name is not the operator's to choose. `box.sh` reads BOX_NAME so a
# test can drive the lifecycle without touching a real run's box, and CI sets
# it — but this script hard-codes `onboarding-box` in the allow-set it hands
# the CLI and in the version read below, and `prompt.md` and the audit's box
# predicate do the same. Inherited from the environment it would send `box.sh`
# to build a different container, write a `box` block certifying that one as
# fresh, and leave the run itself on whatever still holds the real name — with
# the preflight that used to check it now living inside `box.sh`, which is
# looking elsewhere. That is #383 again, wearing this PR's evidence.
unset BOX_NAME
RUN=${1:?usage: run-clock.sh <run name; the next unused one, e.g. run2>}
RESULTS="$SCRIPT_DIR/runs/$RUN"

# This guard stays; the reason it was given on 2026-08-25 does not.
#
# WITHDRAWN: "the declared allowlist did not gate because the launch was
# nested". Probed from a plain terminal on 2026-08-28 — CLAUDECODE unset, four
# pairs — the scope refused nothing there either. `--allowedTools` grants; it
# does not confine. Nesting was never the cause.
#
# WHAT SURVIVES, and why the refusal is still right: in the nested measurement
# the parent session's own auto-mode classifier blocked a LEGITIMATE in-box
# author command. A run whose driver is refused by a permission layer that is
# not part of this protocol measures the parent's configuration, not this
# repository's documentation. That is a corrupt measurement whichever way the
# allowlist behaves.
[ -n "${CLAUDECODE+x}" ] && {
    echo "refusing to launch from inside a Claude session: the parent session's own" >&2
    echo "permission classifier refused a legitimate in-box command when measured" >&2
    echo "(PROTOCOL.md Amendments 2026-08-25), so the run would time the parent's" >&2
    echo "configuration rather than this repository's README." >&2
    echo "Run from a plain terminal." >&2
    exit 1
}

mkdir -p "$RESULTS"

command -v claude >/dev/null || { echo "claude CLI not found" >&2; exit 1; }
# One run per name, keyed on whatever survives a clone. Keying on the
# transcript could not hold: it is gitignored, so on any fresh checkout the
# guard passed for a name whose committed meta.json and timeline.tsv were
# sitting right there, and `mkdir -p` above would have sent the new run into
# that directory to overwrite them.
[ -n "$(ls -A "$RESULTS" 2>/dev/null)" ] && { echo "$RESULTS already holds a run; one run per name" >&2; exit 1; }

# The extractor checks itself before anything burns a box: a predicate
# regression stops the launch, not the adjudication three files later.
python3 "$SCRIPT_DIR/clock-audit.py" --selftest >/dev/null \
    || { echo "clock-audit.py --selftest failed; fix the instrument before running" >&2; exit 1; }

# Canary: safe mode must authenticate before the run burns the box. This sits
# ahead of the build and the box because the launcher now creates them: a
# failed canary used to leave the operator's hand-made box and cost a retry,
# and would now leave one this script refuses to launch over, so the sentence
# above became load-bearing rather than descriptive.
# Canary: safe mode must authenticate before the run burns the box.
canary_out=$(claude --safe-mode -p "Reply with exactly: ok" < /dev/null 2>"$RESULTS/canary-stderr.log") \
    || { echo "canary failed — see $RESULTS/canary-stderr.log" >&2; exit 1; }
case "$canary_out" in
    *ok*) echo "canary: safe mode authenticates" ;;
    *) echo "canary returned unexpected output: $canary_out" >&2; exit 1 ;;
esac

REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)

# The image, from the Dockerfile beside this protocol — which is what
# PROTOCOL.md's "The fresh machine" names, so an image inherited from whatever
# the tag happens to point at is the same defect as an inherited box, one line
# up. A cached rebuild costs under a second and reaches the network for nothing
# (measured). What this fixes is provenance, not content identity: the
# Dockerfile does not pin jrnl or the apt set, deliberately, so two builds of
# the same file are not byte-identical. `dockerfile_sha256` below records the
# file; `target_version` records what came out.
#
# `-q` prints only the image id, and passing that id rather than the tag means
# the container runs the image this line built, not whatever the tag names by
# the time the next line runs. The shape is asserted because `set -u` does not
# fire on an empty capture and a bare `IMAGE=$(...)` that produced nothing would
# reach `docker run` as a missing argument.
IMAGE=$(docker build -q -f "$SCRIPT_DIR/Dockerfile" -t sideeye-onboarding "$REPO_ROOT")
case "$IMAGE" in
    sha256:*) ;;
    *) echo "docker build -q did not return an image id: [$IMAGE]" >&2; exit 1 ;;
esac
DOCKERFILE_SHA=$(shasum -a 256 "$SCRIPT_DIR/Dockerfile" | cut -d' ' -f1)
# The document this criterion measures. `Dockerfile` copies it out of the build
# context — the working tree, at whatever commit and cleanliness it is in — and
# PROTOCOL.md promises the box holds "the repository's front page at the
# measured commit, verbatim". Run 2 established that by comparing sha256 after
# the fact; recording it here is what lets a later reader do the same without
# the box.
README_SHA=$(shasum -a 256 "$REPO_ROOT/README.md" | cut -d' ' -f1)

# The box. `box.sh` refuses when a container of that name already exists — in
# any state — so this run cannot inherit one, and its isolation checks (running,
# network-off) live there now, applied to the container it just made.
BOX=$(sh "$SCRIPT_DIR/box.sh" "$IMAGE")
# Shape-checked for the reason the image id is, and against a worse failure: a
# truncated record is refused by the audit, which runs after the driver has
# already spent the box, so a run that actually happened would write neither
# meta.json nor timeline.tsv.
case "$BOX" in
    container_id=*) ;;
    *) echo "box.sh did not return a container record: [$BOX]" >&2; exit 1 ;;
esac

CLI_VERSION=$(claude --version 2>&1 | head -1)

# The target's installed version, read from the box before the clock starts
# (PROTOCOL.md deviation 2 promised it recorded; the extractor stores the
# first line as meta.target_version). No pipe: a pipe would hand back the
# tail command's exit code and turn a dead box into an empty string.
TARGET_VERSION=$(docker exec onboarding-box jrnl --version 2>&1) \
    || { echo "could not read the target's version from the box" >&2; exit 1; }

PROMPT="$SCRIPT_DIR/prompt.md"
PROMPT_SHA=$(shasum -a 256 "$PROMPT" | cut -d' ' -f1)
# THE ONE DEFINITION of this run's policy. These two strings go to the CLI and,
# unchanged, to the audit — which classifies every call against them rather than
# against a copy. The predecessor kept a second denied list inside clock-audit.py
# and a comment saying to keep the two in step by hand; they had already drifted
# by run 1, and RESULTS.md records that the extractor named fewer tools than the
# launcher denied. A copy cannot drift if there is no copy.
#
# What each flag actually does, measured from a plain terminal on 2026-08-28:
# DISALLOWED removes those tools by name, and works. ALLOWED grants; it does NOT
# confine — a command outside the scope runs, and denying one execution tool only
# moves execution to another. Neither flag is a seal, and the protocol no longer
# says otherwise. The audit is the detector.
ALLOWED="Bash(docker exec onboarding-box *),Read,Edit,Write,Glob,Grep"
DISALLOWED="WebFetch,WebSearch,Task,Agent,Workflow,SendMessage,PushNotification,RemoteTrigger,ScheduleWakeup,CronCreate,CronDelete"

# An empty cwd: the driver has nothing on the host worth reading, and the audit
# still checks it read nothing anyway.
WORKDIR=$(mktemp -d "$HOME/onboarding-clock-XXXXXX")

echo "=== the run: one driver, one box, the transcript records everything ==="
# Stamped here, one line before exec, because the transcript's own start is not
# reliably the session's start: run 1's init event carried NO timestamp, so the
# derived clock silently began at the first assistant turn instead. Both go into
# meta.json and PROTOCOL.md names which one the criterion reads. At 4:22 the
# difference was small; at 9:59 it decides the criterion.
LAUNCH_STARTED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)
agent_rc=0
( cd "$WORKDIR" && claude --safe-mode -p "$(cat "$PROMPT")" \
    --allowedTools "$ALLOWED" \
    --disallowedTools "$DISALLOWED" \
    --output-format stream-json --verbose \
    < /dev/null \
    > "$RESULTS/transcript.jsonl" 2> "$RESULTS/agent-stderr.log" ) || agent_rc=$?
echo "driver exited: $agent_rc"

# The scratch is actually removed. Run 1's `rmdir || true` failed silently
# the moment the driver wrote a file, and left its scratch on the host; the
# contents are already recorded in the transcript's Write events, so nothing
# is lost — but the names are echoed first so the run log says what existed.
leftovers=$(ls -A "$WORKDIR" 2>/dev/null || true)
[ -n "$leftovers" ] && echo "driver scratch held files (recorded above, removed now): $leftovers"
if command -v trash >/dev/null 2>&1; then
    trash "$WORKDIR" || rm -rf -- "$WORKDIR"
else
    rm -rf -- "$WORKDIR"
fi

# The audit exits non-zero when it voids the run or cannot audit it. Its status
# is captured rather than allowed to abort the script, so the reading
# instructions below still print — a voided run is exactly the one whose
# meta.json someone needs to open.
audit_rc=0
python3 "$SCRIPT_DIR/clock-audit.py" \
    --transcript "$RESULTS/transcript.jsonl" \
    --outdir "$RESULTS" \
    --cli-version "$CLI_VERSION" \
    --prompt-sha "$PROMPT_SHA" \
    --agent-rc "$agent_rc" \
    --repo-root "$REPO_ROOT" \
    --target-version "$TARGET_VERSION" \
    --allowed "$ALLOWED" \
    --disallowed "$DISALLOWED" \
    --launch-started-at "$LAUNCH_STARTED_AT" \
    --box "$BOX
dockerfile_sha256=$DOCKERFILE_SHA
readme_sha256=$README_SHA" \
    || audit_rc=$?

echo ""
echo "next: read $RESULTS/meta.json and adjudicate every flagged command against"
echo "      PROTOCOL.md (run 1's precedent: transfer of driver-authored files into"
echo "      the box is inside the seal; anything else voids), pick the qualifying"
echo "      stop candidate, and write RESULTS.md with the derived wall-clock"
exit "$audit_rc"
