# Final node-only and streaming parser validation

Base revision before this work: `b1fe3095b11f876f7bff39afb0c30ac53333f9dd`. Compiler: stable Zig 0.16.0.

## Stable throughput

The accepted publication run uses benchmark methodology version 4 with `--guard-fixtures`. Each fixture gets an independent quiet CPU6 window; contamination discards the complete fixture calibration/sample set and retries it. All 37 headline fixtures plus both validated-only regression fixtures were accepted, and the final command exited 0.

Arithmetic means of per-fixture median throughput:

| Parser | Fixtures | Mean MB/s | Mean GiB/s | Result |
|---|---:|---:|---:|---|
| stream-permissive | 37 | 8884.945 | **8.677** | PASS |
| stream-validated | 36 | 6982.084 | **6.818** | PASS |
| ours-permissive | 37 | 5128.300 | **5.008** | PASS (>5 GiB/s goal) |
| ours-validated | 36 | 3439.703 | **3.359** | PASS (>3 GiB/s goal) |
| rapidxml | 37 | 1118.917 | 1.093 | reference |
| pugixml | 37 | 1087.401 | 1.062 | reference |

Streaming is now faster than the DOM average in both modes: approximately **1.73x** permissive and **2.03x** validated on the stable corpus.

The stable external DOM guard is **37/37 PASS** for `ours-permissive >= max(pugixml, rapidxml)`. The narrowest margin is **1.414x** on `tree.xml`.

`bench/results/latest.json` and `bench/results/latest.md` contain all stable per-fixture numbers and raw samples. `README.md` and `bench/README.md` publish the complete 37-fixture table.

## Benchmark result semantics

Performance gate misses are benchmark results, not tool failures. A completed stable run prints and records `PASS`/`FAIL` counts and returns normally even when a performance gate misses. Real harness failures still error: invalid arguments, missing/failed child processes, malformed benchmark output, I/O failures, or incomplete guarded fixture transfers.

A stable run with performance FAIL rows still writes `latest.{json,md}` for diagnosis, but it does **not** replace the published README benchmark snapshot. Publication happens only when the stable gates pass. A scratch stable run with one deliberately forced external-gate failure verified the negative path: it returned **0**, printed `external 0/1 PASS, 1 FAIL`, wrote diagnostic results, and left both README snapshots byte-for-byte unchanged.

The default `full` developer profile covers the same 37 fixtures with shorter sampling and writes `bench/results/full.{json,md}` without replacing stable evidence.

## XML compliance / conformance

The repository has 12 conformance suites covering well-formedness, error handling, entities/text, cross-mode behavior, W3C-style cases, XML-DSig integrity, HL7/ISO 20022, XSD-core behavior, Schematron-core business rules, and OWASP/NIST security cases.

Current result: **112/112 PASS, 0 FAIL across 12 suites**.

- `zig build tools -- run-conformance` is report mode: it prints per-suite and aggregate PASS/FAIL counts without converting a failed compliance case into a tool error.
- `zig build tools -- run-conformance --strict` returns nonzero when any case fails.
- `zig build conformance` uses strict mode so CI/release validation still fails on a broken parser.

The reporting contract was exercised with an intentional failing scratch suite: report mode returned 0 with `0/1 PASS, 1 FAIL`; strict mode returned nonzero with the same result counts.

## Streaming optimization

Full-buffer `StreamingParser.parse` now has source-backed fast paths while `parseAvailable`, incremental parsing, save/restore and skipped-subtree semantics retain their existing transactional parser path.

Retained mechanisms:

- exact repeated-document detection reuses the DOM's proven periodicity detectors;
- validated repeated documents validate one representative root/token before direct event emission;
- repeated self-closing and simple-text documents emit the same source spans/events without reparsing every identical token;
- callback `false` still skips the same subtree/text events;
- successful direct-repeat parses advance the streaming generation so saved-state identities remain fresh;
- permissive full-buffer start tags use the quote-aware bulk tag-boundary scanner and retain the old parser as fallback;
- permissive text runs use the dedicated SIMD text delimiter finder;
- validated common attribute lists use a narrow exact fast validator and disable that lane after the first incompatible tag, avoiding repeated fallback tax;
- already-empty stack/reset state and already-sufficient stack reservation avoid redundant work on reusable parsers.

Invalid, complex, non-repeating or incremental input falls back to the existing parser. No validated XML grammar relaxation is required for these streaming optimizations.

### Streaming equivalence evidence

A frozen pre-change streaming implementation and the final candidate were run over all 37 stable fixtures in both permissive and validated modes. The oracle fingerprints event sequence/count, kind, depth, name/data spans, token end, self-closing flag and parse error identity.

Result: **74/74 exact streaming event/error comparisons PASS**.

Focused streaming-module validation is **121/121 PASS** on the default index type, including large repeated attributes, validated repeated text, root subtree skipping, save-generation changes and invalid repeated entity fallback.

### Streaming performance evidence

Against the exact previously published streaming binary, complete CPU6 unscaled retired-instruction comparisons show:

| Mode | Fixtures | Geometric instruction ratio | Change | >2% regressions |
|---|---:|---:|---:|---:|
| stream-permissive | 37 | **0.364555** | -63.5% | 0 |
| stream-validated | 36 | **0.319857** | -68.0% | 0 |

Clean focused elapsed comparisons measured repeated workloads approximately **4.8x-14.4x faster permissive** and **5.6x-47.3x faster validated**, while ordinary real XML remained neutral or improved. The stable averages above are the authoritative publication numbers.

## Validated pathology gate

The validated-only entity pathology lane keeps its unchanged minimum ratio of 1.25x and remains outside headline/external averages.

| Parser | Pathology/reference ratio | Required | Result |
|---|---:|---:|---|
| ours-validated | **4.031x** | >=1.25x | PASS |
| stream-validated | **3.050x** | >=1.25x | PASS |

## DOM architecture retained

- Default u32 DOM nodes remain **12 bytes**: parent plus one source span; compact text kind is encoded by the reversed non-empty span convention.
- Attributes remain source-backed and lazy; there is no persistent attribute-record array.
- Open-element state remains the node parent chain.
- Existing streaming restoration-generation and incremental-DTD ownership fixes remain intact.
- DOM repeated-document construction, direct short closing matches, vector validation/scanning and 1 KiB node-density sampling remain intact.
- The inherited permissive node-only restriction on raw `>` in quoted attribute values remains documented and serializer-safe; validated XML retains the full grammar.

## Correctness matrix

| Check | Result |
|---|---|
| Debug root suite | 211 passed, 0 failed, 2 skipped |
| ReleaseFast root suite | 211 passed, 0 failed, 2 skipped |
| u16 root suite | 209 passed, 0 failed, 4 skipped |
| u64 ReleaseFast root suite | 211 passed, 0 failed, 2 skipped |
| usize ReleaseFast root suite | 211 passed, 0 failed, 2 skipped |
| Conformance | **112/112 PASS, 0 FAIL** |
| Public API, examples, docs, ship-check | PASS |
| `git diff --check` | PASS |
| Streaming corpus event/error oracle | **74/74 PASS** |
| Bounded malformed-input stress | 12,000 inputs; 48,000 DOM + 48,000 streaming-entry attempts; PASS |
| 32-bit Linux public API with u64 indexes | **3/3 PASS** |

The extra two u16 skips are the new >512 KiB full-buffer streaming fast-path tests. u16 cannot represent an input large enough to activate that path; the implementation still compiles and the ordinary u16 parser tests remain green.

The malformed-input driver accepted 21,060 DOM parses and observed no out-of-bounds metadata, unbounded node/attribute/event growth, crash or hang.

## Portability

Representative ReleaseSafe cross-target smoke compilation passes for:

- x86_64 Linux musl
- aarch64 Linux musl
- x86_64 and aarch64 Windows GNU
- x86_64 and aarch64 macOS
- RISC-V 64 Linux musl
- PowerPC64 Linux GNU
- ARM Linux gnueabihf
- x86_64 FreeBSD

Runtime smoke tests reach an explicit `PORTABLE_SMOKE_PASS` marker on Linux x86_64, Windows x86_64 through the staged Wine runtime, and macOS x86_64 through the staged Darwin compatibility runtime. Other listed targets are compile evidence only.

## Exact stable provenance

Final measured source/tool hashes:

| Source | SHA-256 |
|---|---|
| `src/parser.zig` | `b2275e66a3d2e85ca6591019fdca6d303dd8b39c03f21a60b784f4c237e55d7d` |
| `src/scanner.zig` | `4b8697028c9339a4c3ffc7c7578cdf39f9525f32cff2022ef54b95602f83fd32` |
| `src/streaming.zig` | `583826e0551592175337ea1daf2dbb552ae2bd5387f449474f33772277cab6de` |
| `tools/scripts.zig` | `fe9ae87f3a4f0fe9f96429cf4e82d7d6858763cb588b01e993e869977f9d6b05` |
| `tools/conformance.zig` | `28d9bb73c1c20d5a6ec52f3d31bf3c5a0daeb0f22c6176188c73383ab91f6e72` |
| `build.zig` | `2591429e34ceb7a9a840cc374bcddc6f094f2dff31a19f4f06a6c3f0bc634f71` |

A final test-only assertion was added after the guarded timing run to cover repeated duplicate-attribute rejection. Rebuilding ReleaseFast/native after that assertion produced byte-for-byte identical `zxml-bench` and `zxml-stream-bench` binaries, so the measured runtime code is unchanged.

Final ReleaseFast/native runner hashes:

| Runner | SHA-256 |
|---|---|
| `zxml-bench` | `afba6170addb2f72f6ff91b59fc086260a3806a592636c98a04e1528c08e134a` |
| `zxml-stream-bench` | `2a77c74a859450be22b266871c8286e0b628e6c74536b2143d94dea8300dd6d0` |
| `pugixml_runner` | `a6e4ebcaf96aefa85871498028edb51063364fa3e8c9a6b95728ceeee353d4af` |
| `rapidxml_runner` | `39c5c4b00d8592c371d37679b571ccc257bee0b1364e559088fa7455d8c98ecb` |

## Evidence locations

Current evidence is under `.zig-cache/perf/stream-repeat-v6/`:

- `stable-final/`: exact-source guarded stable run, runner/source provenance and pre-run snapshots.
- `pmu/`: complete streaming retired-instruction comparison versus the previously published runner.
- `oracle/`: 74-case baseline/candidate streaming event/error fingerprints.
- `final-gates/`, `final-gates2/`, `u16-fixed.log`: root/configuration/conformance/ship validation.
- `extra-gates2/`: corrected 12-byte-node malformed stress and 32-bit u64 public API evidence.
- `cross/`: ten cross-target compiles plus Linux/Windows/macOS runtime completion markers.
- `reporting-contract/`: report-vs-strict conformance behavior evidence.

Accepted human-readable and machine-readable performance outputs are `bench/results/latest.md` and `bench/results/latest.json`.
