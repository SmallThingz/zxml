#!/usr/bin/env python3
"""Paired A/B benchmark runner with swapped CPU assignments.

Each repeat launches baseline and candidate simultaneously on two pinned CPUs,
then swaps the binaries across those CPUs. The two assignment ratios are
geometrically combined to cancel stable per-core speed differences. Repeats
are summarized by their median, not their geometric mean, so an occasional
scheduler/interrupt outlier cannot reverse a sub-percent result.
"""

import argparse
import json
import math
import os
import statistics
import subprocess


def positive_int(text: str) -> int:
    value = int(text)
    if value <= 0:
        raise argparse.ArgumentTypeError("must be > 0")
    return value


def nonnegative_int(text: str) -> int:
    value = int(text)
    if value < 0:
        raise argparse.ArgumentTypeError("must be >= 0")
    return value


def gm(values):
    if not values:
        raise ValueError("empty geometric mean")
    if any(value <= 0 for value in values):
        raise ValueError("geometric mean requires positive values")
    return math.exp(sum(math.log(value) for value in values) / len(values))


def load_cases(path):
    with open(path, encoding="utf-8") as file:
        cases = json.load(file)
    if not isinstance(cases, list) or not cases:
        raise ValueError("cases JSON must be a non-empty array")
    for index, case in enumerate(cases):
        if not isinstance(case, dict):
            raise ValueError(f"case {index} is not an object")
        if not isinstance(case.get("path"), str) or not case["path"]:
            raise ValueError(f"case {index} has invalid path")
        if type(case.get("iterations")) is not int or case["iterations"] <= 0:
            raise ValueError(f"case {index} has invalid iterations")
    return cases


def launch(binary, core, path, iterations):
    return subprocess.Popen(
        ["taskset", "-c", str(core), binary, path, str(iterations)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )


def finish(process):
    stdout, stderr = process.communicate()
    if process.returncode:
        raise RuntimeError(f"{process.args}: rc={process.returncode}\n{stderr}")
    text = stdout.strip()
    if not text.isdecimal():
        raise RuntimeError(f"{process.args}: invalid timing output {text!r}")
    value = int(text)
    if value <= 0:
        raise RuntimeError(f"{process.args}: non-positive timing {value}")
    return value


def assignment(args, path, iterations, swap=False):
    if not swap:
        base_process = launch(args.base, args.core_a, path, iterations)
        cand_process = launch(args.cand, args.core_b, path, iterations)
        return finish(base_process), finish(cand_process)

    cand_process = launch(args.cand, args.core_a, path, iterations)
    base_process = launch(args.base, args.core_b, path, iterations)
    cand_ns = finish(cand_process)
    base_ns = finish(base_process)
    return base_ns, cand_ns


def summarize_case(args, case):
    path = case["path"]
    iterations = case["iterations"]
    name = case.get("name", os.path.basename(path))

    # Excluded warm-up pair, including both assignments.
    assignment(args, path, iterations, False)
    assignment(args, path, iterations, True)

    ratios = []
    base_pairs = []
    cand_pairs = []
    for _ in range(args.repeats):
        base_a, cand_b = assignment(args, path, iterations, False)
        base_b, cand_a = assignment(args, path, iterations, True)
        ratios.append(math.sqrt((cand_b / base_a) * (cand_a / base_b)))
        base_pairs.append(math.sqrt(base_a * base_b))
        cand_pairs.append(math.sqrt(cand_a * cand_b))

    # Median is the point estimate. The old harness used gm(ratios), which is
    # mathematically elegant but not robust: one interrupted assignment can
    # dominate a sub-percent result even after the core swap. Keep the GM only
    # as a diagnostic so unstable cases are visible.
    ratio = statistics.median(ratios)
    base_ns = statistics.median(base_pairs)
    cand_ns = statistics.median(cand_pairs)
    return {
        "path": path,
        "iterations": iterations,
        "name": name,
        "ratio": ratio,
        "ratio_gm": gm(ratios),
        "base_ns": base_ns,
        "cand_ns": cand_ns,
        "pairs": ratios,
        "min": min(ratios),
        "max": max(ratios),
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--base", required=True)
    parser.add_argument("--cand", required=True)
    parser.add_argument("--repeats", type=positive_int, default=9)
    parser.add_argument("--core-a", type=nonnegative_int, default=0)
    parser.add_argument("--core-b", type=nonnegative_int, default=2)
    parser.add_argument("--cases-json", required=True)
    parser.add_argument("--out")
    args = parser.parse_args()

    if args.core_a == args.core_b:
        parser.error("--core-a and --core-b must be different")
    if args.repeats < 3 or args.repeats % 2 == 0:
        parser.error("--repeats must be an odd integer >= 3")
    for binary in (args.base, args.cand):
        if not os.path.isfile(binary) or not os.access(binary, os.X_OK):
            parser.error(f"not an executable file: {binary}")
    if os.path.samefile(args.base, args.cand):
        parser.error("--base and --cand must be different executables")

    if hasattr(os, "sched_getaffinity"):
        allowed = os.sched_getaffinity(0)
        for core in (args.core_a, args.core_b):
            if core not in allowed:
                parser.error(f"CPU {core} is outside this process's affinity set")

    cases = load_cases(args.cases_json)
    for case in cases:
        if not os.path.isfile(case["path"]):
            parser.error(f"case path is not a file: {case['path']}")
    results = []
    for case in cases:
        row = summarize_case(args, case)
        results.append(row)
        spread = row["max"] - row["min"]
        print(
            f"{row['name']:34s} {row['ratio']:.6f} "
            f"gm={row['ratio_gm']:.6f} spread={spread:.6f}",
            flush=True,
        )

    overall = gm([row["ratio"] for row in results])
    summed = sum(row["cand_ns"] for row in results) / sum(row["base_ns"] for row in results)
    print(f"GM {overall:.6f}")
    print(f"SUM {summed:.6f}")

    if args.out:
        with open(args.out, "w", encoding="utf-8") as file:
            json.dump(results, file, indent=2)
            file.write("\n")


if __name__ == "__main__":
    main()
