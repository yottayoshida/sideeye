#!/bin/sh
# slate 2 の残り枠。3 軸（linkage / threads / write が stdio か raw か）で測る。
set -u
mkdir -p /work/s3 && cd /work/s3

# bsdtar: アーカイブに追記する（in-place 更新）
mkdir -p /work/s3/tarsrc
printf 'one\n' > /work/s3/tarsrc/f1.txt
printf 'two\n' > /work/s3/tarsrc/f2.txt
bsdtar -cf /work/s3/a.tar -C /work/s3/tarsrc f1.txt 2>/dev/null
printf 'three\n' > /work/s3/tarsrc/f3.txt

# bundler: Gemfile.lock を作る／更新する
mkdir -p /work/s3/rb
cat > /work/s3/rb/Gemfile <<'EOG'
source "https://rubygems.org"
EOG

# git-annex: git repo を用意する
mkdir -p /work/s3/ga
git -C /work/s3/ga init -q 2>/dev/null
git -C /work/s3/ga config user.email probe@example.com
git -C /work/s3/ga config user.name probe
printf 'payload\n' > /work/s3/ga/data.bin

echo "--- 素材 ---"
ls -la /work/s3 /work/s3/ga

check() {
  name=$1; bin=$2; shift 2
  path=$(command -v "$bin" 2>/dev/null)
  if [ -z "$path" ]; then printf "%-12s 見つからない\n" "$name"; return 0; fi
  if file -L "$path" | grep -q "statically linked"; then link=static
  elif file -L "$path" | grep -qi "ELF"; then link=dynamic
  else link=script; fi

  strace -f -e trace=clone,clone3,execve -o /tmp/c.txt "$@" > /tmp/o.txt 2>&1
  rc=$?
  th=$(grep -c CLONE_THREAD /tmp/c.txt 2>/dev/null | head -1)
  ex=$(grep -c execve /tmp/c.txt 2>/dev/null | head -1)

  strace -f -e trace=write -o /tmp/w.txt "$@" > /dev/null 2>&1
  w4096=$(grep -c ", 4096)" /tmp/w.txt 2>/dev/null | head -1)
  wall=$(grep -c "write(" /tmp/w.txt 2>/dev/null | head -1)

  printf "%-12s %-8s thread=%-3s execve=%-3s rc=%-3s write計=%-4s うち4096=%s\n" \
    "$name" "$link" "$th" "$ex" "$rc" "$wall" "$w4096"
  if [ "$rc" -ne 0 ]; then
    echo "    失敗: $(head -3 /tmp/o.txt | tr '\n' ' ' | cut -c1-170)"
  fi
  return 0
}

echo
echo "=== slate 2 の screen（残り枠）==="
check bsdtar   bsdtar    bsdtar -uf /work/s3/a.tar -C /work/s3/tarsrc f3.txt
check bundler  bundle    sh -c "cd /work/s3/rb && bundle lock"
check gitannex git-annex sh -c "cd /work/s3/ga && git annex init probe && git annex add data.bin"

echo
echo "--- 書き込み後 ---"
ls -la /work/s3 /work/s3/rb 2>/dev/null
bsdtar -tf /work/s3/a.tar 2>/dev/null
