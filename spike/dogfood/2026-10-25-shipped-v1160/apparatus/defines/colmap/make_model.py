"""A small sparse reconstruction in COLMAP's text format: one pinhole camera, three images a step
apart, twelve points seen by all three. Eight project exactly; four have observations moved 30 px,
the outliers `point_filtering` exists to remove.   python3 make_model.py <dir>"""
import os, sys
d = sys.argv[1]; os.makedirs(d, exist_ok=True)
f, cx, cy = 500.0, 320.0, 240.0
imgs = [(i + 1, -0.5 * i) for i in range(3)]                  # image id, tx (camera at x = 0.5 i)
pts = [(p + 1, -1.0 + 0.6 * (p % 4), -0.6 + 0.6 * (p // 4), 5.0 + 0.3 * p) for p in range(12)]
bad = {3, 6, 9, 12}
obs = {i: [] for i, _ in imgs}; tracks = {p: [] for p, *_ in pts}
for pid, X, Y, Z in pts:
    for iid, tx in imgs:
        u = f * (X + tx) / Z + cx + (30.0 if pid in bad and iid == 2 else 0.0)
        v = f * Y / Z + cy
        tracks[pid].append((iid, len(obs[iid]))); obs[iid].append((u, v, pid))
open(f"{d}/cameras.txt", "w").write(f"1 SIMPLE_PINHOLE 640 480 {f} {cx} {cy}\n")
with open(f"{d}/images.txt", "w") as o:
    for iid, tx in imgs:
        o.write(f"{iid} 1 0 0 0 {tx} 0 0 1 img{iid}.jpg\n" + " ".join(f"{u:.6f} {v:.6f} {p}" for u, v, p in obs[iid]) + "\n")
with open(f"{d}/points3D.txt", "w") as o:
    for pid, X, Y, Z in pts:
        o.write(f"{pid} {X} {Y} {Z} 128 128 128 0.5 " + " ".join(f"{i} {k}" for i, k in tracks[pid]) + "\n")
