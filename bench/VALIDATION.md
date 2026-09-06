# Generated-parser rewrite validation

Date: 2026-09-06. Source revision: `82c37f5652f607e1734e90f40534740af42d8c3e`. Compiler: Zig 0.16.0.

## Code status

All accepted changes are committed. There is no pending parser experiment. The intentionally untracked handoff is excluded from commits.

- `d62a706`: prevent saved-state generation reuse and isolate incremental DTD validation from full-parse scratch. Both regressions were reproduced before fixing them.
- `e92a48c`: repair Darwin cold sections and 32-bit address/shift conversions, including u64-index public APIs on a 32-bit host. CI now uses the generated benchmark modes and checks these portability paths.
- `d332155`: keep completed DOM storage observable, document fresh construction/freeing in each timed iteration, and advance the benchmark methodology to version 4.
- `82c37f5`: allow measurements of prebuilt, frozen runners without compiling inside the quiet window.

## Executed validation

| Check | Result |
|---|---|
| Debug, ReleaseFast, u16, u64, usize root suites | 198 passed, 0 failed, 2 skipped per configuration |
| Repository conformance cases | 112/112 passed |
| Final ship-check, public API, examples, documentation | Passed |
| 32-bit Linux public API with u64 indexes, ReleaseSafe | 2/2 passed |
| Frozen DOM/streaming/external runner smoke invocations | 8/8 passed |
| Deterministic malformed-input stress | 12,000 inputs across generated DOM/streaming profiles; passed with a 512 KiB arena per attempt |
| Linux x86_64 and x86 runtime smoke | Passed |
| Windows x86_64 under Wine; macOS x86_64 under Darwin compatibility runtime | Passed |

Cross-compilation also passed for aarch64 Linux/Windows/macOS, ARM Linux, RISC-V Linux, big-endian PowerPC64 Linux, and x86_64 FreeBSD. Those additional targets were compile checks, not native runtime tests.

## Directional instruction measurements

These compare the streaming correctness fixes at `d62a706` with the inherited streaming implementation. Each sample used CPU6, `cpu_core/instructions/u`, a successful child exit, 100.00% event running time, and alternating baseline/candidate order. Ratios are candidate/baseline geometric means, not elapsed-time speedups.

| Workload | Fixtures | Instruction ratio | Largest regression |
|---|---:|---:|---:|
| Full permissive streaming | 37 | 1.000002030 | 0.0016% |
| Full validated streaming | 36 | 1.000001139 | 0.0010% |
| Validated parseAvailable | 10 | 0.995916197 | 0.7665% |
| Divergent save/restore workload | 1 | 0.992020460 | Not applicable |

## Throughput status

**The >3 GiB/s validated and >5 GiB/s permissive goals are not verified.** No new full stable elapsed-time result was accepted. Five guarded attempts encountered foreign workloads: four could not acquire a quiet window, and one was discarded after contamination during runner compilation. Later attempts separated the build phase from measurement using `--no-build`.

The historical `latest.json` and `latest.md` were left unchanged. They are methodology version 3 and must not be represented as current generated-parser performance. No contaminated samples were published and no throughput threshold or external-parser gate was relaxed.

## Frozen runners

The current native runners were built with ReleaseFast / native CPU settings (C++ runners with -O3 / -march=native), smoke-tested, and frozen under `.zig-cache/perf/final-audit/baseline-82c37f5652f607e1734e90f40534740af42d8c3e/binaries`. Source, fixture, and runner hashes were verified unchanged. These are ready-to-measure binaries, not evidence of a completed throughput run.

| Runner | SHA-256 |
|---|---|
| `pugixml_runner` | `a6e4ebcaf96aefa85871498028edb51063364fa3e8c9a6b95728ceeee353d4af` |
| `rapidxml_runner` | `39c5c4b00d8592c371d37679b571ccc257bee0b1364e559088fa7455d8c98ecb` |
| `zxml-bench` | `43379bad9c22d6844cebafb2f8f35431181fb755df034c1e979d8e4723a9857f` |
| `zxml-stream-bench` | `a196b4e86cd4f49e17e7046b0c0ffc20699cd06a7c4e3946308b895ad852b0f4` |

Detailed regression, gate, stress, cross-target, instruction-counter, and quiet-host logs are in `.zig-cache/perf/final-audit/`. No validation or benchmark process from this pass is left running.
