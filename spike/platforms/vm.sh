#!/bin/sh
# spike/platforms/vm.sh — a distribution booted on its own, older kernel, beside the same
# userland on the runner's kernel (#697, ADR 0105; spike/platforms/RUNS-RULE-2026-10-10b.md).
#
#   SIDEEYE_VERSION=v1.10.0 sh spike/platforms/vm.sh <image> <out dir>
#   <image>: debian13 (6.12) | rocky10 (6.12) | debian12 (6.1) | ubuntu2204 (5.15) | ubuntu2004 (5.4)
#            | rocky9 (5.14) | rocky8 (4.18)
#
# Two legs, both as root, both on this runner's CPU:
#   <image>-container  the distribution's container image, --privileged with its own cgroup
#                      namespace, on the runner's kernel — the control: same userland, the
#                      runner's kernel
#   <image>-vm         the distribution's cloud image booted under QEMU (KVM when /dev/kvm can be
#                      used, TCG otherwise; vm.txt says which), its own kernel. cloud-init mounts a
#                      vfat disk labelled PROBEDATA holding the engine, measure.sh and vm-inner.sh,
#                      runs vm-inner.sh as root, and powers off; the record is copied back from that
#                      disk. A run whose disk holds no `done` mark is the apparatus's fault
#                      (RUNS-RULE-2026-10-10b.md), whatever the console shows.
# Images are fetched from dated paths and checked against the digests their sum files published.
set -u

usage="usage: SIDEEYE_VERSION=<tag> vm.sh <image> <out dir>"
name=${1:?$usage}
out=${2:?$usage}
V=${SIDEEYE_VERSION:?set SIDEEYE_VERSION to the release tag to measure}
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
mkdir -p "$out"
out=$(cd "$out" && pwd)
arch=$(uname -m)
t=${RUNNER_TEMP:-/tmp}/vm-$name
mkdir -p "$t"

deb13=https://cloud.debian.org/images/cloud/trixie/20261001-2618
deb=https://cloud.debian.org/images/cloud/bookworm/20261006-2623
jam=https://cloud-images.ubuntu.com/releases/jammy/release-20261004
foc=https://cloud-images.ubuntu.com/releases/focal/release-20250624
case "$arch:$name" in
x86_64:debian13)  url=$deb13/debian-13-genericcloud-amd64-20261001-2618.qcow2
                  sum=sha512:f46f0671a6e5bdec5291ab8972bae2f10e5408c2f64a74078f11efc2f06a436a9d0313ed50e0472542eeabf780e9f7c792ac0a314c6c20507fcd9fd81b468c3d ;;
aarch64:debian13) url=$deb13/debian-13-genericcloud-arm64-20261001-2618.qcow2
                  sum=sha512:d8470b8c6c38fead046c794b5800a5a7b96672d5bcf543cc230ceb0c4b8ace05ed341a0c8928045422243fde26b2f1f2f58e99244c65709ffda2e3d4b674dd5a ;;
x86_64:rocky10)  url=https://dl.rockylinux.org/pub/rocky/10.2/images/x86_64/Rocky-10-GenericCloud-Base-10.2-20260525.0.x86_64.qcow2
                 sum=sha256:9fc9e9ff16888bb68ac39b0392e25c9c92684d50c85f1cce6ab549363bbc4b48 ;;
aarch64:rocky10) url=https://dl.rockylinux.org/pub/rocky/10.2/images/aarch64/Rocky-10-GenericCloud-Base-10.2-20260525.0.aarch64.qcow2
                 sum=sha256:457c8375e19496f43a25c4a6169fa11237536c53cef6f85a20ea3c5a751aa0f5 ;;
x86_64:debian12)  url=$deb/debian-12-genericcloud-amd64-20261006-2623.qcow2
                  sum=sha512:a09170d17e13af43da61774666f520e3bbec0f8bd96b4db37c15f3426fb327ccad950b80dbe78c09aa5ca90ce5015e99334b0ba5188fd4018736bc3fb5f0882c ;;
aarch64:debian12) url=$deb/debian-12-genericcloud-arm64-20261006-2623.qcow2
                  sum=sha512:835b929522716de9798d1c0fbe61caae8313ab78858b278f3389a2db922ae42e4619b4a776ecad39583c149fb85334a2f8cdae685bc56987160e5c86a2354375 ;;
x86_64:ubuntu2204)  url=$jam/ubuntu-22.04-server-cloudimg-amd64.img
                    sum=sha256:012d81fade7e8ff4428fc35dfeee711d66d1f47d5ea9c5c8ced96a85b959835c ;;
aarch64:ubuntu2204) url=$jam/ubuntu-22.04-server-cloudimg-arm64.img
                    sum=sha256:86e13258765945ad792dac75fac7f02f4db9fa73a4a535ffa472266e7041fa19 ;;
x86_64:ubuntu2004)  url=$foc/ubuntu-20.04-server-cloudimg-amd64.img
                    sum=sha256:18f2977d77dfea1b74aee14533bd21c34f789139e949c57023b7364894b7e5e9 ;;
aarch64:ubuntu2004) url=$foc/ubuntu-20.04-server-cloudimg-arm64.img
                    sum=sha256:d4603cd783e2578f838c63f7c3a8dae6b554bd6358870f2c8eb182aa51ade465 ;;
x86_64:rocky9)  url=https://dl.rockylinux.org/pub/rocky/9.8/images/x86_64/Rocky-9-GenericCloud-Base-9.8-20260525.0.x86_64.qcow2
                sum=sha256:92c206cc6f790c61583247eefe87890f8828420662c17cacf247cec78ab4eec8 ;;
aarch64:rocky9) url=https://dl.rockylinux.org/pub/rocky/9.8/images/aarch64/Rocky-9-GenericCloud-Base-9.8-20260525.0.aarch64.qcow2
                sum=sha256:24692a444f1f0b8bb95375c38c8b43f8099a115347623691be2c330b40c8a1fe ;;
x86_64:rocky8)  url=https://dl.rockylinux.org/pub/rocky/8.10/images/x86_64/Rocky-8-GenericCloud-Base-8.10-20240528.0.x86_64.qcow2
                sum=sha256:e56066c58606191e96184de9a9183a3af33c59bcbd8740d8b10ca054a7a89c14 ;;
aarch64:rocky8) url=https://dl.rockylinux.org/pub/rocky/8.10/images/aarch64/Rocky-8-GenericCloud-Base-8.10-20240528.0.aarch64.qcow2
                sum=sha256:946b5b9845aa5e3ed98f1bc6ee9873201712a2aef01b87731aed16857e0ca13f ;;
*) echo "vm: no image $name for $arch"; exit 2 ;;
esac
case $name in
debian13)   ctl=debian:13@sha256:913f6706df59a68922d1dd08f78c2476560a8d367897200a6005b00e5f67c2d5 ;;
rocky10)    ctl=rockylinux/rockylinux:10.2@sha256:827d37bc128288ccf160ee318bb3cb92d591164cb217e92f8bc61e3982ae1834 ;;
debian12)   ctl=debian:12@sha256:2c037a04925515fdd6ea85ea14a682d0e79931f5e9f5d07b6dbfc6ba12f9e858 ;;
ubuntu2204) ctl=ubuntu:22.04@sha256:5ec03bb3441e8b0bf3b4f9cd4629a1ae763010dc3035bb8da3ae6cf026486401 ;;
ubuntu2004) ctl=ubuntu:20.04@sha256:8feb4d8ca5354def3d8fce243717141ce31e2c428701f6682bd2fafe15388214 ;;
rocky9)     ctl=rockylinux/rockylinux:9.8@sha256:8101994123cf3d0a8fee517bee7f39e555c7d92bd2d9eb3303cc988a0eeed00f ;;
rocky8)     ctl=rockylinux/rockylinux:8.10@sha256:e8a49c5403b687db05d4d67333fa45808fbe74f36e683cec7abb1f7d0f2338c6 ;;
esac

bin=$(sh "$root/docs/ci-quickstart/release/install-sideeye.sh" "$V" "$t/sideeye" 2> "$out/install.txt") || {
    echo "vm: the engine could not be installed"; cat "$out/install.txt"; exit 1
}
se_dir=$(dirname "$bin")

# The control first: it needs nothing but docker, so a VM that fails to boot still leaves it.
echo "== $name-container"
docker run --rm --privileged --cgroupns=private -v "$root":/ap:ro -v "$se_dir":/se:ro -v "$out":/out "$ctl" sh -c "
    if command -v apt-get > /dev/null; then
        { apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq strace; } > /out/$name-container-pkg.txt 2>&1
        dpkg-query -W libc6 strace coreutils >> /out/$name-container-pkg.txt 2>&1
        dpkg -S \"\$(readlink -f \$(command -v dd))\" >> /out/$name-container-pkg.txt 2>&1
    else
        dnf -q -y install strace > /out/$name-container-pkg.txt 2>&1
        rpm -q glibc strace >> /out/$name-container-pkg.txt 2>&1
        rpm -qf \"\$(readlink -f \$(command -v dd))\" >> /out/$name-container-pkg.txt 2>&1
    fi
    mkdir -p /s
    sh /ap/spike/platforms/measure.sh /se/sideeye /out $name-container"

echo "== $name-vm"
{
    echo "arch: $arch"; echo "image: $url"; echo "digest: $sum"
    { sudo apt-get update -qq
      case $arch in
      x86_64) sudo apt-get install -y -qq qemu-system-x86 qemu-utils cloud-image-utils mtools dosfstools ;;
      aarch64) sudo apt-get install -y -qq qemu-system-arm qemu-efi-aarch64 qemu-utils cloud-image-utils mtools dosfstools ;;
      esac; } > "$out/vm-apt.txt" 2>&1
    echo "packages: exit $?"
    if [ -e /dev/kvm ]; then sudo chmod 666 /dev/kvm; fi
    if [ -w /dev/kvm ]; then accel=kvm; cpu=host; limit=1800; else accel=tcg; cpu=max; limit=5400; fi
    echo "accel: $accel (/dev/kvm: $(ls -l /dev/kvm 2>&1))"
} > "$out/vm.txt"
accel=$(sed -n 's/^accel: \([a-z]*\).*/\1/p' "$out/vm.txt")
cpu=host; limit=1800; explore=600; [ "$accel" = tcg ] && { cpu=max; limit=5400; explore=1800; }
fail() { echo "vm: $* — an apparatus fault" | tee -a "$out/vm.txt"; exit 1; }

curl -fsSL -o "$t/base" "$url" || { echo "vm: could not fetch $url" | tee -a "$out/vm.txt"; exit 1; }
algo=${sum%%:*}; want=${sum#*:}
got=$(${algo}sum "$t/base" | cut -d' ' -f1)
[ "$got" = "$want" ] || { echo "vm: digest mismatch for $url: $got" | tee -a "$out/vm.txt"; exit 1; }
cp "$t/base" "$t/disk" && qemu-img resize -q "$t/disk" +6G || fail "could not prepare the disk"

pay=$t/payload; rm -rf "$pay"; mkdir -p "$pay/platforms" "$pay/out"
cp -r "$se_dir" "$pay/se" && cp -r "$here/measure.sh" "$here/define" "$pay/platforms/" || fail "could not stage the payload"
cat > "$pay/vm-inner.sh" <<INNER
#!/bin/sh
# Run as root by cloud-init inside the VM; the data disk is mounted at /mnt/probe.
p=/mnt/probe; o=\$p/out
echo "vm-inner: start" > /dev/console
cp -r \$p/se /opt/se && cp -r \$p/platforms /opt/platforms && chmod 755 /opt/se/sideeye
cat /proc/cmdline > \$o/cmdline.txt
if command -v apt-get > /dev/null; then
    # The first boot's apt-daily can hold apt's and dpkg's locks: stop it, then wait on the lock.
    systemctl stop apt-daily.service apt-daily-upgrade.service unattended-upgrades.service > /dev/null 2>&1
    { apt-get -o DPkg::Lock::Timeout=900 update -qq && DEBIAN_FRONTEND=noninteractive apt-get -o DPkg::Lock::Timeout=900 install -y -qq strace; } > \$o/pkg.txt 2>&1
    echo "vm-inner: packages exit \$?" > /dev/console
    dpkg-query -W libc6 strace coreutils >> \$o/pkg.txt 2>&1
    dpkg -S "\$(readlink -f \$(command -v dd))" >> \$o/pkg.txt 2>&1
else
    dnf -q -y install strace > \$o/pkg.txt 2>&1
    echo "vm-inner: packages exit \$?" > /dev/console
    rpm -q glibc strace >> \$o/pkg.txt 2>&1
    rpm -qf "\$(readlink -f \$(command -v dd))" >> \$o/pkg.txt 2>&1
fi
mkdir -p /s
EXPLORE_TIMEOUT=$explore sh /opt/platforms/measure.sh /opt/se/sideeye \$o $name-vm > /dev/null
echo "vm-inner: measure exit \$?" > /dev/console
echo done > \$o/done
echo "vm-inner: done" > /dev/console
INNER
truncate -s 512M "$t/data.img" && mkfs.vfat -n PROBEDATA "$t/data.img" > /dev/null || fail "could not make the data disk"
mcopy -s -i "$t/data.img" "$pay"/* ::/ || fail "could not copy the payload onto the data disk"
printf '#cloud-config\nruncmd:\n  - [sh, -c, "mkdir -p /mnt/probe && mount -L PROBEDATA /mnt/probe && sh /mnt/probe/vm-inner.sh > /mnt/probe/out/inner.log 2>&1; sync; umount /mnt/probe; poweroff"]\n' > "$t/user-data"
printf 'instance-id: probe-%s\nlocal-hostname: probe\n' "$name" > "$t/meta-data"
cloud-localds "$t/seed.img" "$t/user-data" "$t/meta-data" || fail "could not make the cloud-init seed"

set -- -m 2048 -smp 2 -display none -monitor none -serial "file:$out/$name-vm-console.log" \
    -drive "if=virtio,file=$t/disk" -drive "if=virtio,format=raw,file=$t/seed.img" \
    -drive "if=virtio,format=raw,file=$t/data.img" -netdev user,id=n0 -device virtio-net-pci,netdev=n0
case $arch in
x86_64)  qemu=qemu-system-x86_64; set -- -machine "q35,accel=$accel" -cpu "$cpu" "$@" ;;
aarch64) qemu=qemu-system-aarch64; set -- -machine "virt,accel=$accel" -cpu "$cpu" -bios /usr/share/qemu-efi-aarch64/QEMU_EFI.fd "$@" ;;
esac
start=$(date +%s)
timeout "$limit" "$qemu" "$@" > "$out/$name-vm-qemu.txt" 2>&1
echo "qemu: exit $? after $(( $(date +%s) - start )) s (limit $limit s)" >> "$out/vm.txt"
# How far the guest got, for RUNS-RULE-2026-10-10b.md's "same stop twice": its kernel, cloud-init,
# and the probe's own marks (vm-inner writes one per step to the console); the last mark is the
# point a stop is compared by.
c=$out/$name-vm-console.log
{ echo "console: kernel $(grep -c 'Linux version' "$c" 2>/dev/null), cloud-init $(grep -ci 'cloud-init' "$c" 2>/dev/null),"\
    "vm-inner start $(grep -c 'vm-inner: start' "$c" 2>/dev/null), done $(grep -c 'vm-inner: done' "$c" 2>/dev/null)"
  echo "console last mark: $(tr -d '\r' < "$c" 2>/dev/null | grep 'vm-inner:' | tail -1)"
  echo "console last line: $(tr -d '\r' < "$c" 2>/dev/null | grep -v '^$' | tail -1)"; } >> "$out/vm.txt"

mkdir -p "$out/$name-vm-disk"
mcopy -s -n -i "$t/data.img" ::/out/* "$out/$name-vm-disk/" 2>> "$out/vm.txt"
[ -d "$out/$name-vm-disk/$name-vm" ] && mv "$out/$name-vm-disk/$name-vm" "$out/$name-vm"
[ -s "$out/$name-vm-disk/done" ] || fail "no done mark on the data disk (RUNS-RULE-2026-10-10b.md)"
grep -q '^strace:    none' "$out/$name-vm/env.txt" 2>/dev/null && fail "strace was not installed in the VM"
[ "$(grep -cE "$(printf '\t')(PASS|FAIL|UNKNOWN|SETUP ERROR)" "$out/$name-vm/summary.txt" 2>/dev/null)" = 3 ] || fail "the VM left no verdict in every mode"
[ "$(grep -cE "$(printf '\t')(PASS|FAIL|UNKNOWN|SETUP ERROR)" "$out/$name-container/summary.txt" 2>/dev/null)" = 3 ] || fail "the control left no verdict in every mode"
