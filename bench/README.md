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

`full` and `stable` cover the same 37 headline fixtures and compute the same external and validated-pathology comparisons. `full` is the default developer profile: three samples targeted at 5 ms each, scaled-down calibration hints, and reuse of an in-range calibration measurement as sample 1. `stable` remains the publication profile: five independent samples targeted at 40 ms each and hard-fails its gates. `full` reports gate failures but does not make them fatal because its short samples are intended for fast feedback. `quick` keeps its smaller fixture subset.

Developer profiles also reuse already-built pugixml/rapidxml runners when their runner sources and parser headers are older than the binaries. `stable` always rebuilds both external runners so publication evidence never depends on a stale C++ artifact.

A successful `stable` run also updates:

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
| CPU frequency scaling | 25% |
| CPU MHz range | 400.0000–4400.0000 |
| Zig | 0.16.0 (`ReleaseFast -Dcpu=native`) |
| C++ driver | c++ (`-O3 -DNDEBUG -march=native`) |

### Parse Throughput Comparison (MB/s)

| Fixture | ours-permissive | ours-validated | stream-permissive | stream-validated | pugixml | rapidxml |
|---|---:|---:|---:|---:|---:|---:|
| `note.xml` | 2876.74 | 1671.65 | 3282.15 | 1392.80 | 977.97 | 1773.58 |
| `sitemaps.xml` | 4223.02 | 2128.56 | 3720.77 | 1802.19 | 2067.23 | 2101.88 |
| `plant_catalog.xml` | 3624.58 | 1866.88 | 3215.44 | 1529.97 | 1574.25 | 1680.87 |
| `cd_catalog.xml` | 3255.46 | 1736.88 | 2810.06 | 1407.95 | 1503.05 | 1656.73 |
| `hnrss.xml` | 9970.37 | 5510.29 | 8570.10 | 4432.99 | 2984.76 | 2722.01 |
| `xkcd_rss.xml` | 8670.15 | 4106.10 | 8792.88 | 3439.53 | 2530.09 | 2650.42 |
| `bbc_world.xml` | 5957.65 | 3459.30 | 5433.30 | 3144.30 | 2628.28 | 2561.22 |
| `arxiv_cs.xml` | 8451.59 | 4158.79 | 10686.52 | 4577.96 | 2733.14 | 1897.48 |
| `ecb_usd.xml` | 6813.26 | 3207.87 | 6032.57 | 2859.11 | 2705.87 | 2751.16 |
| `tree.xml` | 2977.17 | 1465.52 | 3109.66 | 1368.22 | 1275.77 | 2105.11 |
| `character.xml` | 3498.75 | 1477.28 | 3293.65 | 1437.93 | 1181.24 | 2132.49 |
| `transitions.xml` | 3726.03 | - | 3408.92 | - | 1472.48 | 2268.62 |
| `xgconsole.xml` | 6011.79 | 2012.75 | 6078.22 | 1334.16 | 1895.04 | 2492.48 |
| `weekly_utf8.xml` | 3828.66 | 1272.68 | 3160.34 | 691.95 | 2248.38 | 2435.64 |
| `pugixml_large.xml` | 2567.86 | 1489.42 | 2113.79 | 1677.26 | 481.54 | 308.00 |
| `synthetic_flat_attrs.xml` | 6787.72 | 1329.41 | 8721.19 | 1235.85 | 467.18 | 351.47 |
| `synthetic_deep_tree.xml` | 1905.42 | 1163.96 | 1768.84 | 1113.43 | 1283.16 | 777.19 |
| `synthetic_entities.xml` | 10451.86 | 10244.35 | 31495.76 | 31127.85 | 919.99 | 930.96 |
| `synthetic_cdata_mix.xml` | 2361.87 | 1783.06 | 2889.12 | 1824.68 | 690.78 | 525.21 |
| `synthetic_wide_siblings.xml` | 1552.51 | 1129.72 | 2251.36 | 1126.05 | 430.08 | 316.79 |
| `synthetic_namespace_mix.xml` | 3785.66 | 1452.84 | 4411.76 | 1484.34 | 700.09 | 577.30 |
| `synthetic_long_names.xml` | 6430.58 | 3271.51 | 6204.73 | 2596.65 | 1392.15 | 1654.52 |
| `synthetic_self_closing_swarm.xml` | 4670.28 | 1157.32 | 5471.68 | 1354.86 | 574.86 | 460.87 |
| `synthetic_mixed_content.xml` | 2306.95 | 1362.48 | 3130.30 | 1392.69 | 524.03 | 396.20 |
| `synthetic_small_records.xml` | 1916.97 | 1378.95 | 2783.71 | 1344.09 | 425.77 | 301.11 |
| `synthetic_tiny_empty.xml` | 1732.05 | 1720.05 | 7416.80 | 7394.28 | 192.12 | 120.16 |
| `synthetic_tiny_text.xml` | 1763.30 | 1749.24 | 15198.86 | 15133.66 | 181.29 | 123.27 |
| `synthetic_one_attr.xml` | 2990.51 | 2960.46 | 10505.99 | 10437.36 | 236.77 | 161.82 |
| `synthetic_two_attr.xml` | 5461.72 | 5449.06 | 16997.02 | 16705.59 | 290.06 | 213.50 |
| `synthetic_attrs4.xml` | 8574.21 | 8540.75 | 21832.56 | 21886.81 | 329.26 | 253.57 |
| `synthetic_attrs8.xml` | 12609.67 | 12372.73 | 25994.73 | 26089.28 | 350.26 | 266.27 |
| `synthetic_single_quotes.xml` | 9786.17 | 9816.82 | 23297.40 | 23385.45 | 489.95 | 375.99 |
| `synthetic_unicode_names.xml` | 8592.19 | 8489.89 | 29237.23 | 29101.26 | 642.70 | 544.00 |
| `synthetic_pretty_indented.xml` | 1932.42 | 1346.93 | 2271.95 | 1346.08 | 497.21 | 400.80 |
| `synthetic_crlf_pretty.xml` | 2031.23 | 1222.65 | 2932.27 | 1415.76 | 524.77 | 437.24 |
| `synthetic_token_whitespace_mix.xml` | 9022.22 | 8904.10 | 21260.64 | 21278.67 | 437.93 | 363.87 |
| `synthetic_attr_count_mix.xml` | 6628.53 | 1419.09 | 8960.68 | 1484.03 | 394.33 | 310.12 |

### External Parser Gates

| Fixture | ours-permissive | best external | ours/best-ext | Result |
|---|---:|---|---:|---|
| `note.xml` | 2876.74 | `rapidxml` 1773.58 | 1.622 | PASS |
| `sitemaps.xml` | 4223.02 | `rapidxml` 2101.88 | 2.009 | PASS |
| `plant_catalog.xml` | 3624.58 | `rapidxml` 1680.87 | 2.156 | PASS |
| `cd_catalog.xml` | 3255.46 | `rapidxml` 1656.73 | 1.965 | PASS |
| `hnrss.xml` | 9970.37 | `pugixml` 2984.76 | 3.340 | PASS |
| `xkcd_rss.xml` | 8670.15 | `rapidxml` 2650.42 | 3.271 | PASS |
| `bbc_world.xml` | 5957.65 | `pugixml` 2628.28 | 2.267 | PASS |
| `arxiv_cs.xml` | 8451.59 | `pugixml` 2733.14 | 3.092 | PASS |
| `ecb_usd.xml` | 6813.26 | `rapidxml` 2751.16 | 2.477 | PASS |
| `tree.xml` | 2977.17 | `rapidxml` 2105.11 | 1.414 | PASS |
| `character.xml` | 3498.75 | `rapidxml` 2132.49 | 1.641 | PASS |
| `transitions.xml` | 3726.03 | `rapidxml` 2268.62 | 1.642 | PASS |
| `xgconsole.xml` | 6011.79 | `rapidxml` 2492.48 | 2.412 | PASS |
| `weekly_utf8.xml` | 3828.66 | `rapidxml` 2435.64 | 1.572 | PASS |
| `pugixml_large.xml` | 2567.86 | `pugixml` 481.54 | 5.333 | PASS |
| `synthetic_flat_attrs.xml` | 6787.72 | `pugixml` 467.18 | 14.529 | PASS |
| `synthetic_deep_tree.xml` | 1905.42 | `pugixml` 1283.16 | 1.485 | PASS |
| `synthetic_entities.xml` | 10451.86 | `rapidxml` 930.96 | 11.227 | PASS |
| `synthetic_cdata_mix.xml` | 2361.87 | `pugixml` 690.78 | 3.419 | PASS |
| `synthetic_wide_siblings.xml` | 1552.51 | `pugixml` 430.08 | 3.610 | PASS |
| `synthetic_namespace_mix.xml` | 3785.66 | `pugixml` 700.09 | 5.407 | PASS |
| `synthetic_long_names.xml` | 6430.58 | `rapidxml` 1654.52 | 3.887 | PASS |
| `synthetic_self_closing_swarm.xml` | 4670.28 | `pugixml` 574.86 | 8.124 | PASS |
| `synthetic_mixed_content.xml` | 2306.95 | `pugixml` 524.03 | 4.402 | PASS |
| `synthetic_small_records.xml` | 1916.97 | `pugixml` 425.77 | 4.502 | PASS |
| `synthetic_tiny_empty.xml` | 1732.05 | `pugixml` 192.12 | 9.015 | PASS |
| `synthetic_tiny_text.xml` | 1763.30 | `pugixml` 181.29 | 9.727 | PASS |
| `synthetic_one_attr.xml` | 2990.51 | `pugixml` 236.77 | 12.630 | PASS |
| `synthetic_two_attr.xml` | 5461.72 | `pugixml` 290.06 | 18.829 | PASS |
| `synthetic_attrs4.xml` | 8574.21 | `pugixml` 329.26 | 26.041 | PASS |
| `synthetic_attrs8.xml` | 12609.67 | `pugixml` 350.26 | 36.001 | PASS |
| `synthetic_single_quotes.xml` | 9786.17 | `pugixml` 489.95 | 19.974 | PASS |
| `synthetic_unicode_names.xml` | 8592.19 | `pugixml` 642.70 | 13.369 | PASS |
| `synthetic_pretty_indented.xml` | 1932.42 | `pugixml` 497.21 | 3.887 | PASS |
| `synthetic_crlf_pretty.xml` | 2031.23 | `pugixml` 524.77 | 3.871 | PASS |
| `synthetic_token_whitespace_mix.xml` | 9022.22 | `pugixml` 437.93 | 20.602 | PASS |
| `synthetic_attr_count_mix.xml` | 6628.53 | `pugixml` 394.33 | 16.810 | PASS |

### Streaming Comparison (Advisory)

| Fixture | stream-permissive | ours-permissive | stream/ours | stream-validated | ours-validated | stream/ours |
|---|---:|---:|---:|---:|---:|---:|
| `note.xml` | 3282.15 | 2876.74 | 1.141 | 1392.80 | 1671.65 | 0.833 |
| `sitemaps.xml` | 3720.77 | 4223.02 | 0.881 | 1802.19 | 2128.56 | 0.847 |
| `plant_catalog.xml` | 3215.44 | 3624.58 | 0.887 | 1529.97 | 1866.88 | 0.820 |
| `cd_catalog.xml` | 2810.06 | 3255.46 | 0.863 | 1407.95 | 1736.88 | 0.811 |
| `hnrss.xml` | 8570.10 | 9970.37 | 0.860 | 4432.99 | 5510.29 | 0.804 |
| `xkcd_rss.xml` | 8792.88 | 8670.15 | 1.014 | 3439.53 | 4106.10 | 0.838 |
| `bbc_world.xml` | 5433.30 | 5957.65 | 0.912 | 3144.30 | 3459.30 | 0.909 |
| `arxiv_cs.xml` | 10686.52 | 8451.59 | 1.264 | 4577.96 | 4158.79 | 1.101 |
| `ecb_usd.xml` | 6032.57 | 6813.26 | 0.885 | 2859.11 | 3207.87 | 0.891 |
| `tree.xml` | 3109.66 | 2977.17 | 1.044 | 1368.22 | 1465.52 | 0.934 |
| `character.xml` | 3293.65 | 3498.75 | 0.941 | 1437.93 | 1477.28 | 0.973 |
| `xgconsole.xml` | 6078.22 | 6011.79 | 1.011 | 1334.16 | 2012.75 | 0.663 |
| `weekly_utf8.xml` | 3160.34 | 3828.66 | 0.825 | 691.95 | 1272.68 | 0.544 |
| `pugixml_large.xml` | 2113.79 | 2567.86 | 0.823 | 1677.26 | 1489.42 | 1.126 |
| `synthetic_flat_attrs.xml` | 8721.19 | 6787.72 | 1.285 | 1235.85 | 1329.41 | 0.930 |
| `synthetic_deep_tree.xml` | 1768.84 | 1905.42 | 0.928 | 1113.43 | 1163.96 | 0.957 |
| `synthetic_entities.xml` | 31495.76 | 10451.86 | 3.013 | 31127.85 | 10244.35 | 3.039 |
| `synthetic_cdata_mix.xml` | 2889.12 | 2361.87 | 1.223 | 1824.68 | 1783.06 | 1.023 |
| `synthetic_wide_siblings.xml` | 2251.36 | 1552.51 | 1.450 | 1126.05 | 1129.72 | 0.997 |
| `synthetic_namespace_mix.xml` | 4411.76 | 3785.66 | 1.165 | 1484.34 | 1452.84 | 1.022 |
| `synthetic_long_names.xml` | 6204.73 | 6430.58 | 0.965 | 2596.65 | 3271.51 | 0.794 |
| `synthetic_self_closing_swarm.xml` | 5471.68 | 4670.28 | 1.172 | 1354.86 | 1157.32 | 1.171 |
| `synthetic_mixed_content.xml` | 3130.30 | 2306.95 | 1.357 | 1392.69 | 1362.48 | 1.022 |
| `synthetic_small_records.xml` | 2783.71 | 1916.97 | 1.452 | 1344.09 | 1378.95 | 0.975 |
| `synthetic_tiny_empty.xml` | 7416.80 | 1732.05 | 4.282 | 7394.28 | 1720.05 | 4.299 |
| `synthetic_tiny_text.xml` | 15198.86 | 1763.30 | 8.620 | 15133.66 | 1749.24 | 8.652 |
| `synthetic_one_attr.xml` | 10505.99 | 2990.51 | 3.513 | 10437.36 | 2960.46 | 3.526 |
| `synthetic_two_attr.xml` | 16997.02 | 5461.72 | 3.112 | 16705.59 | 5449.06 | 3.066 |
| `synthetic_attrs4.xml` | 21832.56 | 8574.21 | 2.546 | 21886.81 | 8540.75 | 2.563 |
| `synthetic_attrs8.xml` | 25994.73 | 12609.67 | 2.061 | 26089.28 | 12372.73 | 2.109 |
| `synthetic_single_quotes.xml` | 23297.40 | 9786.17 | 2.381 | 23385.45 | 9816.82 | 2.382 |
| `synthetic_unicode_names.xml` | 29237.23 | 8592.19 | 3.403 | 29101.26 | 8489.89 | 3.428 |
| `synthetic_pretty_indented.xml` | 2271.95 | 1932.42 | 1.176 | 1346.08 | 1346.93 | 0.999 |
| `synthetic_crlf_pretty.xml` | 2932.27 | 2031.23 | 1.444 | 1415.76 | 1222.65 | 1.158 |
| `synthetic_token_whitespace_mix.xml` | 21260.64 | 9022.22 | 2.356 | 21278.67 | 8904.10 | 2.390 |
| `synthetic_attr_count_mix.xml` | 8960.68 | 6628.53 | 1.352 | 1484.03 | 1419.09 | 1.046 |

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
