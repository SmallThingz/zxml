# Generated-parser rewrite validation

Measured: 2026-09-06T22:58:08+10:00. Compiler: Zig 0.16.0. Methodology: version 4.

**The throughput objectives are not met. The architectural rewrite is implemented and correctness-validated, but performance acceptance is still open.**

## Measured baseline

Independent, fully guarded fixture windows on CPU6. This is not one continuous quiet interval.

The complete stable corpus contains 37 headline fixtures plus one validated-only DTD fixture: 222 parser/fixture rows and 1,110 positive timed samples. Every DOM iteration constructs and frees a fresh document, including parser scratch and node growth. Streaming retains its distinct reusable-parser lifecycle.

All rates below are GiB/s. These are arithmetic means of per-fixture median throughputs, not pooled bytes/time rates. The generated JSON stores decimal MB/s; conversion divides by 1073.741824. Validated/permissive fixture counts are 36/37 overall, 14/15 real, and 22/22 synthetic.

| DOM policy | All applicable fixtures | Real | Synthetic | Objective |
|---|---:|---:|---:|---:|
| Validated | 1.401 | 2.043 | 0.992 | >3 |
| Permissive | 2.619 | 3.592 | 1.956 | >5 |

External guardrail: **34/37 passed**. The unchanged requirement is `ours-permissive >= max(pugixml, rapidxml)` on every fixture.

| Failing fixture | ours-permissive MB/s | Best external | Best external MB/s | ours/external |
|---|---:|---|---:|---:|
| character.xml | 1944.32 | rapidxml | 2143.18 | 0.907 |
| transitions.xml | 1928.89 | rapidxml | 2235.63 | 0.863 |
| synthetic_deep_tree.xml | 1214.39 | pugixml | 1332.92 | 0.911 |

Validated-only DTD pathology checks: 2/2 passed. These remain outside headline means and external gates. Excluded throughput-inflating fixtures were not restored. No thresholds were lowered and no timing checkpoints were resumed.

The generated [latest results](results/latest.md) and `results/latest.json` now contain version-4 measurements, not relabeled historical version-3 data. Numeric README leaderboards remain withheld because the stable gate failed.

## Correctness and accepted changes

| Check | Evidence/result |
|---|---|
| Full Debug, ReleaseFast, u16, u64 and usize matrix | 200 passed, 0 failed, 2 skipped per root suite at `0850f4e` |
| Repository conformance | 112/112 passed in that completed matrix |
| Final ReleaseFast ship-check after restoring rejected candidates | Exit 0; root 200/0/2; public API, examples, docs and tool tests passed |
| Benchmark tool tests after the redirected-output fix | 15/15 passed |
| Redirected-output regression | Before: only 5/30 sample lines survived; after: all 30/30 survived |

The parser runtime was not changed by the three continuation commits:

- `048d5e6`: retain UTF-8 boundary/control regression tests after rejecting the optimization that motivated them.
- `0850f4e`: collect complete fixtures in independent quiet windows, retry only contamination, and reject incomplete/failed child results. Collection mode is explicit in JSON and Markdown.
- `c7a718b`: use streaming console writers so redirected stdout does not overwrite earlier stderr diagnostics.

The earlier saved-state identity and incremental DTD fixes (`d62a706`), Darwin/32-bit portability repairs (`e92a48c`), fresh-document observability (`d332155`), and prebuilt-runner support (`82c37f5`) remain intact.

## Rejected performance candidates

- Unicode prefix-mask changes reduced retired instructions but failed elapsed acceptance. The completed 146-pair comparison included roughly 1.72x DOM time on `weekly_utf8.xml` and 1.85x streaming time on `synthetic_unicode_names.xml`; the implementation was reverted.
- Small-document density reservation regressed instructions by more than 2% on 20 validated and eight permissive fixtures. Its correctness matrix passed, but clean elapsed improvement was not established; it was reverted.
- Scalar start-tag offset returns reduced permissive instructions by 2.69% geometrically, but elapsed screens showed no repeatable gain on the failing character/deep-tree fixtures, wide spreads, and a noisy 2.19% median increase on `tree.xml`. Collection then stopped on contamination/quiet timeouts. This candidate was not promoted; all three source files were restored exactly.

Instruction counts are directional evidence, not elapsed speedups. No unaccepted candidate is included in the measured final runtime.

Continuous whole-profile attempts did not establish a clean continuous run. Contaminated whole runs were discarded in full, including the 22:59 attempt; the accepted data here comes only from complete independently guarded fixture windows. This distinction is not a claim that the throughput objectives were reached.

## Provenance and inherited portability evidence

Frozen runner revision: `82c37f5652f607e1734e90f40534740af42d8c3e`. Measurement harness revision: `c7a718b3dde8de8f28bd18276b79460807478d6a`. Later parser-source changes are tests only. The frozen native runners use ReleaseFast/native CPU settings; external C++ runners use `-O3 -DNDEBUG -march=native`.

| Runner | SHA-256 |
|---|---|
| `pugixml_runner` | `a6e4ebcaf96aefa85871498028edb51063364fa3e8c9a6b95728ceeee353d4af` |
| `rapidxml_runner` | `39c5c4b00d8592c371d37679b571ccc257bee0b1364e559088fa7455d8c98ecb` |
| `zxml-bench` | `43379bad9c22d6844cebafb2f8f35431181fb755df034c1e979d8e4723a9857f` |
| `zxml-stream-bench` | `a196b4e86cd4f49e17e7046b0c0ffc20699cd06a7c4e3946308b895ad852b0f4` |

Accepted collection evidence: `.zig-cache/perf/finish-20260906/verified-guarded-baseline/`. Source, fixtures, runner binaries and harness hashes were checked before/after collection. All 222 row identities, 1,110 samples, medians and throughput-unit calculations were checked independently.

The earlier `final-audit/` evidence records 12,000 deterministic malformed inputs, 48,000 DOM attempts and 48,000 streaming-entry-point attempts with a 512 KiB arena per attempt; 32-bit Linux u64-index public API tests passed 2/2. That audit also recorded Linux x86_64/x86 runtime smoke and Windows/macOS x86_64 compatibility-runtime smoke. This closeout did not re-establish those cross-OS completion markers. Additional aarch64 Linux/Windows/macOS, ARM, RISC-V, big-endian PowerPC64 and FreeBSD lanes were compile-only, not native runtime validation.

The initial `final-audit/cross-summary.log` is pre-fix evidence, not the final portability result. Use the later logs/artifacts and portability commit instead.

## Evidence index and remaining work

- Accepted data/provenance and guard logs: `.zig-cache/perf/finish-20260906/verified-guarded-baseline/`.
- Completed all-index correctness matrix: `.zig-cache/perf/finish-20260906/final-gates/summary.log`.
- Final restored-runtime ship-check: `.zig-cache/perf/finish-20260906/closeout/ship.log` and `ship-exit.txt`.
- Console regression before/after and focused tests: `.zig-cache/perf/finish-20260906/console-order/`.
- Rejected Unicode elapsed comparison: `.zig-cache/perf/finish-20260906/elapsed/`.
- Rejected density and return-interface candidates: `.zig-cache/perf/finish-20260906/small-reserve/` and `tag-end-offset/`.

Remaining performance work is explicit: reach both throughput objectives and pass every external-parser guardrail without changing lifecycle, corpus exclusions or thresholds. The verified failing measurements are a baseline, not completion of those objectives. No parser experiment remains in the tracked tree.
