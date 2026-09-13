#!/bin/sh
# #556 same-class on a real runtime: node (libuv installs its SIGCHLD handler with a full
# sa_mask and writes to a pipe inside it). Engine at /se.
set -u
SE=/se/sideeye
SHIM=/se/libsideeye_shim.so
echo "engine: $("$SE" --version 2>&1 | head -1)   shim sha256: $(sha256sum "$SHIM" | cut -d' ' -f1)"
echo "node: $(node --version)   libc: $(ldd --version 2>&1 | head -1)"
cat > /tmp/n.js <<'JS'
const cp = require('child_process'), fs = require('fs');
const out = process.argv[2];
try { cp.execFileSync('/bin/true'); console.error('execFileSync /bin/true -> ok'); }
catch (e) { console.error('execFileSync /bin/true -> threw', e.code || e.signal || e.message); }
cp.execFile('/bin/true', (err) => {
  console.error('execFile async /bin/true ->', err ? ('error ' + (err.code || err.signal)) : 'ok');
  fs.writeFileSync(out, 'x\n');
});
JS
cat > /tmp/nsig.js <<'JS'
// control: a signal handler through libuv with no child process at all
const fs = require('fs'); const out = process.argv[2];
process.on('SIGUSR2', () => { console.error('SIGUSR2 handler ran'); fs.writeFileSync(out, 'x\n'); });
process.kill(process.pid, 'SIGUSR2');
setTimeout(() => {}, 200);
JS
for js in n nsig; do
  mkdir -p /s/$js/plain
  echo "==================== $js / plain ===================="
  node /tmp/$js.js /s/$js/plain/o.txt; echo "rc=$?"
  for m in wrappers syscalls; do
    mkdir -p /s/$js/$m /wk/$js/$m
    echo "==================== $js / preflight --observe $m ===================="
    "$SE" preflight --state /s/$js/$m --operation "node /tmp/$js.js /s/$js/$m/o.txt" \
      --shim "$SHIM" --oracle /usr/bin/strace --observe $m --work /wk/$js/$m > /tmp/pf.txt 2>&1
    echo "preflight rc=$?"
    grep -E " -> |handler ran|^(UNKNOWN|PREFLIGHT)|^ +(the |recording)" /tmp/pf.txt | head -8
  done
done
