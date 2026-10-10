# 0114 — The MCP container is a Dockerfile to copy, not an image to pull

- **Status:** Accepted (2026-10-10)
- **Refs:** #721 (from the 2026-10-05 whole-product review); ADR 0010 (containment is the
  caller's side), ADR 0022 (the root and the destruction range), ADR 0061 (actions pinned by
  commit), ADR 0080 (the release quickstart is a copied script); `spike/platforms/runner.sh`
  (whose hardened legs measure the page's flags).
- **Scope:** `docs/mcp-container/Dockerfile`, `spike/check-mcp-container.py`,
  `.github/workflows/mcp-container.yml`, the section "Running it in a container" in
  `docs/mcp.md`.

## Context

ADR 0010 leaves containment to whoever runs `sideeye mcp`, and `docs/mcp.md` has long told that
operator to run the server in a container — with a `docker run` line whose image was
`your-image`. #721 named what that leaves out: the confinement the server depends on was each
adopter's to build, and the issue proposed a published image on ghcr, built by `release.yml`,
with strace in it.

Two facts shape the answer. The tool a define runs has to be inside the same container as the
server, because the server executes the config's commands where it runs — so a published image
is a base an operator adds a layer to, never something they run as it is. And a published image
is a distribution surface this project would keep: tags, a visibility setting (a new ghcr
package starts private), retention, and an obligation to everyone who pinned a tag.

## Decision

**The container is a Dockerfile in this repository, which an operator copies, adds their tool
to, and builds.** The owner's ruling, 2026-10-10. Nothing is published.

- **What goes in is the release's own tarball**, fetched with `ADD --checksum` against the digest
  GitHub publishes for the asset — one stage per architecture, `FROM fetch-${TARGETARCH}` picking
  one — and laid out flat under `/opt/sideeye`, binary beside shim. No API call, no curl, no
  rate limit, nothing fetched when the container runs: the pin is in the file, which is
  `install-sideeye.sh`'s own rule ("a script fetched at run time is a pin you do not hold").
- **The base is `debian:bookworm-slim` pinned by its multi-architecture index digest, as
  `spike/platforms/hardened.Dockerfile` pins its own; strace is the base's package, unpinned.**
  Debian moves a stable package only with stable updates, and pinning an apt version would
  break the build on the day the archive drops it. ADR 0061 is about actions; nothing in this
  repository pins apt versions.
- **The version is in one place, `SIDEEYE_VERSION`, beside its two digests.** CI holds the three
  to the release and the version to the quickstart's `SIDEEYE_VERSION`, so the pin moves with the
  quickstart's, in the pull request that follows a release.
- **The server runs as the operator's user: the page's flags gain `--user "$(id -u):$(id -g)"`,
  and nothing else changes.** The README's define keeps its state beside the config, inside the
  mount, so the server has to write the directory the operator made. Before this, the page's
  block ran the server as root with every capability dropped — and on Linux with Docker running
  as root, a root without `CAP_DAC_OVERRIDE` cannot write a directory another user owns, so a
  README-shaped define ended `SETUP_ERROR`. As that user, the server writes the mount, and what
  a target leaves there is the user's: it cannot plant a file the host would run as root. Under
  rootless Docker or Podman the container's root already is the user, and the page says to drop
  the flag there. The platform probe's hardened legs (`spike/platforms/runner.sh`) measure the
  page's line, so they gain the same flag in the same change and stop handing their mount to root.
- **The image is built from a directory of its own (`image/`), and the build and the run are
  joined by `&&`.** A build sends its whole directory as context, and the mount holds whatever a
  target left there; a failed build must not run whatever image was built before.
- **CI runs the page's block as written**, on x86_64 and aarch64 runners, with a toy added at the
  end of the Dockerfile the way the page tells an operator to add theirs: a FAIL on a planted
  bug, a PASS whose `oracle_verified` is true on a correct target, and the flags checked from
  inside the container — a user other than root, no capability in the bounding set, `NoNewPrivs`,
  no route, and `/var/tmp` (world-writable on the base) refusing a write. A verdict does not move
  when a flag is dropped, so without that probe the flags would be text nobody runs; and as a
  user other than root the effective set is empty and `/` unwritable with or without the flags,
  which is why the probe reads the bounding set and `/var/tmp`. The defines are in the README's
  shape, state inside the mount, so the run has to write to `/work` as the page's readers' will.

## Alternatives considered

- **A published image on ghcr, built by `release.yml` (#721's proposal).** Not taken. It saves
  an operator one `FROM` line and the copy, and in exchange the project keeps a registry
  surface for good: a tag policy, the package's visibility, retention, and every pinned tag as
  a promise. The layer with the operator's tool is needed either way.
- **Running `install-sideeye.sh` inside the build.** Not taken. It reads the release through the
  API, which inside `docker build` is unauthenticated and limited to 60 requests an hour
  (`quickstart-release.yml` says why it passes a token), it makes the operator copy two files,
  and its tarball lands in a directory named for the version and architecture, which a fixed
  `PATH` cannot name.
- **Handing the mount to root (`sudo chown -R 0:0 sideeye-work`) and keeping the flags.** Tried in
  this change and dropped. A root that can write the mount can leave a setuid-root file in it —
  setting the bit on a file one owns needs no capability — and with Docker running as root that
  file is setuid-root on the host (measured on 2026-10-10 under an equivalent ownership, the
  host side not measured). Before the chown the mount could not be written at all, so this was
  a hole the fix would have opened.
- **`--init` and a non-root `USER` in the image.** Not taken. Neither was needed for a verdict;
  a `USER` in the image would make the page's `--user` redundant on one engine and wrong on
  another (rootless Docker, where the container's root is the operator).
- **Making the version check required.** Not taken. The workflow is path-filtered, and a
  path-filtered required check blocks every pull request it does not run on; the pin moves in
  a pull request of its own after a release, which waits for this workflow to go green.

## Consequences

- The page describes `main` and the container runs a release. On v1.10.0 the server inside has
  two tools, not the four the page lists, and none of what the CHANGELOG records after v1.10.0.
  The section says the server is the pinned release's and that what came after arrives when the
  pin moves; it does not list the difference, which changes with every release. The CI uses only
  `sideeye_explore_config`.
- Moving the version is three edits. Forgetting a digest fails the build at `ADD --checksum` and
  this repository's CI before it fails an operator.
- Measured on 2026-10-10 while writing this, and recorded so the page's flags carry a reason
  rather than a ritual: without `:exec` the tmpfs is mounted `noexec`, and the server still
  reached both verdicts — it executes nothing from its work directory, so the page now says
  `--tmpfs /tmp` is the required half and `:exec` is for a define that runs what it puts there.
  Without the tmpfs at all the call fails with "the work directory could not be created".
- Found by the first review of this change: with the CI's defines keeping their state under
  `/tmp`, the run never wrote to `/work`, and a README-shaped define on Linux ended
  `SETUP_ERROR` ("the directory /work/. does not exist" — it existed, and could not be
  written). The README-shaped defines came from that, and `--user` from the second review, which
  found the setuid-root hole in the first answer.
- On Docker Desktop (macOS, arm64), the platform probe's hardened CLI leg under `--user` stopped
  at `UNKNOWN unresolvable_path` — "unlinked-fd write fd:1 … last named /work/s/st/a.txt" — where
  the same leg as root reached FAIL; the MCP leg reached FAIL with `oracle_verified` either way.
  Desktop's bind mount is not the hosted runners' file system. On Linux the same legs under
  `--user` (uid 1001) gave what they gave as root: the CLI leg FAIL in the default and syscalls
  modes and a SETUP ERROR naming the cgroup under supervised, the MCP leg FAIL with
  `oracle_verified`, on x86_64 and aarch64 (`spike-platforms` run 38043239184, 2026-10-10, on
  this ADR's merge commit). That run is a look, not a count: the platform table's hardened row
  is counted by the probe's own rule for the `--user` leg, which was written before its run.
- The Dockerfile's first line, `# syntax=docker/dockerfile:1`, has BuildKit fetch its Dockerfile
  frontend from Docker Hub rather than use the engine's own, because `ADD --checksum` on an
  https source is newer than some engines' frontend. It is a moving reference, like the strace
  package.
- Not measured by the workflow: Docker Desktop, rootless Docker, Podman, and a replay. The page's
  block was run as written on Docker Desktop (macOS, arm64) while writing this, and reached both
  verdicts.
