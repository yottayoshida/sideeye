# Sourced, not executed. One definition of each enumerated set on the five frozen
# surfaces, shared by surface-drift.sh (which reports movement) and
# check-freeze-audit.sh (which gates it).
#
# WHY IT IS ITS OWN FILE. The two scripts had a copy each — six extractions,
# identical logic, different function names, nothing pinning them together. That is
# the hand-synced-pair shape #65 tracks, and here it would fail in the worst
# available way: the gate and the drift report would disagree about what a surface
# IS, and each would be internally consistent while doing it. A /simplify pass found
# it before the copies had a chance to drift.
#
# Each extraction reads the file's content on STDIN rather than resolving a revision
# itself, because the two callers obtain content differently — one from `<rev>:<path>`
# and one from a pinned blob sha — and the definition of a set has nothing to do with
# where the bytes came from.
#
# WHAT THESE DEFINITIONS ARE, AND ARE NOT. Each answers "which names are in this
# set", nothing more. Behavioural clauses — which call site returns which exit code,
# a field's meaning or presence rule, the MCP input schemas, the isError rule, the
# split-on-spaces rule — are NOT here and are not measured by anything that uses
# this file. They are rung 3 in ADR 0028's ladder and the page says so. The proof
# that this distinction is load-bearing rather than cautious is in the window these
# scripts audit: #273 moved the exit-code surface while `ExitCode` stayed
# byte-identical.
#
# Two definitions carry a scar worth keeping:
#   - config_keys is the operand of each key comparison in the parser, NOT "quoted
#     lowercase strings". The earlier definition counted fifteen tokens in a file
#     whose accepted key set is six, and that figure reached a plan before anyone
#     asked what it was a count of.
#   - exit_codes is name=value pairs, so a renumbering shows up and not only a
#     rename.

# extract_surface_set <set-name>   — content on stdin, sorted unique names on stdout
extract_surface_set() {
    case "$1" in
      config_keys)
          grep -oE 'mem\.eql\(u8, key, "[a-z_]+"\)' | grep -oE '"[a-z_]+"' | tr -d '"' ;;
      unknown_reason)
          awk '/pub const UnknownReason = enum/,/^};/' | grep -oE '^ +[a-z_]+,$' | tr -d ' ,' ;;
      exit_codes)
          awk '/pub const ExitCode = enum/,/^};/' | grep -oE '^ +[a-z_]+ = [0-9]+' | tr -s ' ' ;;
      contract_version)
          grep -oE 'pub const contract_version: u32 = [0-9]+' ;;
      mcp_tools)
          grep -oE 'sideeye_[a-z_]+' ;;
      schema_fields)
          grep -oE '^\| `[a-z_]+`' | grep -oE '`[a-z_]+`' | tr -d '`' ;;
      *)
          echo "extract_surface_set: unknown set $1" >&2
          return 1 ;;
    esac | LC_ALL=C sort -u
}

# The file each set is defined by. A surface whose files are all byte-identical
# across a window did not move at all — enumerated names AND behavioural clauses —
# which is why surface 1 needs BOTH src/config.zig and src/main.zig: the accepted
# keys and the parse are in the first, and splitArgs and resolvePathAgainst are in
# the second. Claiming surface 1 settled on src/config.zig alone was a real
# overclaim caught in review.
surface_set_path() {
    case "$1" in
      config_keys)      echo src/config.zig ;;
      unknown_reason)   echo src/contract.zig ;;
      exit_codes)       echo src/contract.zig ;;
      contract_version) echo src/contract.zig ;;
      mcp_tools)        echo src/mcp.zig ;;
      schema_fields)    echo docs/report-schema.md ;;
      *) echo "surface_set_path: unknown set $1" >&2; return 1 ;;
    esac
}

# Every set name, in report order.
surface_set_names() {
    printf '%s\n' config_keys unknown_reason schema_fields exit_codes contract_version mcp_tools
}
