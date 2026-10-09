#!/usr/bin/env python3
"""F1: value shapes through encrypt, decrypt and set, both versions. No crash, no Sideeye.

For each shape file, `dotenvx get -f <file>` (every key, as JSON) is read before anything is done
to it. Then encrypt, read again; decrypt, read again; each must equal the first read. Separately,
on a fresh encrypted file, `set KEY <value>` for every value the first read returned, and `get KEY`
must return that value. Differences are printed key by key.

    docker run --rm --network none -v <apparatus>:/ap:ro sideeye-dx1010 python3 -I /ap/lab-9.py
"""
import json, os, subprocess, shutil

LONG = "x" * 5000
SHAPES = [
    ("PLAIN", "hello"),
    ("SPACES", "  padded  "),
    ("SQ", "'single $HOME #notcomment'"),
    ("DQ_ESC", '"double \\n escape"'),
    ("BQ", "`backtick`"),
    ("HASH_COMMENT", "value # comment"),
    ("HASH_NOSPACE", "value#nocomment"),
    ("DOLLAR", "$HOME"),
    ("DOLLAR_BRACE", "${HOME}/x"),
    ("DOLLAR_DEFAULT", "${UNSET_VAR:-fallback}"),
    ("DOLLAR_ESCAPED", "\\$HOME"),
    ("SQ_DOLLAR", "'$HOME'"),
    ("BACKSLASH", "C:\\path\\to"),
    ("MULTI_DQ", '"line1\nline2"'),
    ("MULTI_SQ", "'line1\nline2'"),
    ("EQUALS", "a=b=c"),
    ("EMPTY", ""),
    ("UNICODE", "日本語🔑"),
    ("JSONV", '{"a":1,"b":[2,3]}'),
    ("DQ_INNER_SQ", "\"it's\""),
    ("SQ_INNER_DQ", "'say \"hi\"'"),
    ("TRAILING_SPACE_DQ", '"x "'),
    ("LONG", LONG),
    ("PEM", '"-----BEGIN KEY-----\nMIIBOgIBAAJBAKj34GkxFhD90vcNLYLInFEX6Ppy1tPf9Cnzj4p4WGeKLs1Pt8Qu\n-----END KEY-----"'),
    ("CMD_SUBST", "$(echo substituted)"),
]

def body(eol="\n", trailing=True, extra=""):
    lines = [f"{k}={v}" for k, v in SHAPES]
    lines.insert(3, "export EXPORTED=yes")
    lines.insert(5, "DUP=first")
    lines.append("DUP=second")
    lines.append("# a comment line")
    s = eol.join(l.replace("\n", eol) for l in lines) + extra
    return s + (eol if trailing else "")

VARIANTS = {"lf": body(), "crlf": body("\r\n"), "no-trailing-newline": body(trailing=False)}

def run(v, args, cwd):
    env = dict(os.environ, PATH=f"/opt/dx-{v}/bin:/usr/local/bin:/usr/bin:/bin", HOME="/s/lab9/home",
               UV_THREADPOOL_SIZE="1", npm_config_update_notifier="false")
    return subprocess.run(["dotenvx", *args], cwd=cwd, env=env, capture_output=True, text=True)

def getall(v, f, cwd):
    r = run(v, ["get", "-f", f], cwd)
    try:
        return json.loads(r.stdout)
    except Exception:
        return {"<unparsed>": (r.stdout + r.stderr)[:200]}

def diff(a, b):
    out = []
    for k in sorted(set(a) | set(b)):
        if a.get(k) != b.get(k):
            out.append(f"{k}: {a.get(k)!r:.80} -> {b.get(k)!r:.80}")
    return out

os.makedirs("/s/lab9/home", exist_ok=True)
for v in ("2.32.4", "2.34.2"):
    for name, text in VARIANTS.items():
        d = f"/s/lab9/{v}-{name}"
        shutil.rmtree(d, ignore_errors=True); os.makedirs(d)
        open(f"{d}/.env", "w", newline="").write(text)
        before = getall(v, ".env", d)
        e = run(v, ["encrypt", "-f", ".env"], d)
        enc = getall(v, ".env", d)
        dc = run(v, ["decrypt", "-f", ".env"], d)
        dec = getall(v, ".env", d)
        print(f"## {v} {name}: {len(before)} keys read before; encrypt exit {e.returncode}, decrypt exit {dc.returncode}")
        for label, got in (("after encrypt", enc), ("after decrypt", dec)):
            for line in diff(before, got) or ["(same)"]:
                print(f"   {label}: {line}")
        same_text = open(f"{d}/.env", newline="").read() == text
        print(f"   decrypted file byte-identical to the original: {same_text}")
    # set every value the first read returned, on a fresh encrypted file
    d = f"/s/lab9/{v}-set"
    shutil.rmtree(d, ignore_errors=True); os.makedirs(d)
    open(f"{d}/.env", "w").write("SEED=x\n")
    run(v, ["encrypt", "-f", ".env"], d)
    want = getall(v, ".env", f"/s/lab9/{v}-lf")
    bad = []
    for k, val in want.items():
        if k in ("SEED", "DOTENV_PUBLIC_KEY"):
            continue
        r = run(v, ["set", k, val, "-f", ".env"], d)
        g = run(v, ["get", k, "-f", ".env"], d)
        if g.stdout.rstrip("\n") != val:
            bad.append(f"{k}: set {val!r:.60} (exit {r.returncode}) -> get {g.stdout.rstrip(chr(10))!r:.60}")
    print(f"## {v} set then get, {len(want)} values: " + ("all equal" if not bad else f"{len(bad)} differ"))
    for b in bad:
        print("   " + b)
