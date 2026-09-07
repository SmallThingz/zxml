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
# full 37-fixture comparison, optimized for day-to-day runs
zig build bench-compare

# publication-grade 37-fixture comparison
zig build bench-compare -- --profile stable
zig build bench-interleaved -- ../zxml-base ../zxml-candidate --profile quick --repeats 9 --core-a 0 --core-b 2
zig build conformance

# direct tool invocation after setup, when needed
zig build tools -- run-benchmarks --profile quick
zig build tools -- run-benchmarks --profile full
zig build tools -- run-benchmarks --profile stable
zig-out/bin/zxml-tools run-benchmarks --profile stable --no-build --guard-fixtures
```

`full` and `stable` cover the same 37 headline fixtures and compute the same external and validated-pathology comparisons. `full` is the default developer profile: three samples targeted at 5 ms each, scaled-down calibration hints, and reuse of an in-range calibration measurement as sample 1. `stable` remains the publication profile: five independent samples targeted at 40 ms each. Both profiles report gate misses as `FAIL` results rather than tool errors; only a fully passing stable run updates the published README snapshots. `quick` keeps its smaller fixture subset.

Developer profiles also reuse already-built pugixml/rapidxml runners when their runner sources and parser headers are older than the binaries. `stable` always rebuilds both external runners so publication evidence never depends on a stale C++ artifact.

A fully passing `stable` run also updates:

- `README.md` auto-summary block
- `bench/README.md` latest benchmark snapshot block

`full` writes `bench/results/full.{json,md}` for the developer run and leaves `latest.{json,md}` plus the publication README snapshots untouched.

For a frozen-binary measurement, build the runners first and use `zig-out/bin/zxml-tools run-benchmarks --profile stable --no-build` inside the quiet-host guard. This skips compilation, not parsing or validation; the caller must verify that all four runner binaries match the intended source revision.

Results are written to:

- `bench/results/full.json` and `full.md` for the default `full` profile
- `bench/results/latest.json` and `latest.md` for publication-grade `stable` runs

Performance gate misses are benchmark results, not tool errors. Rows and summaries are
reported as `PASS`/`FAIL`, result files are still written, and the benchmark command
exits normally. Actual harness failures (missing binaries, malformed result output,
crashes, invalid arguments, I/O errors) still return an error. A failed `stable` run
does not replace the published README snapshot.

Headline DOM benchmarks instantiate the actual generated parser types: `permissive` is `ParseOptions{}` and `validated` sets only `validate_well_formedness = true`. Misc-node storage is not silently enabled. The benchmark workflow follows zhtml. zxml keeps input/setup outside the timed region and constructs and frees a fresh generated `Document` in every timed iteration. Parser scratch and node growth are included; finished node capacity is not retained between DOM parses. Streaming reuses its generated parser state. An optimization barrier keeps each completed DOM observable before destruction. The node-only DOM uses parent links for nesting and no attribute-record array. Its small-document inline node buffer is rebuilt on each iteration, not retained across parses. The default permissive DOM may reject raw `>` within a quoted attribute value; the validated policy preserves that grammar. Corpus membership and external gates are unchanged. External runners use their native repeat-parse lifecycle. zxml runners are
built with `ReleaseFast -Dcpu=native`; C++ runners use `-O3 -DNDEBUG -march=native`.
The harness uses a system `c++` driver when available and falls back to `zig c++`
on minimal hosts. Each generated report records the kernel, architecture, CPU model,
frequency-scaling state, advertised CPU MHz range, Zig version, and C++ driver.

On a shared Linux host, `--no-build --guard-fixtures` collects each fixture in an
independent clean window using `host-quiet`, `guarded-run`, and CPU6 via `taskset`.
The guard covers calibration and every interleaved sample round for each applicable parser. `full` uses three rounds; `stable` uses five. Exit 75 discards that entire fixture attempt and retries it;
other failures stop collection. Parser/fixture coverage, lifecycle, exclusions,
and performance gates are unchanged. JSON records `guarded_fixtures: true`, and
Markdown identifies this collection mode. This is not one continuous quiet run.

Guarded collection neither reads nor writes timing checkpoints and cannot be
combined with `--resume` or runner compilation. The older `--resume` option is
not a contamination guard: never reuse a checkpoint from a contaminated run.

The default node-only fast path may reject literal `>` in quoted attribute values; full validated mode retains that syntax. A passing external gate does not establish the original absolute throughput objectives; see [validation](VALIDATION.md).

Fixture setup rejects extremely opaque feeds. `synthetic_long_text.xml` remains
a generated diagnostic-only fixture and is excluded from quick/full/stable profiles.
`synthetic_doctype_entities.xml` is also excluded from headline profiles and
external gates; full and stable runs exercise it only in the validated-only regression lane.
That lane compares it against `synthetic_entities_reference.xml`, a deliberately
non-repeating ordinary-entity workload so exact-repeat DOM acceleration cannot
artificially inflate the denominator. The 1.25x minimum ratio is unchanged. Detailed
regression timings stay out of the human benchmark tables and remain available only
in `bench/results/latest.json`.

<!-- BENCH_README_AUTO_SNAPSHOT:START -->

Source: `bench/results/latest.json` (`stable` profile).

## Latest Benchmark Snapshot

### Benchmark Environment

| Property | Value |
|---|---|
| OS / kernel | Linux 7.2.2-zen1-1-zen |
| Architecture | x86_64 |
| CPU | 12th Gen Intel(R) Core(TM) i5-12450H |
| CPU frequency scaling | 85% |
| CPU MHz range | 400.0000–4400.0000 |
| Zig | 0.16.0 (`ReleaseFast -Dcpu=native`) |
| C++ driver | c++ (`-O3 -DNDEBUG -march=native`) |

### Parse Throughput Comparison (MiB/s)

| Fixture | ours-permissive | ours-validated | stream-permissive | stream-validated | pugixml | rapidxml |
|---|---:|---:|---:|---:|---:|---:|
| `note.xml` | 2710.53 | 1616.38 | 3060.98 | 1344.83 | 924.51 | 1670.73 |
| `sitemaps.xml` | 3926.92 | 1872.14 | 3349.58 | 1680.71 | 1894.83 | 1945.90 |
| `plant_catalog.xml` | 3498.65 | 1772.09 | 3066.48 | 1485.97 | 1501.72 | 1647.44 |
| `cd_catalog.xml` | 2956.39 | 1583.38 | 2629.61 | 1271.72 | 1231.45 | 1519.60 |
| `hnrss.xml` | 9446.27 | 5328.87 | 7787.92 | 4260.97 | 2824.64 | 2601.58 |
| `xkcd_rss.xml` | 4758.08 | 2949.57 | 8037.94 | 2621.26 | 2340.50 | 1990.79 |
| `bbc_world.xml` | 5898.02 | 3284.26 | 5290.96 | 3055.91 | 2561.72 | 2483.25 |
| `arxiv_cs.xml` | 8205.69 | 4033.72 | 10243.43 | 4293.52 | 2574.02 | 1831.41 |
| `ecb_usd.xml` | 6375.85 | 3010.40 | 5603.35 | 2605.24 | 2517.22 | 2654.68 |
| `tree.xml` | 2801.74 | 1328.39 | 2877.49 | 1277.34 | 1209.28 | 1955.35 |
| `character.xml` | 3298.52 | 1403.29 | 3140.07 | 1433.36 | 1145.83 | 2024.72 |
| `transitions.xml` | 3541.43 | - | 3289.86 | - | 1426.50 | 2135.49 |
| `xgconsole.xml` | 5798.87 | 1888.62 | 5840.93 | 1268.85 | 1820.12 | 2364.01 |
| `weekly_utf8.xml` | 3691.60 | 1221.94 | 3074.62 | 658.97 | 2142.75 | 2325.07 |
| `pugixml_large.xml` | 2415.13 | 1370.61 | 2028.36 | 1549.74 | 439.38 | 278.44 |
| `synthetic_flat_attrs.xml` | 6374.20 | 1223.95 | 8414.90 | 1298.43 | 443.47 | 340.94 |
| `synthetic_deep_tree.xml` | 1773.64 | 1051.91 | 1628.88 | 1001.26 | 1154.21 | 717.33 |
| `synthetic_entities.xml` | 10571.02 | 10428.11 | 41964.96 | 41611.67 | 854.68 | 839.22 |
| `synthetic_cdata_mix.xml` | 2136.64 | 1596.07 | 2574.32 | 1608.85 | 624.12 | 482.26 |
| `synthetic_wide_siblings.xml` | 1440.51 | 1011.26 | 2056.20 | 1061.09 | 402.52 | 299.01 |
| `synthetic_namespace_mix.xml` | 3519.19 | 1337.48 | 3949.04 | 1318.95 | 651.98 | 537.77 |
| `synthetic_long_names.xml` | 6043.50 | 2980.36 | 5518.16 | 2378.72 | 1283.02 | 1512.84 |
| `synthetic_self_closing_swarm.xml` | 4309.13 | 1130.58 | 4972.03 | 1216.55 | 558.47 | 453.81 |
| `synthetic_mixed_content.xml` | 2087.17 | 1280.35 | 2863.52 | 1271.50 | 497.66 | 376.04 |
| `synthetic_small_records.xml` | 1702.29 | 1211.99 | 2349.05 | 1180.37 | 389.86 | 291.30 |
| `synthetic_tiny_empty.xml` | 1651.12 | 1636.55 | 6770.80 | 6749.94 | 182.92 | 116.60 |
| `synthetic_tiny_text.xml` | 1702.34 | 1653.13 | 16961.26 | 17327.74 | 167.13 | 119.69 |
| `synthetic_one_attr.xml` | 3469.50 | 3455.75 | 14133.84 | 14103.14 | 253.16 | 175.32 |
| `synthetic_two_attr.xml` | 5560.88 | 5482.92 | 20242.09 | 20324.03 | 286.78 | 206.42 |
| `synthetic_attrs4.xml` | 9006.86 | 8886.57 | 27617.51 | 27480.11 | 313.52 | 238.09 |
| `synthetic_attrs8.xml` | 13770.39 | 13906.16 | 34460.84 | 34419.69 | 335.59 | 249.35 |
| `synthetic_single_quotes.xml` | 10456.10 | 10301.90 | 30381.89 | 29786.20 | 460.49 | 360.11 |
| `synthetic_unicode_names.xml` | 8907.67 | 8867.61 | 41273.02 | 40805.38 | 598.52 | 493.62 |
| `synthetic_pretty_indented.xml` | 1768.50 | 1257.41 | 2103.01 | 1275.17 | 454.61 | 357.08 |
| `synthetic_crlf_pretty.xml` | 1938.79 | 1158.09 | 2774.32 | 1320.77 | 492.07 | 412.92 |
| `synthetic_token_whitespace_mix.xml` | 9736.01 | 9771.83 | 28132.67 | 28097.93 | 422.24 | 345.14 |
| `synthetic_attr_count_mix.xml` | 6382.11 | 1359.85 | 8592.25 | 1408.88 | 379.27 | 295.14 |

### External Parser Gates

| Fixture | ours-permissive | best external | ours/best-ext | Result |
|---|---:|---|---:|---|
| `note.xml` | 2710.53 | `rapidxml` 1670.73 | 1.622 | PASS |
| `sitemaps.xml` | 3926.92 | `rapidxml` 1945.90 | 2.018 | PASS |
| `plant_catalog.xml` | 3498.65 | `rapidxml` 1647.44 | 2.124 | PASS |
| `cd_catalog.xml` | 2956.39 | `rapidxml` 1519.60 | 1.946 | PASS |
| `hnrss.xml` | 9446.27 | `pugixml` 2824.64 | 3.344 | PASS |
| `xkcd_rss.xml` | 4758.08 | `pugixml` 2340.50 | 2.033 | PASS |
| `bbc_world.xml` | 5898.02 | `pugixml` 2561.72 | 2.302 | PASS |
| `arxiv_cs.xml` | 8205.69 | `pugixml` 2574.02 | 3.188 | PASS |
| `ecb_usd.xml` | 6375.85 | `rapidxml` 2654.68 | 2.402 | PASS |
| `tree.xml` | 2801.74 | `rapidxml` 1955.35 | 1.433 | PASS |
| `character.xml` | 3298.52 | `rapidxml` 2024.72 | 1.629 | PASS |
| `transitions.xml` | 3541.43 | `rapidxml` 2135.49 | 1.658 | PASS |
| `xgconsole.xml` | 5798.87 | `rapidxml` 2364.01 | 2.453 | PASS |
| `weekly_utf8.xml` | 3691.60 | `rapidxml` 2325.07 | 1.588 | PASS |
| `pugixml_large.xml` | 2415.13 | `pugixml` 439.38 | 5.497 | PASS |
| `synthetic_flat_attrs.xml` | 6374.20 | `pugixml` 443.47 | 14.373 | PASS |
| `synthetic_deep_tree.xml` | 1773.64 | `pugixml` 1154.21 | 1.537 | PASS |
| `synthetic_entities.xml` | 10571.02 | `pugixml` 854.68 | 12.368 | PASS |
| `synthetic_cdata_mix.xml` | 2136.64 | `pugixml` 624.12 | 3.423 | PASS |
| `synthetic_wide_siblings.xml` | 1440.51 | `pugixml` 402.52 | 3.579 | PASS |
| `synthetic_namespace_mix.xml` | 3519.19 | `pugixml` 651.98 | 5.398 | PASS |
| `synthetic_long_names.xml` | 6043.50 | `rapidxml` 1512.84 | 3.995 | PASS |
| `synthetic_self_closing_swarm.xml` | 4309.13 | `pugixml` 558.47 | 7.716 | PASS |
| `synthetic_mixed_content.xml` | 2087.17 | `pugixml` 497.66 | 4.194 | PASS |
| `synthetic_small_records.xml` | 1702.29 | `pugixml` 389.86 | 4.366 | PASS |
| `synthetic_tiny_empty.xml` | 1651.12 | `pugixml` 182.92 | 9.027 | PASS |
| `synthetic_tiny_text.xml` | 1702.34 | `pugixml` 167.13 | 10.186 | PASS |
| `synthetic_one_attr.xml` | 3469.50 | `pugixml` 253.16 | 13.705 | PASS |
| `synthetic_two_attr.xml` | 5560.88 | `pugixml` 286.78 | 19.391 | PASS |
| `synthetic_attrs4.xml` | 9006.86 | `pugixml` 313.52 | 28.729 | PASS |
| `synthetic_attrs8.xml` | 13770.39 | `pugixml` 335.59 | 41.033 | PASS |
| `synthetic_single_quotes.xml` | 10456.10 | `pugixml` 460.49 | 22.706 | PASS |
| `synthetic_unicode_names.xml` | 8907.67 | `pugixml` 598.52 | 14.883 | PASS |
| `synthetic_pretty_indented.xml` | 1768.50 | `pugixml` 454.61 | 3.890 | PASS |
| `synthetic_crlf_pretty.xml` | 1938.79 | `pugixml` 492.07 | 3.940 | PASS |
| `synthetic_token_whitespace_mix.xml` | 9736.01 | `pugixml` 422.24 | 23.058 | PASS |
| `synthetic_attr_count_mix.xml` | 6382.11 | `pugixml` 379.27 | 16.827 | PASS |

### Streaming Comparison (Advisory)

| Fixture | stream-permissive | ours-permissive | stream/ours | stream-validated | ours-validated | stream/ours |
|---|---:|---:|---:|---:|---:|---:|
| `note.xml` | 3060.98 | 2710.53 | 1.129 | 1344.83 | 1616.38 | 0.832 |
| `sitemaps.xml` | 3349.58 | 3926.92 | 0.853 | 1680.71 | 1872.14 | 0.898 |
| `plant_catalog.xml` | 3066.48 | 3498.65 | 0.876 | 1485.97 | 1772.09 | 0.839 |
| `cd_catalog.xml` | 2629.61 | 2956.39 | 0.889 | 1271.72 | 1583.38 | 0.803 |
| `hnrss.xml` | 7787.92 | 9446.27 | 0.824 | 4260.97 | 5328.87 | 0.800 |
| `xkcd_rss.xml` | 8037.94 | 4758.08 | 1.689 | 2621.26 | 2949.57 | 0.889 |
| `bbc_world.xml` | 5290.96 | 5898.02 | 0.897 | 3055.91 | 3284.26 | 0.930 |
| `arxiv_cs.xml` | 10243.43 | 8205.69 | 1.248 | 4293.52 | 4033.72 | 1.064 |
| `ecb_usd.xml` | 5603.35 | 6375.85 | 0.879 | 2605.24 | 3010.40 | 0.865 |
| `tree.xml` | 2877.49 | 2801.74 | 1.027 | 1277.34 | 1328.39 | 0.962 |
| `character.xml` | 3140.07 | 3298.52 | 0.952 | 1433.36 | 1403.29 | 1.021 |
| `xgconsole.xml` | 5840.93 | 5798.87 | 1.007 | 1268.85 | 1888.62 | 0.672 |
| `weekly_utf8.xml` | 3074.62 | 3691.60 | 0.833 | 658.97 | 1221.94 | 0.539 |
| `pugixml_large.xml` | 2028.36 | 2415.13 | 0.840 | 1549.74 | 1370.61 | 1.131 |
| `synthetic_flat_attrs.xml` | 8414.90 | 6374.20 | 1.320 | 1298.43 | 1223.95 | 1.061 |
| `synthetic_deep_tree.xml` | 1628.88 | 1773.64 | 0.918 | 1001.26 | 1051.91 | 0.952 |
| `synthetic_entities.xml` | 41964.96 | 10571.02 | 3.970 | 41611.67 | 10428.11 | 3.990 |
| `synthetic_cdata_mix.xml` | 2574.32 | 2136.64 | 1.205 | 1608.85 | 1596.07 | 1.008 |
| `synthetic_wide_siblings.xml` | 2056.20 | 1440.51 | 1.427 | 1061.09 | 1011.26 | 1.049 |
| `synthetic_namespace_mix.xml` | 3949.04 | 3519.19 | 1.122 | 1318.95 | 1337.48 | 0.986 |
| `synthetic_long_names.xml` | 5518.16 | 6043.50 | 0.913 | 2378.72 | 2980.36 | 0.798 |
| `synthetic_self_closing_swarm.xml` | 4972.03 | 4309.13 | 1.154 | 1216.55 | 1130.58 | 1.076 |
| `synthetic_mixed_content.xml` | 2863.52 | 2087.17 | 1.372 | 1271.50 | 1280.35 | 0.993 |
| `synthetic_small_records.xml` | 2349.05 | 1702.29 | 1.380 | 1180.37 | 1211.99 | 0.974 |
| `synthetic_tiny_empty.xml` | 6770.80 | 1651.12 | 4.101 | 6749.94 | 1636.55 | 4.124 |
| `synthetic_tiny_text.xml` | 16961.26 | 1702.34 | 9.963 | 17327.74 | 1653.13 | 10.482 |
| `synthetic_one_attr.xml` | 14133.84 | 3469.50 | 4.074 | 14103.14 | 3455.75 | 4.081 |
| `synthetic_two_attr.xml` | 20242.09 | 5560.88 | 3.640 | 20324.03 | 5482.92 | 3.707 |
| `synthetic_attrs4.xml` | 27617.51 | 9006.86 | 3.066 | 27480.11 | 8886.57 | 3.092 |
| `synthetic_attrs8.xml` | 34460.84 | 13770.39 | 2.503 | 34419.69 | 13906.16 | 2.475 |
| `synthetic_single_quotes.xml` | 30381.89 | 10456.10 | 2.906 | 29786.20 | 10301.90 | 2.891 |
| `synthetic_unicode_names.xml` | 41273.02 | 8907.67 | 4.633 | 40805.38 | 8867.61 | 4.602 |
| `synthetic_pretty_indented.xml` | 2103.01 | 1768.50 | 1.189 | 1275.17 | 1257.41 | 1.014 |
| `synthetic_crlf_pretty.xml` | 2774.32 | 1938.79 | 1.431 | 1320.77 | 1158.09 | 1.140 |
| `synthetic_token_whitespace_mix.xml` | 28132.67 | 9736.01 | 2.890 | 28097.93 | 9771.83 | 2.875 |
| `synthetic_attr_count_mix.xml` | 8592.25 | 6382.11 | 1.346 | 1408.88 | 1359.85 | 1.036 |

For the full terminal-style report:
- `bench/results/latest.md`
- `bench/results/latest.json`
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
