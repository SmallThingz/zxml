# ZXML Benchmark Suite

This suite compares `zxml` against:

- `pugixml`
- `rapidxml`

The corpus mixes:

- downloaded real XML fixtures (`note.xml`, `sitemaps.xml`, `plant_catalog.xml`, `cd_catalog.xml`, `hnrss.xml`, `xkcd_rss.xml`, `bbc_world.xml`, `arxiv_cs.xml`, `ecb_usd.xml`)
- curated UTF-8/XML samples copied from the vendored `pugixml` corpus (`tree.xml`, `character.xml`, `transitions.xml`, `xgconsole.xml`, `weekly_utf8.xml`, `pugixml_large.xml`)
- generated synthetic stress fixtures for attributes, depth, entities, CDATA/PI/comment mixes, wide sibling sets, namespaces, long names, self-closing tags, and small-record workloads

## Setup

```bash
zig build tools -- setup-parsers
zig build tools -- setup-fixtures
```

## Run

```bash
# full setup + comparison, matching zhtml
zig build bench-compare
zig build bench-compare -- --profile stable
zig build bench-interleaved -- ../zxml-base ../zxml-candidate --profile quick --repeats 9 --core-a 0 --core-b 2
zig build conformance

# direct tool invocation after setup, when needed
zig build tools -- run-benchmarks --profile quick
zig build tools -- run-benchmarks --profile stable
zig-out/bin/zxml-tools run-benchmarks --profile stable --no-build --guard-fixtures
```

`run-benchmarks` also updates:

- `README.md` auto-summary block
- `bench/README.md` latest benchmark snapshot block

For a frozen-binary measurement, build the runners first and use `zig-out/bin/zxml-tools run-benchmarks --profile stable --no-build` inside the quiet-host guard. This skips compilation, not parsing or validation; the caller must verify that all four runner binaries match the intended source revision.

Results are written to:

- `bench/results/latest.json`
- `bench/results/latest.md`

Headline DOM benchmarks instantiate the actual generated parser types: `permissive` is `ParseOptions{}` and `validated` sets only `validate_well_formedness = true`. Misc-node storage is not silently enabled. The benchmark workflow follows zhtml. zxml keeps input/setup outside the timed region and constructs and frees a fresh generated `Document` in every timed iteration. Parser scratch and node growth are included; finished node capacity is not retained between DOM parses. Streaming reuses its generated parser state. An optimization barrier keeps each completed DOM observable before destruction. The node-only DOM uses parent links for nesting and no attribute-record array. Its small-document inline node buffer is rebuilt on each iteration, not retained across parses. The default permissive DOM may reject raw `>` within a quoted attribute value; the validated policy preserves that grammar. Corpus membership and external gates are unchanged. External runners use their native repeat-parse lifecycle. zxml runners are
built with `ReleaseFast -Dcpu=native`; C++ runners use `-O3 -DNDEBUG -march=native`.
The harness uses a system `c++` driver when available and falls back to `zig c++`
on minimal hosts. Each generated report records the kernel, architecture, CPU model,
frequency-scaling state, advertised CPU MHz range, Zig version, and C++ driver.

On a shared Linux host, `--no-build --guard-fixtures` collects each fixture in an
independent clean window using `host-quiet`, `guarded-run`, and CPU6 via `taskset`.
The guard covers calibration and all five interleaved sample rounds for every
applicable parser. Exit 75 discards that entire fixture attempt and retries it;
other failures stop collection. Parser/fixture coverage, lifecycle, exclusions,
and performance gates are unchanged. JSON records `guarded_fixtures: true`, and
Markdown identifies this collection mode. This is not one continuous quiet run.

Guarded collection neither reads nor writes timing checkpoints and cannot be
combined with `--resume` or runner compilation. The older `--resume` option is
not a contamination guard: never reuse a checkpoint from a contaminated run.

The default node-only fast path may reject literal `>` in quoted attribute values; full validated mode retains that syntax. A passing external gate does not establish the original absolute throughput objectives; see [validation](VALIDATION.md).

Fixture setup rejects extremely opaque feeds. `synthetic_long_text.xml` remains
a generated diagnostic-only fixture and is excluded from quick/stable profiles.
`synthetic_doctype_entities.xml` is also excluded from headline profiles and
external gates; stable runs exercise it only in the validated-only regression lane.
When that regression check passes, its detailed timings stay out of the human
benchmark tables and remain available only in `bench/results/latest.json`.

<!-- BENCH_README_AUTO_SNAPSHOT:START -->

No current elapsed-time snapshot was accepted for the SIMD revision. The retained latest results are historical node-only measurements. See [validation and provenance](VALIDATION.md); retired-instruction reductions are not GiB/s results.

<!-- BENCH_README_AUTO_SNAPSHOT:END -->

Conformance suites live in `bench/conformance/*.json` and can also be run with:

```bash
zig build tools -- run-conformance
zig build tools -- run-conformance --suite bench/conformance/well_formedness_w3c_core.json
```

Each conformance case may target one or many parser profiles:

- `"profile": "validated"` for a validating generated parser
- `"profiles": ["validated", "permissive"]` to run the same assertions in both generated policies

## Parser Perf Guardrail

The hard gate is:

- `ours-permissive >= max(pugixml, rapidxml)` per fixture

For parser-only optimization passes, use the paired A/B harness below.

Optional validated/permissive spot checks:

```bash
zig-out/bin/zxml-bench parse validated bench/fixtures/sitemaps.xml 400
zig-out/bin/zxml-bench parse permissive bench/fixtures/sitemaps.xml 2000
```

For sub-percent parser A/B work, use `bench/paired_bench.py`. It runs baseline
and candidate simultaneously on two pinned CPUs, swaps the CPU assignments,
geometrically combines each assignment pair, then uses the median paired ratio
across repeats to reject scheduler outliers. Reported ratios are candidate time
divided by baseline time, so values below `1.0` are faster.
