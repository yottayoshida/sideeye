#!/bin/sh
# The scale benchmark's grid (#621, ADR 0081). Runs the cells `PROTOCOL.md` defines, one
# `run-cell.py` process each, appending a TSV row per cell.
#
#   sh run-grid.sh <engine> <toy-scale> <out.tsv> [oracle]
#
# **One cell is one process**, because `ru_maxrss` for waited-for children is a high-water mark
# that never decreases: a second engine in the same process would report the larger of the two
# as this cell's, and `run-cell.py` refuses to start where that could happen.
#
# **Resumable by construction**: a cell whose identity is already in the output is skipped, so
# an interrupted grid is restarted with the same command and only the missing cells run. The
# identity is the tuple the row carries, not a sequence number — reordering the loops below
# does not re-run what is already measured.
#
# This is an apparatus, not a check. It is not wired into CI, for the reason
# `.github/workflows/spike-fsusage.yml` gives about itself: a measurement is run deliberately.
set -eu

engine=${1:?usage: run-grid.sh <engine> <toy-scale> <out.tsv> [oracle]}
toy=${2:?usage: run-grid.sh <engine> <toy-scale> <out.tsv> [oracle]}
out=${3:?usage: run-grid.sh <engine> <toy-scale> <out.tsv> [oracle]}
oracle=${4:-/usr/bin/strace}
here=$(cd "$(dirname "$0")" && pwd)
header_file=$(mktemp "${TMPDIR:-/tmp}/se621-header-XXXXXX")

[ -x "$engine" ] || { echo "no engine at $engine" >&2; exit 2; }
[ -x "$toy" ] || { echo "no toy at $toy" >&2; exit 2; }
[ -x "$oracle" ] || { echo "no oracle at $oracle — the grid measures under a strict oracle" >&2; exit 2; }

# Proven able to go red before it is trusted to say green.
python3 "$here/run-cell.py" --selftest

# Column positions are read from `run-cell.py --header`, never written down here. The two files
# would otherwise agree only by hand: review measured that swapping two entries in COLUMNS left
# the selftest green while this function silently began reading different columns — skipping
# measured cells or re-running finished ones with nothing going red.
col() {
    awk -F'\t' -v want="$1" 'NR==1 { for (i = 1; i <= NF; i++) if ($i == want) { print i; exit } }' "$header_file"
}
python3 "$here/run-cell.py" --header > "$header_file"
C_CP=$(col crash_points_requested)
C_SF=$(col state_files)
C_MD=$(col mode)
C_CK=$(col checker)
C_RP=$(col rep)
C_NOTE=$(col note)
for v in "$C_CP" "$C_SF" "$C_MD" "$C_CK" "$C_RP" "$C_NOTE"; do
    [ -n "$v" ] || { echo "run-grid: run-cell.py --header is missing a column this grid indexes" >&2; exit 2; }
done

# **A `not-counted` row does not count as measured.** Skipping one would let a whole leg that
# refused — the checker leg did, for a checker the engine would not accept — come back on a
# re-run as "already done", and the grid would report itself complete with no figures in it.
# Such a row is left in the file as the record of what happened and the cell is run again.
already() {
    [ -f "$out" ] || return 1
    awk -F'\t' -v cp="$1" -v sf="$2" -v md="$3" -v ck="$4" -v rp="$5" \
        -v ccp="$C_CP" -v csf="$C_SF" -v cmd="$C_MD" -v cck="$C_CK" -v crp="$C_RP" -v cn="$C_NOTE" \
        '$ccp==cp && $csf==sf && $cmd==md && $cck==ck && $crp==rp && $cn !~ /not-counted/ { found=1 }
         END { exit found?0:1 }' "$out"
}

for rep in 1 2 3; do
    for state in "0:1024" "200:102400"; do
        files=${state%%:*}
        bytes=${state##*:}
        for mode in wrappers syscalls; do
            for checker in none cheap; do
                for cp in 10 50 100 250 500 1000; do
                    if already "$cp" "$files" "$mode" "$checker" "$rep"; then
                        echo "skip cp=$cp files=$files mode=$mode checker=$checker rep=$rep"
                        continue
                    fi
                    echo "cell cp=$cp files=$files mode=$mode checker=$checker rep=$rep"
                    python3 "$here/run-cell.py" \
                        --engine "$engine" --toy "$toy" \
                        --crash-points "$cp" --state-files "$files" --state-bytes "$bytes" \
                        --mode "$mode" --checker "$checker" --cheap-checker "$here/check-kept.sh" \
                        --oracle "$oracle" --rep "$rep" --out "$out" >/dev/null
                done
            done
        done
    done
done

# The sampling pass. #621 asks for the work directory's MAXIMUM as well as its final size, and
# the maximum has to be watched while the run is going. It is a pass of its own because the
# walk is heavy enough to disturb the wall clock it would otherwise sit beside — a sampling row
# carries no time, and the timed rows above carry no maximum. One repetition: the figure is a
# lower bound whatever the count, and three of them would not make it an upper one.
for state in "0:1024" "200:102400"; do
    files=${state%%:*}
    bytes=${state##*:}
    for cp in 10 100 1000; do
        if already "$cp" "$files" wrappers none 4; then
            echo "skip sample cp=$cp files=$files"
            continue
        fi
        echo "sample cp=$cp files=$files"
        python3 "$here/run-cell.py" \
            --engine "$engine" --toy "$toy" \
            --crash-points "$cp" --state-files "$files" --state-bytes "$bytes" \
            --mode wrappers --checker none --oracle "$oracle" --rep 4 \
            --sample-work-dir --out "$out" >/dev/null
    done
done

rm -f "$header_file"
echo "--- grid complete: $(awk 'END {print NR-1}' "$out") row(s) in $out ---"
awk -F'\t' -v cn="$C_NOTE" 'NR>1 && $cn ~ /not-counted/ { n++ } END { printf "not-counted rows: %d\n", n+0 }' "$out"
