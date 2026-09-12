# 0061 — Every action is pinned by commit, and the release checksum is GitHub's

Status: Accepted (2026-09-12)

## Context

Two questions arrived together in an outside review of this repository, and they
look like one question about supply chain until you measure them.

**The first is real.** Four workflows ran twenty-four action references between
them. Three of those — the ones in `spike-fsusage.yml` — named a commit SHA. The
other twenty-one named a tag: `actions/checkout@v4`, `mlugg/setup-zig@v2`. A tag is
a pointer its owner can move, and whatever it points at runs with this repository's
checkout in front of it and, in `release.yml`, in front of the token that uploads
the tarballs people download. (Twenty-five after this change rather than twenty-four:
the job that runs the check carries a checkout of its own. A count taken before a
change and read after it counts what the change added — a first-read review caught
this paragraph asserting 25 = 3 + 21.)

The judgment was already here. `spike-fsusage.yml` carried a comment beside its
three: *"Pinned by commit: these actions run before a script that runs as root."*
That reasoning was made about one file, so it stayed in one file, and the leg that
builds the release — the one whose output leaves this machine — was not the one it
covered.

**The second dissolves on measurement.** The review asked for a SHA256 manifest
beside each release, on the grounds that a downloader has no way to check what
they got. They do. GitHub computes a sha256 for every release asset at upload and
publishes it through the API and on the Releases page:

```
$ gh api repos/yottayoshida/sideeye/releases/tags/v1.3.0 --jq '.assets[].digest'
sha256:ef94464f5d96f2e23b65ab8a55abe7cc34bafe1c2a5295cba303a23bfc92db8e
sha256:eb27ac75e7afd99351acb07dedb47249f51d8c0552e005992c2f77fd949b4f1f
sha256:c2014f30be34154ba0f0074102b4fa2c8045ce3678aea842507b8703d1779c95
```

This project has used it twice, both recorded: the v1.3.0 release ceremony
(`BUILDLOG.md`, "each asset's sha256 was computed from the downloaded bytes and
matched the release's own digest") and the 2026-09-11 dogfood run, which
established that it was measuring the released tarball rather than a local build
"because its sha256 matched the digest the release publishes".

What was missing was never the mechanism. It was the sentence telling a reader the
mechanism is there.

## Decision

**1. Every action reference in every workflow names `<owner>/<repo>[/<path>]@<40 hex>`,
with the tag it was taken from as a trailing comment** (`# v4`). Twenty-one
references move; three were already there. Both halves are checked — the shape and
the comment — because the first draft of this ADR stated the comment requirement
while `spike/check-action-pins.sh` looked only at the SHA, and a reference with no
comment passed (measured, first-read review). `<owner>/<repo>` rather than "ends in
forty hex" for the same reason: `docker://x@<40 hex>` and `./.github/actions/x@<40 hex>`
both satisfied the looser rule and neither is a pinned action.

**2. Verifying a downloaded release is documented, not re-implemented.**
`docs/cli.md` says how to read the digest GitHub already publishes and what
comparing it does and does not establish. No `SHA256SUMS`, no signature, no
attestation.

## Alternatives Considered

**A `SHA256SUMS` file published beside the tarballs.** Rejected. It would sit in
the same release, signed by nothing, so its trust root is the same GitHub account
as the digest it duplicates — in a world where the release is tampered with, both
move together. What it would genuinely add is convenience: one `sha256sum -c` over
three files instead of reading three digests out of an API. The cost of that
convenience is a job that runs on every release, a round-trip check to keep the
job honest (publish, download, compare — a checksum generated and verified in the
same directory from the same bytes passes by construction), and the `contents:
write` permission that check would need at pull-request time to be exercised
before a tag exists. Owner ruling, 2026-09-12: not worth it. The absence is a
choice, and this paragraph is where it is recorded.

**Signature or provenance attestation.** Rejected for now, and it is the only one
of the three that answers a question the digest cannot: *who built this*. If
distribution integrity is revisited, this is the shape to revisit — not
`SHA256SUMS`, which moves the same trust root to a second file. Deliberately not
deferred with a date attached; it needs a reason to exist, and "the release
workflow could emit one" is not one.

**Leaving the tags alone.** Rejected. The counter-argument to pinning is that it
freezes the code — a compromised action stays compromised rather than being fixed
under you by the next tag move — and that is a real cost, stated here rather than
argued away. It is the smaller cost: a tag moves without anyone here looking,
which is the property the `spike-fsusage.yml` comment already refused to accept
for its own leg.

## Consequences

- Action updates become manual. Nothing tracks upstream releases now; a SHA is
  changed when someone decides to change it. If that becomes the binding problem,
  the answer is a Dependabot configuration that rewrites the SHAs — at which point
  `check-action-pins.sh` is the second place one judgment lives and should go.
- Anyone adding a workflow must look a SHA up. The check names the file, the line
  and the command that resolves a tag, because the failure will arrive months from
  now to someone who did not read this page.
- `spike-fsusage.yml` no longer explains its own pinning; it points at the rule.
  Its three references were the precedent and are now just three of twenty-five.
- A local action (`uses: ./.github/actions/x`) would go red. None exists. When one
  is wanted, the check refuses it and the decision gets made in the open rather
  than by an exemption written in advance for a case nobody has met.
