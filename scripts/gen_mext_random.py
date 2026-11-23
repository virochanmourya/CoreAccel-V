#!/usr/bin/env python3
"""Generate a self-checking random RV32M test (tests/common/test.h format).

Usage: gen_mext_random.py --seed N [--ops N] --out <file.S>

The test is a sequence of groups. Each group runs 1-3 M-extension ops back
to back, then CHECKs every register the group wrote. Before each op, each
source register is either loaded with a fresh value (edge values such as 0,
+-1, INT_MIN, INT_MAX, small signed ints, or uniform 32-bit) or left holding
the result of an earlier op. In "chain" groups the ops issue back to back
with no loads in between and usually read the previous op's rd, which
exercises the shared issue/done handshake and forwarding into a multi-cycle
op. Spec corner pairs (INT_MIN / -1, x / 0, ...) are injected on purpose.
rd and rs are drawn from a register pool with deliberate aliasing (rd = rs1,
rd = rs2, rs1 = rs2) and occasional x0.

Expected values come from the reference model below (RISC-V spec semantics,
including divide by zero and INT_MIN / -1), applied to a model of the
register file. The same seed always produces the same file. The output is
only rewritten when its content changes, so make rebuilds only when the
seed or the generator changes.
"""
import argparse
import os
import random
import sys

M32 = 0xFFFFFFFF
INT_MIN, INT_MAX = 0x80000000, 0x7FFFFFFF
OPS = ["mul", "mulh", "mulhsu", "mulhu", "div", "divu", "rem", "remu"]


# ---------------------------------------------------------------- reference model
def s32(x):
    x &= M32
    return x - (1 << 32) if x & 0x80000000 else x


def mext(op, a, b):
    """RV32M result for 32-bit unsigned operands a (rs1), b (rs2)."""
    a &= M32
    b &= M32
    sa, sb = s32(a), s32(b)
    if op == "mul":
        return (sa * sb) & M32
    if op == "mulh":
        return ((sa * sb) >> 32) & M32
    if op == "mulhsu":
        return ((sa * b) >> 32) & M32
    if op == "mulhu":
        return ((a * b) >> 32) & M32
    if op == "div":
        if b == 0:
            return M32
        if a == INT_MIN and sb == -1:
            return INT_MIN
        q = abs(sa) // abs(sb)
        return (-q if (sa < 0) != (sb < 0) else q) & M32
    if op == "divu":
        return M32 if b == 0 else a // b
    if op == "rem":
        if b == 0:
            return a
        if a == INT_MIN and sb == -1:
            return 0
        r = abs(sa) % abs(sb)
        return (-r if sa < 0 else r) & M32
    if op == "remu":
        return a if b == 0 else a % b
    raise ValueError(op)


def self_check():
    assert mext("div", 7, 0) == M32 and mext("rem", 7, 0) == 7
    assert mext("rem", (-7) & M32, 0) == (-7) & M32
    assert mext("divu", 7, 0) == M32 and mext("remu", 7, 0) == 7
    assert mext("div", INT_MIN, M32) == INT_MIN and mext("rem", INT_MIN, M32) == 0
    assert mext("div", (-7) & M32, 2) == (-3) & M32 and mext("rem", (-7) & M32, 2) == (-1) & M32
    assert mext("mulh", INT_MIN, INT_MIN) == 0x40000000
    assert mext("mulhsu", M32, M32) == M32 and mext("mulhu", M32, M32) == 0xFFFFFFFE


# ---------------------------------------------------------------- generator
# s11 (signature pointer) and t6 (TEST_END scratch) are reserved by test.h.
POOL = ["a0", "a1", "a2", "a3", "a4", "a5", "a6", "a7",
        "t0", "t1", "t2", "t3", "t4", "t5"]
EDGES = [0, 1, 2, 3, M32, M32 - 1, INT_MIN, INT_MIN + 1, INT_MAX, INT_MAX - 1,
         0x0000FFFF, 0x00010000, 0x00008000, 0xFFFF8000, 0x55555555, 0xAAAAAAAA]
IMEM_WORDS = 2048
IMEM_MARGIN = 64        # TEST_BEGIN/TEST_END and slack


def li_words(v):
    """Instructions `li` expands to (RV32)."""
    sv = s32(v)
    if -2048 <= sv < 2048:
        return 1
    return 1 if (v & 0xFFF) == 0 else 2


def gen(seed, n_ops):
    rng = random.Random(seed)
    regs = {r: 0 for r in POOL}         # model register file (x0 is always 0)
    lines, checks, words, ops_done = [], 0, 0, 0
    loaded = set()                      # registers given a value by this test

    def value():
        k = rng.random()
        if k < 0.35:
            return rng.choice(EDGES)
        if k < 0.50:
            return rng.randint(-64, 64) & M32
        return rng.getrandbits(32)

    def load(r, v=None):
        nonlocal words
        if v is None:
            v = value()
        regs[r] = v
        loaded.add(r)
        lines.append("    li      %s, 0x%08x" % (r, v))
        words += li_words(v)

    def read(r):
        return 0 if r == "x0" else regs[r]

    group = 0
    while ops_done < n_ops:
        group += 1
        n = rng.choice([1, 1, 2, 2, 3])
        # Chain group: ops after the first load nothing, so they issue back to
        # back, and usually read the previous op's rd (forwarded from EX/MEM
        # straight into the next multi-cycle op's operand latch).
        chain = n > 1 and rng.random() < 0.6
        written = []
        prev_rd = None
        lines.append("    // group %d%s" % (group, " (chain)" if chain else ""))
        for i in range(n):
            op = rng.choice(OPS)
            rs1 = "x0" if rng.random() < 0.04 else rng.choice(POOL)
            rs2 = "x0" if rng.random() < 0.04 else (rs1 if rng.random() < 0.10 else rng.choice(POOL))
            linked = chain and i > 0
            if linked and prev_rd not in (None, "x0") and rng.random() < 0.75:
                if rng.random() < 0.5:
                    rs1 = prev_rd
                else:
                    rs2 = prev_rd
            # Chained ops load nothing (a never-written register reads 0, as
            # in the model: the register file resets to 0).
            if not linked:
                if rs1 not in ("x0", rs2) and rs2 != "x0" and rng.random() < 0.06:
                    # Spec corner cases as an operand pair.
                    a, b = rng.choice([(INT_MIN, M32), (INT_MIN, 1), (INT_MIN, INT_MIN),
                                       (rng.choice(EDGES), 0), (M32, M32), (INT_MIN, INT_MAX)])
                    load(rs1, a)
                    load(rs2, b)
                else:
                    # Fresh operand, or keep the live value (often an earlier result).
                    for r in dict.fromkeys((rs1, rs2)):
                        if r != "x0" and (r not in loaded or rng.random() < 0.55):
                            load(r)
            k = rng.random()
            if k < 0.05:
                rd = "x0"
            elif k < 0.20:
                rd = rs1 if rs1 != "x0" else rng.choice(POOL)
            elif k < 0.30:
                rd = rs2 if rs2 != "x0" else rng.choice(POOL)
            else:
                rd = rng.choice(POOL)
            a, b = read(rs1), read(rs2)
            res = mext(op, a, b)
            lines.append("    %-7s %s, %s, %s%s// %s(0x%08x, 0x%08x) = 0x%08x"
                         % (op, rd, rs1, rs2, " " * max(1, 16 - len(rd + rs1 + rs2)),
                            op, a, b, res))
            words += 1
            ops_done += 1
            if rd != "x0":
                regs[rd] = res
                loaded.add(rd)
            written.append(rd)
            prev_rd = rd
        for r in dict.fromkeys(written):
            lines.append("    CHECK   %s, 0x%08x" % (r, read(r)))
            checks += 1
            words += 2
        if words > IMEM_WORDS - IMEM_MARGIN:
            sys.exit("gen_mext_random: %d ops do not fit in IMEM (%d words used at op %d)"
                     % (n_ops, words, ops_done))
    return lines, checks, words


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--seed", type=int, required=True)
    ap.add_argument("--ops", type=int, default=360)
    ap.add_argument("--out", required=True)
    args = ap.parse_args()
    self_check()

    lines, checks, words = gen(args.seed, args.ops)
    text = "\n".join([
        "// mext_random — GENERATED by scripts/gen_mext_random.py, do not edit.",
        "// seed=%d ops=%d checks=%d (~%d IMEM words)" % (args.seed, args.ops, checks, words),
        "// Regenerate: make test T=mext_random MEXT_SEED=%d MEXT_OPS=%d" % (args.seed, args.ops),
        "#define SIG_WORDS %d" % checks,
        '#include "test.h"',
        "",
        "    TEST_BEGIN",
    ] + lines + ["", "    TEST_END", ""])

    old = open(args.out).read() if os.path.exists(args.out) else None
    if text != old:
        with open(args.out, "w") as f:
            f.write(text)
    print("gen_mext_random: seed=%d ops=%d checks=%d -> %s" % (args.seed, args.ops, checks, args.out))


if __name__ == "__main__":
    main()
