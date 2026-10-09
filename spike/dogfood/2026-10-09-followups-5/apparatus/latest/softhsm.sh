# softhsm/SoftHSMv2#908, the report's steps on 2.7.0.
U=/opt/softhsm/bin/softhsm2-util
mkdir -p /work/hsm && cd /work/hsm
export SOFTHSM2_CONF=$PWD/softhsm2.conf
mkdir tokens
printf 'directories.tokendir = %s/tokens\nobjectstore.backend = file\n' "$PWD" > softhsm2.conf
$U --init-token --free --label t --pin 1234 --so-pin 5678 | tail -1
openssl genpkey -algorithm RSA -out k1.pem 2>/dev/null; openssl genpkey -algorithm RSA -out k2.pem 2>/dev/null
$U --import k1.pem --token t --pin 1234 --label k1 --id 01 | tail -1
tok=$(ls -d tokens/*/)
strace -f -qq -P "$PWD/${tok}token.object" -e trace=write -e inject=write:signal=KILL $U --import k2.pem --token t --pin 1234 --label k2 --id 02; echo "exit $?"
ls -l "$tok" | awk '{print $5, $NF}'; $U --show-slots 2>&1 | grep -i -E 'label|initialized|token' | head -6
