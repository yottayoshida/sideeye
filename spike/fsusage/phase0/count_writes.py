#!/usr/bin/env python3
"""capture の中から「state ファイルの fd に対する write」だけを数える。

fs_usage の write 行はパス名を持たない（`write F=3 B=0x1`）ので、
先に同じスレッドでその fd を開いた open 行を見つけ、その F=n に絞る。
これをやらないと shim 自身のトレース書き込み（F=900）と stderr（F=2）を
一緒に数えてしまう（spike/fsusage/RESULTS.md「What the observer's shadow
looks like」）。

行文法は spike/fsusage/classify.py の LINE_RE と同じ。実 capture から
書かれたもので、こちらで作り直さない。
"""
import re
import sys

LINE_RE = re.compile(
    r"^(?P<ts>\d{2}:\d{2}:\d{2}\.\d+)\s+"
    r"(?P<call>\S+)\s+"
    r"(?P<middle>.*?)\s*"
    r"(?P<dur>\d+\.\d{6})\s+"
    r"(?P<wflag>W\s+)?"
    r"(?P<proc>.+)\.(?P<tid>\d+)\s*$")
FD_RE = re.compile(r"\bF=(\d+)\b")
TRUNC_RE = re.compile(r">{2,}$")


def main():
    cap_path, state_file = sys.argv[1], sys.argv[2]
    # 表示は左から切られるので、末尾側で照合する（RESULTS.md の実測）
    tail = state_file[-60:]

    fds = {}          # (tid, fd) -> True  … state ファイルを指す fd
    writes = 0
    unparsed = 0
    total = 0

    with open(cap_path, "r", errors="replace") as fh:
        for raw in fh:
            line = raw.rstrip("\n")
            if not line.strip():
                continue
            total += 1
            m = LINE_RE.match(line)
            if not m:
                unparsed += 1
                continue
            call = m.group("call")
            middle = m.group("middle")
            tid = m.group("tid")

            if call.startswith("open"):
                stump = TRUNC_RE.sub("", middle)
                if tail in stump or stump.endswith(state_file.split("/")[-1]):
                    fdm = FD_RE.search(middle)
                    if fdm:
                        fds[(tid, fdm.group(1))] = True
            elif call.startswith("write"):
                fdm = FD_RE.search(middle)
                if fdm and (tid, fdm.group(1)) in fds:
                    writes += 1

    # 走査量を stderr に出す。0 件を「一致」と読ませないため
    print(f"[count_writes] lines={total} unparsed={unparsed} "
          f"state_fds={len(fds)} writes={writes}", file=sys.stderr)
    print(writes)


if __name__ == "__main__":
    main()
