#!/usr/bin/env python3
"""Load a program into CoreAccel-V through the boot ROM's UART loader.

Usage:
  load.py --emit <frames.txt> <image>...           write the frame stream (no serial port)
  load.py --port /dev/ttyUSB1 [--baud N] <image>... send it to the board

<image> is either one ELF (its PT_LOAD segments) or the hex pair written by
elf2hex.py (imem.hex, and optionally tcm.hex; the file name picks the base
address). --entry sets the jump address (default: the ELF entry, or 0).

Protocol (see boot/loader.S): "CAVB" -> ACK 0x06; then frames
addr(4) len(4) data(len) crc(4), little-endian, CRC-32 (zlib) over
addr|len|data, answered ACK 0x06 / NAK 0x15 (resend) / ERR 0xE1..0xE3;
the last frame has len = 0 and addr = entry.

--emit writes one line per transfer, as hex bytes without spaces: the magic
first, then the data frames, the jump frame last. The xsim harness replays
it on UART0's RX pin.
"""
import argparse
import importlib.util
import os
import struct
import sys
import zlib

MAGIC = b"CAVB"
ACK, NAK = 0x06, 0x15
ERRORS = {0xE1: "bad magic", 0xE2: "too many CRC errors", 0xE3: "address/length out of range"}
FRAME_BYTES = 256
MAX_TRIES = 4           # the loader answers the 4th bad CRC with ERR 0xE2
BASES = {"imem.hex": 0x00000000, "tcm.hex": 0x80000000}

assert zlib.crc32(b"123456789") == 0xCBF43926


def die(msg):
    sys.exit("load.py: error: " + msg)


def read_hex(path, base):
    """$readmemh image (@word_index records) -> list of (byte_addr, bytes)."""
    chunks, addr, cur = [], base, bytearray()
    start = base
    for tok in open(path).read().split():
        if tok.startswith("@"):
            if cur:
                chunks.append((start, bytes(cur)))
            addr = base + 4 * int(tok[1:], 16)
            start, cur = addr, bytearray()
        else:
            cur += struct.pack("<I", int(tok, 16))
            addr += 4
    if cur:
        chunks.append((start, bytes(cur)))
    return chunks


def read_elf(path):
    here = os.path.dirname(os.path.abspath(__file__))
    spec = importlib.util.spec_from_file_location("elf2hex", os.path.join(here, "elf2hex.py"))
    e2h = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(e2h)
    data = open(path, "rb").read()
    segments, _sections, _symbols = e2h.parse_elf(data)
    entry = struct.unpack_from("<I", data, 0x18)[0]
    return [(a, b + b"\0" * (-len(b) % 4)) for a, b in segments], entry


def frame(addr, payload):
    head = struct.pack("<II", addr, len(payload))
    return head + payload + struct.pack("<I", zlib.crc32(head + payload))


def build(images, entry):
    if len(images) == 1 and open(images[0], "rb").read(4) == b"\x7fELF":
        chunks, elf_entry = read_elf(images[0])
        if entry is None:
            entry = elf_entry
    else:
        chunks = []
        for p in images:
            name = os.path.basename(p)
            if name not in BASES:
                die("%s: hex images must be named imem.hex or tcm.hex" % p)
            chunks += read_hex(p, BASES[name])
    frames = []
    for addr, blob in sorted(chunks):
        for k in range(0, len(blob), FRAME_BYTES):
            frames.append(frame(addr + k, blob[k:k + FRAME_BYTES]))
    frames.append(frame(entry or 0, b""))
    return frames


def send(port, baud, frames):
    import serial  # pyserial, only needed for a real board
    with serial.Serial(port, baud, timeout=2) as s:
        def reply():
            r = s.read(1)
            if not r:
                die("no reply from the loader (is the board in UART boot mode?)")
            return r[0]
        s.reset_input_buffer()
        s.write(MAGIC)
        r = reply()
        if r != ACK:
            die("magic refused: 0x%02x %s" % (r, ERRORS.get(r, "")))
        for i, f in enumerate(frames):
            for _ in range(MAX_TRIES):
                s.write(f)
                r = reply()
                if r != NAK:
                    break
            if r != ACK:
                die("frame %d: 0x%02x %s" % (i, r, ERRORS.get(r, "")))
        print("load.py: %d frames sent, program started" % len(frames))


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("images", nargs="+")
    ap.add_argument("--emit", help="write the frame stream to this file")
    ap.add_argument("--port", help="serial port of the board")
    ap.add_argument("--baud", type=int, default=115200)
    ap.add_argument("--entry", type=lambda v: int(v, 0), default=None)
    a = ap.parse_args()
    if bool(a.emit) == bool(a.port):
        die("give exactly one of --emit and --port")
    frames = build(a.images, a.entry)
    if a.emit:
        with open(a.emit, "w") as f:
            f.write(MAGIC.hex() + "\n")
            f.write("".join(fr.hex() + "\n" for fr in frames))
    else:
        send(a.port, a.baud, frames)


if __name__ == "__main__":
    main()
