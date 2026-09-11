"""elfsyms.py <elf> tls|imports <names...>: TLS symbols by size, or which names are imported (undefined in .dynsym)."""
import struct, sys
path, mode, names = sys.argv[1], sys.argv[2], set(sys.argv[3:])
d = open(path, "rb").read()
if mode == "phdr":  # phdr: the PT_TLS program header, which is what the loader reserves per thread
    phoff, = struct.unpack_from("<Q", d, 0x20); phentsize, phnum = struct.unpack_from("<HH", d, 0x36)
    for i in range(phnum):
        p_type, _, _, _, _, p_filesz, p_memsz, p_align = struct.unpack_from("<IIQQQQQQ", d, phoff + i * phentsize)
        if p_type == 7:
            print("PT_TLS filesz=%d memsz=%d align=%d" % (p_filesz, p_memsz, p_align))
            break
    else:
        print("no PT_TLS")
    sys.exit(0)
shoff, = struct.unpack_from("<Q", d, 0x28); shentsize, shnum, shstrndx = struct.unpack_from("<HHH", d, 0x3A)
secs = [struct.unpack_from("<IIQQQQIIQQ", d, shoff + i * shentsize) for i in range(shnum)]
def cstr(off):
    return d[off:d.index(b"\0", off)].decode(errors="replace")
want = 2 if mode == "tls" else 11  # SHT_SYMTAB / SHT_DYNSYM
out = []
for s in secs:
    if s[1] != want:
        continue
    strtab = secs[s[6]]
    for j in range(s[5] // 24):
        st_name, st_info, st_other, st_shndx, st_value, st_size = struct.unpack_from("<IBBHQQ", d, s[4] + j * 24)
        n = cstr(strtab[4] + st_name)
        if mode == "tls" and (st_info & 0xF) == 6:
            out.append((st_size, n))
        if mode == "imports" and st_shndx == 0 and n.split("@")[0] in names:
            out.append((0, n))
for size, n in sorted(out, reverse=True)[:12]:
    print(size, n) if mode == "tls" else print("imports", n)
if mode == "imports":
    print("not imported:", sorted(names - {n.split("@")[0] for _, n in out}))
