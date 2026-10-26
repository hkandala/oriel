#!/usr/bin/env python3
"""Prints the UI tests of shard i of n as -only-testing ids joined by commas.

Usage: scripts/shard.py i/n [--on-demand] [--head SECONDS] TEST...
TEST... are the on-demand tests: left out, or with --on-demand the only ones run. The split is by measured time
(scripts/test-times.tsv; a test not listed counts 15 s): the slowest first, each to the shard with the least time
so far. --head: time shard 0 spends on other work first (CI's lint, builds and HerdrKit tests).
"""

import re
import sys
from pathlib import Path

args = sys.argv[1:]
i, n = map(int, args.pop(0).split("/"))
on_demand = "--on-demand" in args
head = int(args[args.index("--head") + 1]) if "--head" in args else 0
listed = {a for a in args if a.startswith("test")}
times = {
    name: int(seconds)
    for seconds, name in (line.split("\t") for line in Path("scripts/test-times.tsv").read_text().splitlines()
                          if not line.startswith("#"))
}
tests = {t for f in Path("OrielUITests").glob("*.swift") for t in re.findall(r"func (test\w+)\(", f.read_text())}
if listed - tests:
    sys.exit(f"on-demand names no test: {sorted(listed - tests)}")
shards = [[head if k == 0 else 0, []] for k in range(n)]
for test in sorted((t for t in tests if (t in listed) == on_demand), key=lambda t: (-times.get(t, 15), t)):
    shard = min(shards, key=lambda s: s[0])
    shard[0] += times.get(test, 15)
    shard[1].append(test)
print(",".join(f"OrielUITests/OrielUITests/{t}" for t in sorted(shards[i][1])))
