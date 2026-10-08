#!/bin/sh
# #690, inside sideeye-f690: the four targets whose result moved between runs of one define,
# each run again a fixed number of times with its work directory kept, and every trace
# decoded with `trace-ops --records` beside it so tally.py can name where two runs part.
#
# Mounted: /se — the branch tree, built `zig build -Dtarget=aarch64-linux-gnu -Dtrace-ops`;
#          /ap — this directory (the checkers); /out — where everything is written.
# usage:   sh run.sh tombi|mogrify|isort|dotter
#
# The counts are fixed here, before any result is read (rule: the range is decided before
# the result). tombi's are weighted to replays, where the 2026-10-02 run met the refusal
# 3 times in 20 against 1 in 36 explores.
set -u
SE=/se/zig-out/bin/sideeye
SHIM=/se/zig-out/lib/libsideeye_shim.so
TO=/se/zig-out/bin/trace-ops
O=/out
mkdir -p "$O"
{ "$SE" version; cat /versions.txt; } > "$O/engine.txt"

decode() { # <work dir>: every trace in it decoded beside it, one `<seq> <pid> <tid> <op> <path>` line per record
    for t in "$1"/trace-*.bin; do
        [ -f "$t" ] && "$TO" --records "$t" > "$t.txt" 2> "$t.err"
    done
    return 0
}

line() { # <label> <txt> <json>: one summary line per run
    v=$(python3 -c 'import json,sys
try:
    d=json.load(open(sys.argv[1])); print(d.get("verdict"), d.get("unknown_reason") or "-")
except Exception: print("none -")' "$3")
    cp=$(grep -o -E 'crash points [0-9]+' "$2" | head -1 | grep -o -E '[0-9]+')
    echo "$1 | $v | crash_points=${cp:--} | $(sed -n '1p' "$2" | cut -c1-90)"
}

tombi() {
    d=$O/tombi; mkdir -p "$d"
    seed() { rm -rf /s/tombi && mkdir -p /s/tombi/proj && printf '[a]\nb=1\nc   =  "x"\n[d]\ne=[1,2,   3]\n' > /s/tombi/proj/a.toml; }
    for i in $(seq 1 20); do
        seed
        "$SE" explore --state /s/tombi/proj --operation "/opt/bin/tombi format --offline a.toml" \
            --cwd /s/tombi/proj --oracle /usr/bin/strace --observe supervised \
            --work "$d/ex$i" --json "$d/ex$i.json" > "$d/ex$i.txt" 2>&1
        decode "$d/ex$i"; line "tombi explore $i" "$d/ex$i.txt" "$d/ex$i.json"
    done
    case_json=$(ls "$d"/ex*/cases/*.json 2>/dev/null | head -1)
    [ -n "$case_json" ] || { echo "tombi: no FAIL case among the explores; no replays"; return; }
    echo "tombi: replaying $case_json"
    for i in $(seq 1 40); do
        seed
        "$SE" replay "$case_json" --oracle /usr/bin/strace --observe supervised \
            --work "$d/rp$i" --json "$d/rp$i.json" > "$d/rp$i.txt" 2>&1
        decode "$d/rp$i"; line "tombi replay $i" "$d/rp$i.txt" "$d/rp$i.json"
    done
}

mogrify() {
    d=$O/mogrify; mkdir -p "$d"
    # The PNGs are made by --setup, as in spike/followup-527: the inputs' times are part of
    # what mogrify writes (date:create, date:modify), so where they are made matters.
    seed() { rm -rf /s/mog && mkdir -p /s/mog; } # an empty state, as followup-527's go() left it
    op="/usr/bin/mogrify -resize 50% /s/mog/img1.png /s/mog/img2.png /s/mog/img3.png"
    for i in $(seq 1 20); do
        seed
        "$SE" explore --state /s/mog --setup /ap/setup-img.sh --operation "$op" --check /ap/check-img.sh --shim "$SHIM" \
            --oracle /usr/bin/strace --observe wrappers --work "$d/ex$i" --json "$d/ex$i.json" > "$d/ex$i.txt" 2>&1
        decode "$d/ex$i"; line "mogrify explore $i" "$d/ex$i.txt" "$d/ex$i.json"
    done
    for i in $(seq 1 10); do
        seed
        "$SE" preflight --twice --state /s/mog --setup /ap/setup-img.sh --operation "$op" --shim "$SHIM" \
            --oracle /usr/bin/strace --observe wrappers --work "$d/tw$i" > "$d/tw$i.txt" 2>&1
        echo "mogrify twice $i exit $? | $(sed -n '1p' "$d/tw$i.txt" | cut -c1-80)"
    done
}

mogrify_nodate() {
    # The control for mogrify: the same define with ImageMagick told to leave out the PNG
    # chunks that carry a date or a time (tIME and the date: text chunks). If the baseline
    # refusals are the clock the target writes, they go away here and nothing else changes.
    d=$O/mogrify; mkdir -p "$d"
    seed() { rm -rf /s/mog && mkdir -p /s/mog; } # an empty state, as followup-527's go() left it
    op="/usr/bin/mogrify -define png:exclude-chunks=date,time -resize 50% /s/mog/img1.png /s/mog/img2.png /s/mog/img3.png"
    for i in $(seq 1 10); do
        seed
        "$SE" explore --state /s/mog --setup /ap/setup-img.sh --operation "$op" --check /ap/check-img.sh --shim "$SHIM" \
            --oracle /usr/bin/strace --observe wrappers --work "$d/nd$i" --json "$d/nd$i.json" > "$d/nd$i.txt" 2>&1
        decode "$d/nd$i"; line "mogrify nodate $i" "$d/nd$i.txt" "$d/nd$i.json"
    done
}

isort() {
    d=$O/isort; mkdir -p "$d"
    seed() { rm -rf "$1" && mkdir -p "$1"; } # empty; the files are written by --setup, as both recorded defines did
    # A: 2026-09-06's define (state /work/st3/is); B: followup-527's (state /localrun/st/wrappers/isort).
    # Both ran from /work with no --cwd and seeded through --setup, as here.
    for which in A B; do
        case $which in A) st=/work/st3/is ;; B) st=/localrun/st/wrappers/isort ;; esac
        for i in $(seq 1 10); do
            seed "$st"
            ( cd /work && "$SE" explore --state "$st" --setup /ap/setup-isort.sh --operation "/usr/bin/isort $st/a.py $st/b.py" \
                --check /ap/check-isort.sh --shim "$SHIM" --oracle /usr/bin/strace --work "$d/$which$i" --json "$d/$which$i.json" ) > "$d/$which$i.txt" 2>&1
            decode "$d/$which$i"; line "isort $which $i" "$d/$which$i.txt" "$d/$which$i.json"
        done
    done
}

dotter() {
    d=$O/dotter; mkdir -p "$d"
    # A: 2026-10-03's define — the state is /s/dotter, dotter's own directory (/s/dotter-in,
    #    where it keeps .dotter and its cache) is outside it and is not restored between worlds.
    # B: the control — both under one state, so whatever dotter keeps beside its config is
    #    restored with everything else.
    seedA() {
        rm -rf /s/dotter /s/dotter-in && mkdir -p /s/dotter/home /s/dotter-in/.dotter
        printf '[default.files]\nbashrc = { target = "/s/dotter/home/.bashrc", type = "template" }\ngitconfig = { target = "/s/dotter/home/.gitconfig", type = "template" }\n' > /s/dotter-in/.dotter/global.toml
        printf 'packages = ["default"]\n' > /s/dotter-in/.dotter/local.toml
        printf 'export EDITOR=vim\n' > /s/dotter-in/bashrc
        printf '[user]\n\tname = me\n' > /s/dotter-in/gitconfig
        printf '# hand edited\nexport PATH=$HOME/bin:$PATH\n' > /s/dotter/home/.bashrc
        printf '[user]\n\tname = old\n' > /s/dotter/home/.gitconfig
    }
    seedB() {
        rm -rf /s/dotb && mkdir -p /s/dotb/home /s/dotb/in/.dotter
        printf '[default.files]\nbashrc = { target = "/s/dotb/home/.bashrc", type = "template" }\ngitconfig = { target = "/s/dotb/home/.gitconfig", type = "template" }\n' > /s/dotb/in/.dotter/global.toml
        printf 'packages = ["default"]\n' > /s/dotb/in/.dotter/local.toml
        printf 'export EDITOR=vim\n' > /s/dotb/in/bashrc
        printf '[user]\n\tname = me\n' > /s/dotb/in/gitconfig
        printf '# hand edited\nexport PATH=$HOME/bin:$PATH\n' > /s/dotb/home/.bashrc
        printf '[user]\n\tname = old\n' > /s/dotb/home/.gitconfig
    }
    for i in $(seq 1 10); do
        seedA
        "$SE" explore --state /s/dotter --operation "/opt/bin/dotter deploy -f -y" --cwd /s/dotter-in \
            --oracle /usr/bin/strace --observe supervised --work "$d/A$i" --json "$d/A$i.json" > "$d/A$i.txt" 2>&1
        ls -la /s/dotter-in/.dotter > "$d/A$i.dotter-in.txt" 2>&1
        decode "$d/A$i"; line "dotter A $i" "$d/A$i.txt" "$d/A$i.json"
    done
    for i in $(seq 1 10); do
        seedB
        "$SE" explore --state /s/dotb --operation "/opt/bin/dotter deploy -f -y" --cwd /s/dotb/in \
            --oracle /usr/bin/strace --observe supervised --work "$d/B$i" --json "$d/B$i.json" > "$d/B$i.txt" 2>&1
        decode "$d/B$i"; line "dotter B $i" "$d/B$i.txt" "$d/B$i.json"
    done
}

for t in "$@"; do "$t" 2>&1 | tee "$O/$t.summary.txt"; done
