# SIMD parser optimization and validation

Runtime commit: `1972c2f9f60ec99cd22e2cc0b047195b8a77ee7e`. Baseline: `afa458d4a57456bc628575ded870a0ad3d14c0ae`. Compiler: Zig 0.16.0.

## Throughput status

**No current elapsed-time throughput was accepted. The >3 GiB/s validated and >5 GiB/s permissive targets remain unverified for this revision.**

Guarded paired screens and the final stable attempt could not complete clean quiet-host collection. No partial or contaminated timing data was published. Only the owned measurement outputs were restored.

The retained latest.json/latest.md describe the previous node-only runtime, not this SIMD revision. That earlier version-4 collection measured 1.505 GiB/s validated and 3.279 GiB/s permissive overall, with 37/37 external gates and 2/2 DTD checks. These historical numbers must not be represented as current performance.

The supplementary paired elapsed-time screen did not complete. The counter evidence below is separate from elapsed-time speedups and does not establish GiB/s.

## Exact retired-instruction comparison

All 146 headline parser/mode/fixture comparisons completed against exact frozen binaries. Each used CPU6 and cpu_core/instructions/u with successful child exits and 100.00% event runtime. Perf itself was pinned before child creation, avoiding startup migration on the hybrid CPU. Four samples per comparison gave 584 accepted unscaled samples in BCCB order. Row arithmetic and coverage were independently checked.

The table gives geometric means of per-fixture candidate/baseline instruction ratios. These are not elapsed-time ratios. The validated-only DTD fixture is outside this 146-case headline comparison.

| Lane | Fixtures | Instruction ratio | Change | Worst fixture ratio |
|---|---:|---:|---:|---:|
| zxml-bench validated | 36 | 0.969330 | -3.07% | 1.007315 |
| zxml-bench permissive | 37 | 0.975246 | -2.48% | 1.001086 |
| zxml-stream-bench validated | 36 | 1.000000 | -0.00% | 1.000000 |
| zxml-stream-bench permissive | 37 | 0.973906 | -2.61% | 1.000000 |

No final row increased instructions by more than 2%. That does not substitute for a full elapsed-time no-regression result.

## Changes retained

- Direct bounded unaligned SIMD loads in the text delimiter scanner. Assembly had reconstructed a vector from scalar loads, inserts and broadcasts; the retained form permits a direct memory-vector comparison.
- Exact DOM UTF-8 block validation with continuation/range checks and bounded reprocessing of incomplete trailing codepoints. The streaming wide-ASCII/scalar path was preserved after its vector variant increased work on token-heavy workloads.
- Removed an unused character-data validation wrapper and inlined the one-use node cleanup expression. Compact nodes, node-only DOM construction, lazy attributes and fresh-document ownership remain unchanged.

No additional XML restrictions were introduced. The inherited permissive restriction on raw `>` inside quoted attributes and its serializer escaping fix remain unchanged. Validated XML semantics, streaming restoration identities and incremental DTD ownership fixes remain intact.

## Experiments not promoted

Broad vector-pointer replacement increased validated work on 13 fixtures. Merging start-tag paths and adding blanket noalias source parameters caused material validated instruction regressions, reaching roughly 11% on the screen. Vector-first special scanning and short-name comparisons also regressed some workload shapes. Those parser/scanner rewrites were restored rather than stacked into the final code.

Explicit 256-byte input prefetching increased permissive instructions by 0.88% geometrically on its eleven-fixture screen, with +2.20% on arxiv_cs.xml, and had no accepted elapsed benefit. It was removed. Branch annotations, noalias, wider SIMD and inlining were not assumed beneficial merely because they reduced source lines.

## Completed correctness and portability

| Check | Result |
|---|---|
| Debug, ReleaseFast, u16, u64 and usize root suites | 209 passed, 0 failed, 2 skipped each |
| Conformance | 112/112 passed |
| Ship-check, public API, examples, docs and tool tests | Passed |
| Frozen/current corpus oracle | 38 fixtures x 4 profiles; exact node fields and serialization |
| UTF-8 oracle, native AVX2 and baseline SSE | 2,374,449 comparisons per build; passed |
| Bounded malformed-input stress | 12,000 inputs, 48,000 DOM and 48,000 streaming attempts, 512 KiB arena per attempt; passed |
| Linux x86 public API with u64 indexes | 3/3 passed in ReleaseSafe |
| Linux x86_64/x86 runtime | Explicit completion markers observed |
| Windows/macOS x86_64 compatibility runtime | Explicit completion markers observed |

Aarch64 Linux/Windows/macOS, ARM Linux, RISC-V Linux, big-endian PowerPC64 Linux and FreeBSD passed compile checks. These are not native runtime qualifications. Cross-OS runtime checks used Wine and the existing Darwin compatibility runtime.

## Evidence

All evidence is under .zig-cache/perf/speed-20260907. Source and frozen-binary manifests were checked around the accepted work.

- profiles/: cycle profiles and annotated assembly for six representative workloads.
- final/pmu/: complete 146-case counter matrix and 584 raw accepted samples.
- gates/summary.log: all correctness, corpus, oracle and cross-target completion statuses.
- utf8-vector/oracle.zig: reproducible scalar-value, truncated-prefix, byte-pair and mixed-buffer comparison.
- stable/: final quiet-host collection attempt, exit status, snapshots and verification when complete.
- vector-load/, cleanup/, noalias/, scan-vectors/, scan-prefix2/, short-name/, prefetch/: separated candidate binaries, logs and decisions.

| Final runner | SHA-256 |
|---|---|
| zxml-bench | `1fb62fd776388076d2b5e1c162429f242c1d580c2dfea01b3b3c098cbd36f02c` |
| zxml-stream-bench | `27c582c86ef788ab9f15ad2b37af2ff1994494866edf719ef596506a6177f43d` |
