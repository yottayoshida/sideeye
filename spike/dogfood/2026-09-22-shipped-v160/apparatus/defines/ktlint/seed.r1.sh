set -eu
rm -rf /s/ktlint && mkdir -p /s/ktlint/proj && cd /s/ktlint/proj
printf "fun main(){println(\"x\")}\n" > a.kt
