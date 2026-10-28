#!/bin/sh
# After a crash the model loads with COLMAP itself (model_converter to text), keeps its camera and
# three images, and its files agree with each other: every 2D point an image says belongs to a 3D
# point is in that point's track, and every track entry points back.
out=/tmp/colmap-check; rm -rf "$out"; mkdir -p "$out"
if ! /opt/bin/colmap model_converter --input_path "$SIDEEYE_STATE_DIR/sparse/0" --output_path "$out" --output_type TXT > "$out.log" 2>&1; then
    echo "checker(colmap): the model does not load: $(grep -m1 -i -E 'error|check failed|failed' "$out.log")"; exit 1
fi
exec python3 - "$out" <<'PY'
import sys
d = sys.argv[1]
rows = lambda n: [l.split() for l in open(f"{d}/{n}") if l.strip() and not l.startswith("#")]
cams = rows("cameras.txt"); ims = rows("images.txt"); pts = rows("points3D.txt")
img2d = {}
for head, p2 in zip(ims[0::2], ims[1::2]):
    iid = int(head[0]); img2d[iid] = [int(p2[k + 2]) for k in range(0, len(p2), 3)]
bad = []
track = {int(r[0]): [(int(r[k]), int(r[k + 1])) for k in range(8, len(r), 2)] for r in pts}
for pid, t in track.items():
    for iid, k in t:
        if iid not in img2d or k >= len(img2d[iid]) or img2d[iid][k] != pid: bad.append(f"point {pid} lists image {iid} #{k}, which does not point back")
for iid, ids in img2d.items():
    for k, pid in enumerate(ids):
        if pid != -1 and (pid not in track or (iid, k) not in track[pid]): bad.append(f"image {iid} #{k} names point {pid}, which does not list it")
print(f"checker(colmap): {len(cams)} camera(s), {len(img2d)} image(s), {len(track)} point(s); " + ("consistent" if not bad else f"{len(bad)} broken reference(s), first: {bad[0]}"))
sys.exit(0 if len(cams) == 1 and len(img2d) == 3 and not bad else 1)
PY
