set -eu
rm -rf /s/jsb && mkdir -p /s/jsb/proj && cd /s/jsb/proj
printf "function f(a){if(a){return a+1}return 0}\n" > a.js
