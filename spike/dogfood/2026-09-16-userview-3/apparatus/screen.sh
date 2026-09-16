#!/bin/sh
# ラウンド1 スクリーニング: 動的リンクか / 実際の書き込み操作でスレッドを作るか。
# --version では出ないスレッドがあるので（beets がそうだった）、必ず実操作で測る。
set -u
cat /tmp/apt-summary.txt
mkdir -p /work/d && cd /work/d

printf 'This sentence has a mistake: recieve.\nAnother one: seperate.\n' > /work/d/a.txt
printf 'And here: teh cat.\n' > /work/d/b.txt
printf 'x = 1\nputs( x )\n' > /work/d/a.rb
head -c 200000 /dev/urandom > /work/d/f.bin
printf 'alpha old beta\n' > /work/d/v.txt
mkdir -p /work/d/zhome/target
echo "--- 素材 ---"; ls -la /work/d

check() {  # check <名前> <バイナリ> <実操作コマンド...>
  name=$1; bin=$2; shift 2
  path=$(command -v "$bin" 2>/dev/null)
  if [ -z "$path" ]; then printf "%-12s 見つからない\n" "$name"; return 0; fi
  kind=$(file -L "$path" | cut -d: -f2- | cut -c1-46)
  if file -L "$path" | grep -q "statically linked"; then link=static
  elif file -L "$path" | grep -qi "ELF"; then link=dynamic
  else link=script; fi
  strace -f -e trace=clone,clone3 -o /tmp/tr-$name.txt "$@" > /tmp/op-$name.txt 2>&1
  rc=$?
  th=$(grep -c CLONE_THREAD /tmp/tr-$name.txt 2>/dev/null | head -1)
  ch=$(grep -c clone /tmp/tr-$name.txt 2>/dev/null | head -1)
  printf "%-12s %-8s thread=%-4s clone=%-4s rc=%-3s %s\n" "$name" "$link" "$th" "$ch" "$rc" "$kind"
  if [ "$rc" -ne 0 ]; then
    echo "    失敗: $(head -3 /tmp/op-$name.txt | tr '\n' ' ' | cut -c1-160)"
  fi
  return 0
}

echo
echo "=== 候補スクリーニング（実操作で測る）==="
check codespell codespell codespell -w /work/d/a.txt /work/d/b.txt
check vim       vim       vim -es -u NONE -c '%s/old/new/g' -c 'wq' /work/d/v.txt
check zstd      zstd      zstd -q --rm /work/d/f.bin
check rubocop   rubocop   rubocop -a --force-default-config --only Layout/SpaceInsideParens /work/d/a.rb
check zoxide    zoxide    env HOME=/work/d/zhome _ZO_DATA_DIR=/work/d/zhome zoxide add /work/d/zhome/target

echo
echo "--- 書き込み後 ---"; ls -la /work/d
