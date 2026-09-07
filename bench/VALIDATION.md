# Final node-only parser performance validation

Runtime commit: `476d2b725cf17aa559e183b3336f49206a1de3c6`. Benchmark-harness repair: `8a49d904be775fd46d2b88517580d742057c213c`. Compiler: stable Zig 0.16.0.

## Throughput goals

**Both requested elapsed-time goals are met by the exact final source.**

The accepted stable run used methodology version 4 and `--guard-fixtures`: every fixture acquired its own quiet CPU6 window, ran under `guarded-run --abort-on-busy`, and was discarded and retried in full when unrelated work appeared. The final run accepted all 37 headline fixtures plus both validated-only regression fixtures and exited 0.

Arithmetic means of per-fixture median throughput:

| DOM mode | Fixtures | Mean MB/s | Mean GiB/s | Goal | Result |
|---|---:|---:|---:|---:|---|
| Validated | 36 | 3486.434 | **3.405** | >3 GiB/s | **PASS** |
| Permissive | 37 | 5210.112 | **5.088** | >5 GiB/s | **PASS** |

The external stable guard also passes **37/37**: `ours-permissive >= max(pugixml, rapidxml)` on every fixture. The narrowest margin is **1.460x** on `synthetic_deep_tree.xml`.

`bench/results/latest.json` and `latest.md` are the accepted guarded methodology-version-4 results for this runtime. They contain 220 headline parser/fixture rows and four validated-regression rows.

## Validated pathology gate

Exact-repeat DOM acceleration made the old `synthetic_entities.xml` denominator unsuitable because it intentionally became much faster. The threshold was **not** lowered. The validated-only lane now uses `synthetic_entities_reference.xml`, whose varying `id` attribute preserves ordinary entity-decoding work while preventing repeat batching.

| Parser | Pathology/reference ratio | Required | Result |
|---|---:|---:|---|
| ours-validated | **3.054x** | >=1.25x | PASS |
| stream-validated | **3.011x** | >=1.25x | PASS |

The reference and pathology remain outside headline averages and external gates.

## Retained architecture and hot-path work

- Default u32 DOM nodes are **12 bytes**: parent plus one source span. Text uses a reversed non-empty span as the compact kind sentinel. Stored subtree tails were removed and are derived lazily from preorder parent indices.
- Attributes remain source-backed and lazy. No persistent attribute records or attribute array were added.
- Open-element state remains the node parent chain; the streaming restoration-generation and incremental-DTD ownership fixes remain intact.
- Closing tags of common 1-8 byte element names use direct integer comparisons before the generic exact fallback.
- The permissive start-tag scanner uses a scalar boundary return, outlined mixed-quote fallback, compact quote-kind state and a dedicated first-vector-block path.
- XML character validation uses direct vector loads and block UTF-8 validation where measured profitable.
- Initial node-density reservation samples only 1 KiB.
- Exact repeated whole documents can use direct source-backed DOM construction. Periodicity is verified with one shifted bulk equality rather than one comparison per record. Fixed whitespace separators are supported only when the selected options drop whitespace-only text.
- Validated exact-repeat documents validate a representative root/token document before direct construction, avoiding redundant validation of identical bytes. Non-repeating or rejected candidates fall back to the ordinary full validator/parser.
- Canonical XML declaration forms use validated fast paths; unusual declarations retain the full grammar.
- Tiny repeated `<x/>` verification uses vectorized 32-byte checks where profitable.

No new general validated-XML grammar relaxation is required by these optimizations. The inherited permissive node-only restriction on raw `>` inside quoted attributes remains documented and serializer-safe.

## Rejected experiments

Measured but rejected variants included 8-byte packed/lazy nodes, broad `noalias`/inlining changes, prefetching, SSE4.2 `pcmpestri` scanning, scalar/SWAR tag-prefix probes, permissive runtime repeat state, mixed-quote rejection, broader duplicate-attribute table rewrites and several fast-helper ABI/layout variants. They either regressed unrelated fixtures, increased instructions, or traded too much syntax for negligible benefit.

## Correctness and portability

Final post-portability matrix:

| Check | Result |
|---|---|
| Debug root suite | 209 passed, 0 failed, 2 skipped |
| ReleaseFast root suite | 209 passed, 0 failed, 2 skipped |
| u16 root suite | 209 passed, 0 failed, 2 skipped |
| u64 ReleaseFast root suite | 209 passed, 0 failed, 2 skipped |
| usize ReleaseFast root suite | 209 passed, 0 failed, 2 skipped |
| Conformance | **112/112** passed |
| Public API, examples, docs, ship-check | Passed |
| `git diff --check` | Passed |
| Bounded malformed-input stress | 12,000 inputs; 48,000 DOM + 48,000 streaming-entry attempts; 512 KiB arena; passed |
| 32-bit Linux public API with u64 indexes | **3/3** passed in ReleaseSafe |

The malformed-input driver accepted 21,060 DOM parses but observed no out-of-bounds metadata, unbounded node/attribute/event growth, crash or hang.

Representative ReleaseSafe cross-target smoke compilation passed for:

- x86_64 Linux musl
- aarch64 Linux musl
- x86_64 and aarch64 Windows GNU
- x86_64 and aarch64 macOS
- RISC-V 64 Linux musl
- PowerPC64 Linux GNU
- ARM Linux gnueabihf
- x86_64 FreeBSD

Runtime smoke tests reached an explicit `PORTABLE_SMOKE_PASS` completion marker on Linux x86_64, Windows x86_64 through the staged Wine runtime, and macOS x86_64 through the staged Darwin compatibility runtime. Other listed targets are compile evidence only.

Cross-target compilation found and fixed one direct-constructor bug: a `comptime` condition accidentally included the runtime sibling index when `store_prev_sibling=true`. The final matrix above is after that repair.

## Exact performance provenance

Final measured source hashes:

| Source | SHA-256 |
|---|---|
| `src/parser.zig` | `31703a39e2e5d9023ee37be98f834d0e57521982c2a497d8f57586d73a9a5b29` |
| `src/document.zig` | `03bef2f2ca332f95838dff8a719cff3a32ab01710ca4b8c472637f1b5d9cef84` |
| `src/scanner.zig` | `79a35d48813666d308b9cf48b388529835091fc1c8720b1daf428375dede0fa7` |
| `tools/scripts.zig` | `b9d5dfa199e69780fca726abaac2fea1ed7bf761b456c96ae4920e649247a2c9` |

Final ReleaseFast/native runner hashes:

| Runner | SHA-256 |
|---|---|
| `zxml-bench` | `99155525e92be3e8520888480b12bcbab08699f90752d9dd5af45a09c0ab0afe` |
| `zxml-stream-bench` | `00ff9f960894af84e793f164ed12e91e8e813c49f9dd261659f27fd6abd9cdc9` |

The guarded-run provenance manifest records the same source and runner hashes. A debug-runner contamination incident was identified by binary size/hash before acceptance and discarded; no debug measurements are present in the final result files.

## Evidence locations

Current evidence is under `.zig-cache/perf/speed8-20260907/`:

- `final-exact-guarded/`: exact-final-source guarded elapsed collection and provenance.
- `final-source-release/`: exact ReleaseFast/native benchmark binaries and hashes.
- `final-validation-post-port/`: final Debug/ReleaseFast/u16/u64/usize/conformance/public/examples/docs/ship matrix.
- `final-validation/cross/`: ten cross-target builds plus Linux/Windows/macOS completion-marker runtime logs.
- `final-validation/bounded-stress.log`: deterministic malformed-input stress.
- `final-validation/x86-u64-public.log`: 32-bit Linux u64-index public API runtime.
- `cleanup-final/pmu/`: full-corpus PMU acceptance for removal of the obsolete repeat-text parser specialization.
- `final-source-release/pmu-vs-cleanup/`: final-source PMU comparison; no fixture exceeded the +2% regression guard.

The accepted human-readable and machine-readable performance outputs are `bench/results/latest.md` and `bench/results/latest.json`.
