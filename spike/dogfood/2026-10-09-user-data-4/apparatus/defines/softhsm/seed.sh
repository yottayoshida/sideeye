set -eu
# A SoftHSM token store on the file backend with one initialized token and one imported key;
# the operation imports a second key, which rewrites token.object (lab 8: O_RDWR|O_CREAT, then
# ftruncate to 0, then the write; a .lock beside each object).
rm -rf /s/hsm && mkdir -p /s/hsm/tokens /s/hsm-in
printf 'directories.tokendir = /s/hsm/tokens\nobjectstore.backend = file\nlog.level = ERROR\n' > /s/hsm/softhsm2.conf
export SOFTHSM2_CONF=/s/hsm/softhsm2.conf
softhsm2-util --init-token --free --label t --pin 1234 --so-pin 5678 > /s/hsm-seed.log 2>&1
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out /s/hsm/k1.pem >> /s/hsm-seed.log 2>&1
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out /s/hsm/k2.pem >> /s/hsm-seed.log 2>&1
softhsm2-util --import /s/hsm/k1.pem --token t --pin 1234 --label k1 --id 01 >> /s/hsm-seed.log 2>&1
[ "$(find /s/hsm/tokens -name '*.object' | wc -l)" -ge 2 ]
