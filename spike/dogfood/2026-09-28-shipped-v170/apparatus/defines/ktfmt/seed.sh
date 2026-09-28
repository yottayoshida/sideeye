set -eu
rm -rf /s/ktfmt && mkdir -p /s/ktfmt/proj && cd /s/ktfmt/proj
printf 'fun f(x:Int):Int{return x+1}\nfun main(){println(f(1))}\n' > a.kt
