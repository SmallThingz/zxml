# Node-only parser validation

Code revision: `b3f365aeba812fd8e3ca9962d7aa7d6153921f61`. Measured: 2026-09-07T01:18:19+10:00. Zig 0.16.0; methodology version 4.

**The external-parser guardrail now passes 37/37 fixtures. The original >3 GiB/s validated and >5 GiB/s permissive mean-throughput objectives remain unmet.**

## Complete stable measurements

The unchanged stable profile completed in independently guarded CPU6 fixture windows: 220 headline parser/fixture rows plus two validated-only DTD rows, with five samples each, totaling 1,110 positive timed samples. This was not one continuous quiet interval. Each retained fixture includes guarded calibration and all five interleaved sample rounds; contaminated attempts were discarded whole.

Every timed DOM iteration constructs and frees a fresh observable document. Scratch, growth and final node ownership are included. Streaming retains its distinct reusable-parser lifecycle. No exclusions, thresholds or external binaries were changed.

The following rates are arithmetic means of per-fixture median throughputs in GiB/s, not pooled bytes/time rates. JSON stores decimal MB/s; conversion divides by 1073.741824. Validated/permissive counts are 36/37 overall, 14/15 real and 22/22 synthetic. Separate stable snapshots are not a full paired speedup estimate.

| DOM policy | Previous overall | Current overall | Current real | Current synthetic | Objective |
|---|---:|---:|---:|---:|---:|
| Validated | 1.401 | 1.505 | 2.225 | 1.047 | >3 |
| Permissive | 2.619 | 3.279 | 4.130 | 2.698 | >5 |

The previous snapshot is committed at `2450c4f`. Current generated data is in [latest results](results/latest.md) and `results/latest.json`.

The unchanged external gate is `ours-permissive >= max(pugixml, rapidxml)` on every headline fixture: **37/37 pass**, up from 34/37. Validated-only DTD pathology checks pass 2/2 and remain outside headline means and external gates.

| Previously failing fixture | Current ours-permissive MB/s | Best external | Best external MB/s | ours/external |
|---|---:|---|---:|---:|
| character.xml | 2981.11 | rapidxml | 2127.43 | 1.401 |
| transitions.xml | 3235.15 | rapidxml | 2267.66 | 1.427 |
| synthetic_deep_tree.xml | 1416.82 | pugixml | 1323.12 | 1.071 |

## Implemented architecture and compatibility

Default u32 nodes remain 16 bytes. Existing node parent links replace the separate DOM open-element stack. Neither DOM policy builds an attribute-record array. Attributes remain source-backed and lazy. Validated parsing uses small name/filter state, exact source rescanning, and a temporary exact-name set for uncommon large collision cases, not stored attribute/value records.

Small documents use inline nodes and allocate their finished node slice once; spill and allocation-failure paths are covered. Bulk quote scans, exact common closing tags and mixed UTF-8 windows avoid repeated work. Streaming restoration identities and incremental DTD ownership fixes remain intact.

The default permissive fast path can reject literal `>` inside a quoted attribute value. Use `&gt;` or `validate_well_formedness = true` for those inputs. Validated mode retains full handling. The rejection fraction was not measured over an independent representative population; this is not a 0.5% rejection-rate claim.

A producer/consumer regression was reproduced before commit: serialization could emit that newly unsupported spelling after lazy attribute materialization. Both raw and decoded attribute writers now escape `>`, preserving existing entity references appropriately. Eight roundtrip combinations cover mutable/immutable source, raw/encoded input and queried/unqueried attributes.

## Completed final-source correctness validation

| Check | Result |
|---|---|
| Full Debug, ReleaseFast, u16, u64, usize matrix | Root 207 passed, 0 failed, 2 skipped per configuration; all child exit codes successful |
| Native CPU ReleaseSafe root suite | 207 passed, 2 skipped |
| Repository conformance | 112/112 passed |
| Ship-check, public API, examples, documentation | Passed; public API includes the roundtrip regression |
| 32-bit Linux public API with u64 indexes, ReleaseSafe | 3/3 passed |
| Final-source corpus equivalence against `2450c4f` | 38 fixtures × four option profiles; exact nodes and serialized output or matching rejection |
| Final-source malformed-input stress | 12,000 deterministic inputs; 512 KiB arena per attempt; passed |
| Serializer roundtrip runtime | Linux x86_64, Windows x86_64 via Wine and macOS x86_64 via Darwin compatibility runtime; explicit completion markers |

Earlier checks of this parser implementation also passed Linux x86/x86_64 runtime smoke and compile checks for aarch64 Linux/Windows/macOS, ARM Linux, RISC-V, big-endian PowerPC64 and FreeBSD. Those additional architectures were compile-only, not native runtime validation. The serializer-only follow-up was rechecked on the three runtimes above.

## Supplementary paired comparison: incomplete

22 complete paired cases were retained, all in the permissive DOM lane. The retained subset has successful guard evidence, positive samples and independently checked ABBA/BAAB ratios. None of those completed cases exceeded a 1.02 candidate/baseline time ratio.

The larger supplementary matrix of 146 headline cases plus two DTD cases did not finish. A subsequent bounded 1,200-second attempt could not acquire another quiet window; no incomplete or contaminated batch was accepted. This subset does not prove absence of regressions across all DOM and streaming workloads. The complete stable measurements above are separate evidence. Instruction counts were not converted into elapsed throughput.

## Executable provenance

Baseline runners remain frozen from `82c37f5652f607e1734e90f40534740af42d8c3e`. After the serializer-only repair, the final-source rebuild and measured node-only binaries have identical entry points, all allocated non-note sections, and full stripped executable bytes. Differences are non-executable metadata; original measured files retain their exact hashes.

| Measured runner | SHA-256 |
|---|---|
| `zxml-bench` | `81a7a57e4ef1a51e3b87510bbf680921b9359c90c3bddc338690aa2914379453` |
| `zxml-stream-bench` | `f10156225327625c4024b2339def23567c10fb5ea73ecee8435fc2964acfc65c` |

## Evidence index

Current evidence is under `.zig-cache/perf/complete-20260907/`:

- `stable/verified-summary.json`, `stable/results/`, `stable/stderr.log` and manifests: complete stable collection, 38 successful fixture guards, independently checked row identities, samples, medians and units.
- `final-gates/summary.log`: complete final-source correctness matrix.
- `serializer/after.log`, `serializer/final-checks.log` and target runtime logs: roundtrip repair and completion markers.
- `serializer/executable-equivalence.json`: exact measured executables versus final-source rebuild.
- `final-extra/corpus-equivalence.log`, `final-extra/bounded-stress.log`: final-source oracle and stress checks.
- `paired/partial-summary.json`, original paired records/guard receipts, and `paired-batched-final.log`: completed subset and explicit bounded collection failure.

The original absolute throughput objectives and full supplementary paired coverage remain open. No experimental parser variant is retained beyond the committed implementation. No push is authorized by this work.
