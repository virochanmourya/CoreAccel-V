#!/usr/bin/env python3
"""Split a CoreAccel-V ELF into $readmemh word images.

Usage: elf2hex.py <file.elf> <outdir>

Writes into <outdir>:
  imem.hex      .text words for IMEM  (0x0000_0000, 8 KB)
  tcm.hex       initialised data for TCM (0x8000_0000, 4 KB); omitted if empty
  expected.hex  contents of the non-loaded .expected section (tests only)
  plusargs.txt  KEY=VALUE lines consumed by the xsim harness
                (DBUS_ERRORS=<n> if the ELF defines expected_dbus_errors,
                 HOLD_EX_STORES=<n> if it defines test_hold_ex_stores)

Only PT_LOAD segments with file contents are emitted, routed by physical
address. Anything outside IMEM/TCM is an error, so a stray section can never
silently produce a 2 GB binary or land in the wrong memory.
"""
import os
import struct
import sys

REGIONS = {
    "imem": (0x00000000, 8 * 1024),
    "tcm": (0x80000000, 4 * 1024),
}


def die(msg):
    sys.exit("elf2hex: error: " + msg)


def parse_elf(data):
    if data[:4] != b"\x7fELF" or data[4] != 1 or data[5] != 1:
        die("not a 32-bit little-endian ELF")
    (e_phoff, e_shoff, _flags, _ehsize, e_phentsize, e_phnum,
     e_shentsize, e_shnum, e_shstrndx) = struct.unpack_from("<IIIHHHHHH", data, 0x1C)

    segments = []
    for i in range(e_phnum):
        p_type, p_offset, _vaddr, p_paddr, p_filesz, _memsz, _f, _a = struct.unpack_from(
            "<IIIIIIII", data, e_phoff + i * e_phentsize)
        if p_type == 1 and p_filesz:
            segments.append((p_paddr, data[p_offset:p_offset + p_filesz]))

    sections = []
    for i in range(e_shnum):
        sections.append(struct.unpack_from("<IIIIIIIIII", data, e_shoff + i * e_shentsize))
    shstr = sections[e_shstrndx]

    def name_at(strtab_hdr, off):
        start = strtab_hdr[4] + off
        return data[start:data.index(b"\0", start)].decode()

    named = {name_at(shstr, s[0]): s for s in sections}

    symbols = {}
    for s in sections:
        if s[1] == 2:  # SHT_SYMTAB
            strtab = sections[s[6]]
            for j in range(s[5] // 16):
                st_name, st_value = struct.unpack_from("<II", data, s[4] + j * 16)
                if st_name:
                    symbols[name_at(strtab, st_name)] = st_value
    return segments, named, symbols


def words_of(blob):
    blob = blob + b"\0" * (-len(blob) % 4)
    return [struct.unpack_from("<I", blob, k)[0] for k in range(0, len(blob), 4)]


def write_hex(path, base, chunks):
    """chunks: list of (byte_addr, bytes). Emits @word_index records."""
    lines, nxt = [], None
    for addr, blob in sorted(chunks):
        if (addr - base) % 4:
            die("segment at 0x%08x is not word aligned" % addr)
        idx = (addr - base) // 4
        if idx != nxt:
            lines.append("@%x" % idx)
        ws = words_of(blob)
        lines.extend("%08x" % w for w in ws)
        nxt = idx + len(ws)
    with open(path, "w") as f:
        f.write("\n".join(lines) + "\n")


def main():
    if len(sys.argv) != 3:
        die("usage: elf2hex.py <file.elf> <outdir>")
    elf, outdir = sys.argv[1], os.path.abspath(sys.argv[2])
    with open(elf, "rb") as f:
        segments, sections, symbols = parse_elf(f.read())

    routed = {k: [] for k in REGIONS}
    for addr, blob in segments:
        for name, (base, size) in REGIONS.items():
            if base <= addr and addr + len(blob) <= base + size:
                routed[name].append((addr, blob))
                break
        else:
            die("segment 0x%08x..0x%08x is outside IMEM/TCM" % (addr, addr + len(blob)))

    if not routed["imem"]:
        die("no .text found for IMEM")

    args = []
    for name, chunks in routed.items():
        if chunks:
            path = os.path.join(outdir, name + ".hex")
            write_hex(path, REGIONS[name][0], chunks)
            args.append("%s=%s" % (name.upper(), path))

    if ".expected" in sections:
        hdr = sections[".expected"]
        with open(elf, "rb") as f:
            f.seek(hdr[4])
            exp = words_of(f.read(hdr[5]))
        if "begin_signature" not in symbols or "end_signature" not in symbols:
            die(".expected present but begin_signature/end_signature missing")
        sig_begin, sig_end = symbols["begin_signature"], symbols["end_signature"]
        sig_room = (sig_end - sig_begin) // 4
        if len(exp) > sig_room:
            die("%d checks but signature region holds only %d words" % (len(exp), sig_room))
        tcm_base, tcm_size = REGIONS["tcm"]
        if not (tcm_base <= sig_begin and sig_end <= tcm_base + tcm_size):
            die("signature region must live in TCM")
        path = os.path.join(outdir, "expected.hex")
        with open(path, "w") as f:
            f.write("".join("%08x\n" % w for w in exp))
        args += ["EXPECTED=%s" % path, "SIG_BEGIN=%08x" % sig_begin, "SIG_WORDS=%d" % len(exp)]

    if "test_hold_ex_stores" in symbols:   # listed before the Makefile's HOLD, so it wins
        args.append("HOLD_EX_STORES=%d" % symbols["test_hold_ex_stores"])
    if "expected_dbus_errors" in symbols:
        args.append("DBUS_ERRORS=%d" % symbols["expected_dbus_errors"])

    with open(os.path.join(outdir, "plusargs.txt"), "w") as f:
        f.write("\n".join(args) + "\n")


if __name__ == "__main__":
    main()
