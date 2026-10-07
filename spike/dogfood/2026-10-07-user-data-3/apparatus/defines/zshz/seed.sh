set -eu
rm -rf /s/z /s/z-in && mkdir -p /s/z/data /s/z-in/dirs/d1 /s/z-in/dirs/d2 /s/z-in/dirs/d3
printf 'ZSHZ_DATA=/s/z/data/.z\nsource /opt/zsh-z/zsh-z.plugin.zsh\nzshz --add /s/z-in/dirs/d1\nzshz --add /s/z-in/dirs/d2\nzshz --add /s/z-in/dirs/d1\n' > /s/z-in/seed.zsh
printf 'ZSHZ_DATA=/s/z/data/.z\nsource /opt/zsh-z/zsh-z.plugin.zsh\nzshz --add /s/z-in/dirs/d3\n' > /s/z-in/op.zsh
zsh /s/z-in/seed.zsh
test -s /s/z/data/.z
