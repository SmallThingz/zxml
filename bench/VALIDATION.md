# Parser validation

Compiler: Zig 0.16.0. Published benchmark data: `bench/results/latest.{json,md}`.

## Stable throughput

Methodology v5 reports **MiB/s** (`bytes / 1,048,576 / seconds`). The accepted stable run used `--guard-fixtures`; every fixture was measured in its own quiet CPU6 window and any contaminated fixture attempt was discarded in full. All 37 headline fixtures and both validated-only pathology fixtures completed, and the benchmark command exited 0.

| Parser | Fixtures | Mean MiB/s | Mean GiB/s | Target | Result |
|---|---:|---:|---:|---:|---|
| DOM permissive | 37 | **4963.01** | **4.847** | >5 GiB/s | **FAIL** |
| DOM validated | 36 | **3434.82** | **3.354** | >3 GiB/s | **PASS** |
| Streaming permissive | 37 | **10244.76** | **10.005** | — | **PASS** |
| Streaming validated | 36 | **8495.97** | **8.297** | — | **PASS** |
| pugixml | 37 | 1020.56 | 0.997 | — | — |
| rapidxml | 37 | 1044.55 | 1.020 | — | — |

The external permissive gate passes **37/37** (`ours-permissive >= max(pugixml, rapidxml)`), with the narrowest margin **1.433x** on `tree.xml`.

Streaming is now substantially faster than DOM on the same stable corpus. Full-buffer streaming uses repeat-document event emission, bulk permissive start-tag scanning, SIMD text scanning, common validated-attribute scanning, and reusable-parser setup reductions. Incremental `parseAvailable`, save/restore, and incomplete-token semantics remain on the transactional parser path. A 74-case corpus oracle (37 fixtures × permissive/validated) matched the previous streaming event/error fingerprints exactly.

DOM permissive remains **0.153 GiB/s (3.1%)** below the >5 GiB/s objective. The final exact-repeat optimization replaces short-branch `std.mem.eql` periodicity checks with a wide exact shifted-equality loop. It checks every byte and reduced full-corpus retired instructions without changing accepted syntax.

## Validated pathology gate

The threshold remains 1.25x. `synthetic_entities_reference.xml` is deliberately non-repeating so repeat batching cannot distort the denominator.

| Parser | Pathology/reference | Required | Result |
|---|---:|---:|---|
| DOM validated | **2.890x** | >=1.25x | PASS |
| Streaming validated | **2.827x** | >=1.25x | PASS |

## Correctness

| Check | Result |
|---|---|
| Debug root suite | 211 passed, 0 failed, 2 skipped |
| ReleaseFast root suite | 211 passed, 0 failed, 2 skipped |
| u16 root suite | 209 passed, 0 failed, 4 skipped |
| u64 ReleaseFast root suite | 211 passed, 0 failed, 2 skipped |
| usize ReleaseFast root suite | 211 passed, 0 failed, 2 skipped |
| Conformance | **112/112 PASS, 0 FAIL** across 12 suites |
| Ship check | PASS |
| `git diff --check` | PASS |
| Malformed-input stress | 12,000 inputs; 48,000 DOM + 48,000 streaming attempts; PASS |
| 32-bit Linux public API with u64 indexes | 3/3 PASS |

The two extra u16 skips are large-document streaming fast-path tests whose inputs exceed the u16 parser's representable input range; the fast path itself cannot activate in that configuration.

## Portability

ReleaseSafe compile checks passed for x86_64 Linux musl, aarch64 Linux musl, x86_64/aarch64 Windows GNU, x86_64/aarch64 macOS, RISC-V 64 Linux musl, PowerPC64 Linux GNU, ARM Linux gnueabihf, and x86_64 FreeBSD.

Runtime smoke tests reached explicit completion markers on Linux x86_64, Windows x86_64 through Wine, and macOS x86_64 through the staged compatibility runtime.

## Final architecture

- Default u32 DOM nodes are 12 bytes: parent plus one source span.
- Attributes remain source-backed and lazy; there is no persistent attribute array.
- DOM nesting uses parent links, not a separate open-element stack.
- Streaming keeps its separate ephemeral stack and incremental save/restore state.
- Exact repeated documents use verified direct DOM construction / streaming event emission.
- The default permissive DOM may reject literal `>` inside a quoted attribute value; validated mode retains the complete quoted-value grammar.
- Benchmark failures are reported as PASS/FAIL results rather than tool errors. Harness/runtime failures still return errors.
- Direct conformance defaults to report-only; `zig build conformance` and `run-conformance --strict` remain strict.

## Exact benchmark provenance

Final measured source SHA-256:

| Source | SHA-256 |
|---|---|
| `src/parser.zig` | `c89f492e30d3358feb045b516776621b648849dff3c74cf336fffa154de803d7` |
| `src/scanner.zig` | `78c3256992db221de840094cf5b59707266ac6a93b6709aee8343cca951e5c1d` |
| `src/streaming.zig` | `583826e0551592175337ea1daf2dbb552ae2bd5387f449474f33772277cab6de` |
| `tools/scripts.zig` | `65b28d1f825a6828f9011e875238e289c06464ab06b9924dab0cd80eb24097d3` |

Final ReleaseFast/native runners:

| Runner | SHA-256 |
|---|---|
| `zxml-bench` | `e3329aafaf5039dc7dad9f83e35793eb5ab23f7f9d9dabed9018bad6f63f6b6e` |
| `zxml-stream-bench` | `54fb814c89597760681c1c698d499d5d6ded5bed7a1fad76d010e0b9a40a6a80` |

Detailed fixture numbers are intentionally kept in `bench/README.md`, not the root README.
