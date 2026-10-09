set -eu
rm -rf /s/esp /s/esp-in && mkdir -p /s/esp /s/esp-in
espsecure generate-signing-key --version 2 --scheme ecdsa256 /s/esp/k.pem > /s/esp-in/seed.log 2>&1
python3 -c "import sys; sys.stdout.buffer.write(bytes((i*7+3)%256 for i in range(65536)))" > /s/esp/fw.bin
test "$(wc -c < /s/esp/fw.bin)" = 65536
cp /s/esp/fw.bin /s/esp-in/fw.orig
