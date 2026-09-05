# zxml Agent Instructions

## Mission

Build zxml around the same architectural principles as zhtml, extrapolated to XML rather than preserving older zxml APIs or storage layouts. Throughput is the primary constraint, with bounded safe behavior on malformed input. The default path should handle the common ~98% of XML cheaply; rare malformed/spec-heavy cases may return errors, but must not crash, hang, read out of bounds, or grow memory without limit.

### Architecture contract

- `ParseOptions` is a comptime type generator. Options select concrete `Document`, `RawNode`, `Node`, `Attribute`, and streaming parser types; do not reintroduce runtime parse-mode option bundles.
- Destructive `[]u8` parsing is the default. `non_destructive = true` generates an immutable `[]const u8` variant.
- Default DOM nodes remain compact: with `u32` indexes the target layout is 16 bytes (`parent`, `subtree_end`, `name_or_text`). Optional navigation and misc-node metadata must compile out when disabled.
- No persistent navigation sidecar. Persist subtree bounds in-node; derive navigation unless the generated type explicitly requests additional indexes.
- Attributes and text remain source-backed and lazy. Destructive documents may compact/decode in source and cache the result; immutable documents use raw scans or owned fallbacks. Do not add document-wide attribute/value arrays to make queries easier.
- `validate_well_formedness = true` is the explicit expensive XML-validation policy. The default parser is permissive and bounded, with named close-tag recovery and implicit EOF closure where safe.
- Parser open-element stacks are ephemeral parser state, with a small inline stack and safe heap spill. They do not live in the finished `Document`.
- Do not add compatibility aliases, legacy overloads, side representations, or wrappers for deleted APIs unless the user explicitly requests backwards compatibility. Migrate first-party callers instead.
- Current headline throughput targets on the corrected corpus are >3 GiB/s validated and >5 GiB/s permissive. Do not inflate averages with byte-heavy synthetic outliers.

## Workspace rules

- Work in `/home/a/zxml` on branch `main` unless the user explicitly says otherwise.
- Stable Zig is `~/.local/bin/zig` and should report `0.16.0`.
- Keep experiment scratch under `/home/a/zxml/.zig-cache/perf`.
- Do not create checkpoint archives, external experiment worktrees, or separate project directories.
- Do not reset to `origin/main` just to recover state.
- Do not push to GitHub unless the user explicitly asks.
- Preserve unrelated/untracked files such as `HANDOFF-V19G-REMOTE.md`.
- Before editing, inspect `git status --short --branch` and the relevant diff.

## Commit identity

Accepted commits must use both author and committer:

```text
ItsMeSamey <sameychain5041@gmail.com>
```

Set all four `GIT_AUTHOR_*` / `GIT_COMMITTER_*` environment variables explicitly when committing.

## Shared-host behavior

This machine is shared with other active work, including `/home/a/zalloc`, `/home/a/zfuzz`, `/home/a/dict`, and potentially other projects.
- Never kill, pause, renice, pin, or otherwise interfere with foreign project processes.
- Only terminate processes that this zxml task started and owns.
- Do not trust benchmark data collected while unrelated CPU-heavy work is active.
- If a performance run is contaminated, discard it and retry later; do not "correct" the number statistically.
- Correctness/build checks may run during ordinary host activity, but avoid needlessly competing with long foreign builds.

## Global performance tools

`~/.local/bin` is on `PATH`. Reusable host/profiling tools live there and should be preferred over ad-hoc one-off monitors.

### `host-quiet`

One-shot host activity check:

```sh
host-quiet
```

Exit code `0` means quiet. Exit code `75` means at least one foreign process crossed the CPU threshold; the command prints the PID, approximate core utilization, and command line.

Wait for a continuous clean window:

```sh
host-quiet --wait --quiet-for 1.5
```

Useful options:

- `--threshold 0.25` sets the busy threshold in CPU cores.
- `--interval 0.10` sets the `/proc` sampling interval.
- `--ignore STRING` ignores a known harmless command substring.
- `--allow-pid PID` ignores one PID.
- `--ignore-tree PID` ignores a whole process tree, useful for monitoring around an owned workload.
### `guarded-run`

Run an owned command only after a quiet window and monitor for mid-run contamination:

```sh
guarded-run --abort-on-busy -- taskset -c 8 ./benchmark args...
```

Behavior:

- waits for a clean host before starting unless `--no-wait` is given;
- ignores the measured command's own process tree;
- never kills foreign processes;
- with `--abort-on-busy`, terminates only the measured process group if contamination appears;
- returns exit code `75` for a contaminated run, even if the measured command was terminated by the wrapper;
- otherwise returns the measured command's exit code.

For extremely short nanosecond-scale benchmarks, keep monitoring overhead in mind. Prefer ABBA blocks with a lightweight in-process monitor when the wrapper itself could perturb the measurement.

### `gdb-parent-sample`

Use this when ordinary `perf` is unavailable and ptrace attach is restricted. It starts the target as GDB's child and interrupts the GDB process group for samples.

Generic form:

```sh
gdb-parent-sample --samples 120 --raw-log .zig-cache/perf/profile.raw -- command arg1 arg2 ...
```

For zxml, a typical pinned-core invocation is:

```sh
gdb-parent-sample --samples 120 --raw-log .zig-cache/perf/twoattr.raw -- \
  taskset -c 6 zig-out/bin/zxml-bench parse permissive bench/fixtures/synthetic_two_attr.xml 500
```

It prints one classified top frame per sample, followed by aggregate counts. Exit code `2` means it captured zero samples and the result is unusable.
## Performance methodology

- Pin timing work to a stable P-core where possible. On the current i5-12450H host, accepted full-corpus work uses CPU 6 (P-core); CPU 8 is an E-core and must not be treated as the primary headline core.
- Use swapped ABBA ordering (`B C C B`, then `C B B C`) to reduce drift bias.
- Prefer several blocks and report the median candidate/base elapsed-time ratio.
- Treat candidate/base ratio above `1.02` as a material regression unless a stronger rerun clearly overturns it.
- Treat large block spread as noise; rerun noisy or near-gate cases with more blocks and/or more bytes.
- Separate raw elapsed-time ratios from frequency-normalized diagnostics. Do not hide raw regressions behind normalization.
- Benchmark normal workloads first, but explicitly cover edge shapes touched by the optimization.
- Keep baseline and candidate binaries/source hashes when a result matters.
- Do not use results from a run that `host-quiet`, `guarded-run`, or an in-process guard marked contaminated.

## Optimization discipline

- Profile first, then inspect generated assembly around sampled PCs before editing.
- Change one mechanism at a time and keep diffs small enough to attribute regressions.
- Add focused correctness coverage for any new fast path or branch pruning.
- Do not keep a target-only win if unrelated common workloads regress materially.
- Revert rejected experiments cleanly; do not stack speculative changes on top of each other.
- Before repeating an old idea, inspect `HANDOFF-V19G-REMOTE.md` for rejected variants and why they failed.

## Required correctness gates

Before committing a performance change, run the stable Zig 0.16 toolchain through the full acceptance set:
```sh
cd /home/a/zxml
zig build test
zig build test -Doptimize=ReleaseFast
zig build test -Dintlen=u16
zig build test -Dintlen=u64 -Doptimize=ReleaseFast
zig build test -Dintlen=usize -Doptimize=ReleaseFast
zig build conformance -Doptimize=ReleaseFast
zig build ship-check -Doptimize=ReleaseFast
git diff --check
```

Also run the focused tests for the changed subsystem and public API/basic smoke coverage when applicable.

## Cross-platform checks

Compile representative parser/benchmark targets when codegen, integer width, SIMD, sections, or target-specific behavior is touched. Recent useful targets include:

- `x86_64-linux-musl`
- `aarch64-linux-gnu` and `aarch64-linux-musl`
- `x86_64-windows-gnu` and `aarch64-windows-gnu`
- `x86_64/aarch64` FreeBSD, NetBSD, and OpenBSD where supported
- `riscv64-linux-gnu` / `riscv64-linux-musl`
- `powerpc64le-linux-gnu`
- `arm-linux-gnueabihf`

When a cross-target check fails, compare the candidate against its parent before attributing the failure to the current change.
