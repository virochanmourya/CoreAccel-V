#!/usr/bin/env python3
"""Summarise a regression run.

Usage: regress_summary.py <build/tests dir> <known_failures.txt> <test>...

Reads the RESULT line from each <test>/xsim.log and classifies it against the
known-failures list:
  PASS   passed
  XFAIL  failed, listed as a known open bug
  XPASS  passed but listed as known-failing (remove it from the list)
  FAIL   failed and not expected to
Exit status is 1 if any test is FAIL, otherwise 0.
"""
import os
import re
import sys


def load_known(path):
    known = {}
    if os.path.exists(path):
        for line in open(path):
            line = line.split("#", 1)[0].strip()
            if line:
                parts = line.split(None, 2)
                known[parts[0]] = (parts[1], parts[2] if len(parts) > 2 else "")
    return known


def main():
    tests_dir, known_path, tests = sys.argv[1], sys.argv[2], sys.argv[3:]
    known = load_known(known_path)
    rows, counts = [], {"PASS": 0, "XFAIL": 0, "XPASS": 0, "FAIL": 0}
    for t in tests:
        log = os.path.join(tests_dir, t, "xsim.log")
        status, detail = "FAIL", "no RESULT line"
        if os.path.exists(log):
            for line in open(log, errors="replace"):
                m = re.match(r"RESULT (\w+) test=\S+ ?(.*)", line)
                if m:
                    status, detail = m.group(1), m.group(2).strip()
        passed = status == "PASS"
        if t in known:
            cls = "XPASS" if passed else "XFAIL"
            note = "%s: %s" % known[t]
        else:
            cls = "PASS" if passed else "FAIL"
            note = ""
        counts[cls] += 1
        rows.append((t, cls, status, detail, note))

    w = max(len(t) for t in tests) if tests else 10
    out = ["", "%-*s  %-5s  %-7s  %s" % (w, "test", "class", "result", "detail")]
    out.append("-" * (w + 60))
    for t, cls, status, detail, note in rows:
        out.append("%-*s  %-5s  %-7s  %s%s" % (w, t, cls, status, detail,
                                               ("   [" + note + "]") if note else ""))
    out.append("-" * (w + 60))
    out.append("PASS %(PASS)d  XFAIL %(XFAIL)d  XPASS %(XPASS)d  FAIL %(FAIL)d" % counts)
    text = "\n".join(out)
    print(text)
    with open(os.path.join(tests_dir, "..", "regress_summary.txt"), "w") as f:
        f.write(text + "\n")
    sys.exit(1 if counts["FAIL"] else 0)


if __name__ == "__main__":
    main()
