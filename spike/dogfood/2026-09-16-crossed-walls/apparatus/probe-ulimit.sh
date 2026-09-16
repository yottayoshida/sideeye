#!/bin/sh
# Without Sideeye: the three truncating rewrites reproduced with a file-size limit, so a reader
# can see the empty file with nothing installed. A write past the limit raises SIGXFSZ, whose
# default action ends the process — after the truncating open, before any byte lands. dash's
# `ulimit -f` counts 512-byte blocks. Where other writes of the operation come first, the input
# file is made larger than any of them and the limit set between the two.
set -u
X=/localrun/probe
mkdir -p $X
export HOME=$X/home BUN_INSTALL_CACHE_DIR=$X/bun-cache TMPDIR=$X/tmp
mkdir -p "$HOME" "$BUN_INSTALL_CACHE_DIR" "$TMPDIR"

echo "== markdownlint-cli $(markdownlint --version), ulimit -f 0"
mkdir -p $X/ml && printf '# Title\nSome text   \n* item one\n+ item two\n\n\n## Section\ntext\n' > $X/ml/README.md
echo "  before: $(wc -c < $X/ml/README.md) bytes"
( ulimit -f 0; markdownlint --fix $X/ml/README.md ); echo "  rc=$?  after: $(wc -c < $X/ml/README.md) bytes"

echo "== google-java-format 1.36.1, ulimit -f 0 (-XX:-UsePerfData: no hsperfdata file)"
mkdir -p $X/gjf && cat > $X/gjf/A.java <<'EOJ'
package probe;
import java.util.List;
public class A {
  public static int   sum(List<Integer> xs){int s=0;for(int x:xs){s+=x;}return s;}
    public static void main(String[] args){System.out.println(sum(List.of(1,2,3)));}
}
EOJ
echo "  before: $(wc -c < $X/gjf/A.java) bytes"
( ulimit -f 0; java -XX:-UsePerfData --add-exports=jdk.compiler/com.sun.tools.javac.api=ALL-UNNAMED --add-exports=jdk.compiler/com.sun.tools.javac.code=ALL-UNNAMED --add-exports=jdk.compiler/com.sun.tools.javac.file=ALL-UNNAMED --add-exports=jdk.compiler/com.sun.tools.javac.parser=ALL-UNNAMED --add-exports=jdk.compiler/com.sun.tools.javac.tree=ALL-UNNAMED --add-exports=jdk.compiler/com.sun.tools.javac.util=ALL-UNNAMED -jar /opt/gjf/gjf.jar --replace $X/gjf/A.java ) 2>&1 | tail -2 | sed 's/^/  | /'
echo "  after: $(wc -c < $X/gjf/A.java) bytes"

echo "== bun $(bun --version) add, package.json larger than every other file the operation writes"
B=$X/bunpkg; mkdir -p $B/package
printf '{ "name": "probe-dep", "version": "1.0.0", "main": "index.js" }\n' > $B/package/package.json
printf 'module.exports = "probe-dep";\n' > $B/package/index.js
tar -czf $X/dep-1.0.0.tgz -C $B package
for lim in 1 2 4 8; do
  P=$X/bun$lim; mkdir -p $P
  python3 -c "import json; print(json.dumps({'name':'probe-proj','version':'1.0.0','description':'x'*6000}, indent=2))" > $P/package.json
  before=$(wc -c < $P/package.json)
  ( ulimit -f $lim; cd $P && bun add $X/dep-1.0.0.tgz ) > $X/bun$lim.out 2>&1; rc=$?
  echo "  ulimit -f $lim ($((lim*512)) bytes): rc=$rc  package.json $before -> $(wc -c < $P/package.json) bytes; bun.lock $( [ -f $P/bun.lock ] && wc -c < $P/bun.lock || echo absent); node_modules/probe-dep $( [ -d $P/node_modules/probe-dep ] && echo present || echo absent)"
done
