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
# full benchmark: 24 headline + 13 synthetic regression fixtures
zig build bench-compare

# publication-grade benchmark with the same 24 + 13 split
zig build bench-compare -- --profile stable
zig build bench-interleaved -- ../zxml-base ../zxml-candidate --profile quick --repeats 9 --core-a 0 --core-b 2
zig build conformance

# direct tool invocation after setup, when needed
zig build tools -- run-benchmarks --profile quick
zig build tools -- run-benchmarks --profile full
zig build tools -- run-benchmarks --profile stable
zig-out/bin/zxml-tools run-benchmarks --profile stable --no-build --guard-fixtures
```

`full` and `stable` cover 24 headline fixtures plus 13 mandatory synthetic-regression fixtures, and compute the same headline external, synthetic-regression, and validated-pathology comparisons. `full` is the default developer profile: three samples targeted at 5 ms each, scaled-down calibration hints, and reuse of an in-range calibration measurement as sample 1. `stable` remains the publication profile: five independent samples targeted at 40 ms each. Both profiles report gate misses as `FAIL` results rather than tool errors; only a fully passing stable run updates the published README snapshots. `quick` keeps its smaller fixture subset.

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
| CPU frequency scaling | 47% |
| CPU MHz range | 400.0000–4400.0000 |
| Zig | 0.16.0 (`ReleaseFast -Dcpu=native`) |
| C++ driver | c++ (`-O3 -DNDEBUG -march=native`) |

### Parse Throughput Comparison (MiB/s)

| Fixture | ours-permissive | ours-validated | stream-permissive | stream-validated | pugixml | rapidxml |
|---|---:|---:|---:|---:|---:|---:|
| `note.xml` | 2802.99 | 1650.37 | 3165.11 | 1362.65 | 944.23 | 1710.93 |
| `sitemaps.xml` | 4101.84 | 2036.69 | 3573.09 | 1740.36 | 1974.59 | 2017.44 |
| `plant_catalog.xml` | 3481.61 | 1705.50 | 3055.86 | 1372.40 | 1471.49 | 1560.99 |
| `cd_catalog.xml` | 3271.40 | 1672.17 | 2744.52 | 1368.11 | 1420.96 | 1572.07 |
| `hnrss.xml` | 9668.42 | 5384.51 | 8449.01 | 4301.07 | 2916.30 | 2600.42 |
| `xkcd_rss.xml` | 8366.37 | 3999.84 | 8425.40 | 3353.36 | 2042.62 | 2574.45 |
| `bbc_world.xml` | 5940.00 | 3356.84 | 5355.02 | 3162.44 | 2590.99 | 2500.23 |
| `arxiv_cs.xml` | 8397.32 | 4140.77 | 10359.37 | 4461.78 | 2625.27 | 1843.41 |
| `ecb_usd.xml` | 6521.50 | 3114.72 | 5888.88 | 2751.61 | 2664.57 | 2663.92 |
| `tree.xml` | 2996.42 | 1426.45 | 2990.02 | 1329.29 | 1236.79 | 2044.61 |
| `character.xml` | 3316.56 | 1422.39 | 3202.66 | 1432.67 | 1134.51 | 2019.61 |
| `transitions.xml` | 3538.62 | - | 3213.94 | - | 1369.08 | 2159.92 |
| `xgconsole.xml` | 5842.04 | 1927.04 | 5832.01 | 1279.46 | 1828.42 | 2412.94 |
| `weekly_utf8.xml` | 3633.24 | 1218.10 | 3088.15 | 665.27 | 2151.54 | 2332.82 |
| `pugixml_large.xml` | 2560.26 | 1435.62 | 2013.20 | 1621.66 | 473.25 | 300.14 |
| `synthetic_deep_tree.xml` | 1840.90 | 1124.84 | 1728.09 | 1056.93 | 1259.10 | 756.76 |
| `synthetic_cdata_mix.xml` | 2307.92 | 1705.25 | 2783.01 | 1728.85 | 669.92 | 517.66 |
| `synthetic_wide_siblings.xml` | 1509.88 | 1078.86 | 2170.45 | 1065.07 | 429.62 | 318.78 |
| `synthetic_mixed_content.xml` | 2200.81 | 1332.39 | 2996.76 | 1321.31 | 528.42 | 396.35 |
| `synthetic_small_records.xml` | 1748.93 | 1345.19 | 2642.90 | 1283.69 | 430.80 | 301.51 |
| `synthetic_tiny_empty.xml` | 1628.65 | 1627.16 | 6998.98 | 7017.19 | 183.36 | 113.81 |
| `synthetic_tiny_text.xml` | 1719.21 | 1699.57 | 16997.85 | 16969.73 | 176.77 | 117.90 |
| `synthetic_pretty_indented.xml` | 1848.85 | 1280.49 | 2163.61 | 1305.03 | 480.67 | 384.56 |
| `synthetic_crlf_pretty.xml` | 1941.77 | 1169.02 | 2786.91 | 1341.92 | 504.56 | 414.48 |

### Synthetic Regression Fixtures (Excluded From Headline Means)

| Fixture | ours-permissive | ours-validated | stream-permissive | stream-validated | pugixml | rapidxml |
|---|---:|---:|---:|---:|---:|---:|
| `synthetic_token_whitespace_mix.xml` | 9696.10 | 9470.30 | 28637.42 | 28501.03 | 425.43 | 335.83 |
| `synthetic_attr_count_mix.xml` | 6486.76 | 1353.29 | 8576.56 | 1400.55 | 369.58 | 288.80 |
| `synthetic_one_attr.xml` | 3595.14 | 3646.61 | 14909.00 | 14870.66 | 266.31 | 180.03 |
| `synthetic_two_attr.xml` | 5609.10 | 5613.87 | 20141.71 | 20337.67 | 295.14 | 209.21 |
| `synthetic_attrs4.xml` | 9022.85 | 9023.75 | 27962.03 | 27825.19 | 319.84 | 238.06 |
| `synthetic_attrs8.xml` | 14357.04 | 14163.34 | 36084.41 | 35767.22 | 336.80 | 255.89 |
| `synthetic_single_quotes.xml` | 11005.11 | 10884.39 | 31102.06 | 30905.01 | 492.19 | 378.68 |
| `synthetic_unicode_names.xml` | 9075.71 | 8985.15 | 41853.92 | 41670.41 | 618.88 | 527.13 |
| `synthetic_self_closing_swarm.xml` | 4380.22 | 1132.17 | 5106.80 | 1259.37 | 545.74 | 439.86 |
| `synthetic_long_names.xml` | 6329.52 | 3160.07 | 5834.46 | 2482.50 | 1322.08 | 1574.03 |
| `synthetic_namespace_mix.xml` | 3650.98 | 1398.11 | 4230.24 | 1408.00 | 661.60 | 543.84 |
| `synthetic_entities.xml` | 11160.92 | 11147.61 | 44613.03 | 44103.58 | 880.65 | 895.57 |
| `synthetic_flat_attrs.xml` | 6216.80 | 1142.63 | 7970.14 | 1242.38 | 416.71 | 330.21 |

Synthetic regression gate: **13/13 PASS, 0 FAIL**.

### External Parser Gates

| Fixture | ours-permissive | best external | ours/best-ext | Result |
|---|---:|---|---:|---|
| `note.xml` | 2802.99 | `rapidxml` 1710.93 | 1.638 | PASS |
| `sitemaps.xml` | 4101.84 | `rapidxml` 2017.44 | 2.033 | PASS |
| `plant_catalog.xml` | 3481.61 | `rapidxml` 1560.99 | 2.230 | PASS |
| `cd_catalog.xml` | 3271.40 | `rapidxml` 1572.07 | 2.081 | PASS |
| `hnrss.xml` | 9668.42 | `pugixml` 2916.30 | 3.315 | PASS |
| `xkcd_rss.xml` | 8366.37 | `rapidxml` 2574.45 | 3.250 | PASS |
| `bbc_world.xml` | 5940.00 | `pugixml` 2590.99 | 2.293 | PASS |
| `arxiv_cs.xml` | 8397.32 | `pugixml` 2625.27 | 3.199 | PASS |
| `ecb_usd.xml` | 6521.50 | `pugixml` 2664.57 | 2.447 | PASS |
| `tree.xml` | 2996.42 | `rapidxml` 2044.61 | 1.466 | PASS |
| `character.xml` | 3316.56 | `rapidxml` 2019.61 | 1.642 | PASS |
| `transitions.xml` | 3538.62 | `rapidxml` 2159.92 | 1.638 | PASS |
| `xgconsole.xml` | 5842.04 | `rapidxml` 2412.94 | 2.421 | PASS |
| `weekly_utf8.xml` | 3633.24 | `rapidxml` 2332.82 | 1.557 | PASS |
| `pugixml_large.xml` | 2560.26 | `pugixml` 473.25 | 5.410 | PASS |
| `synthetic_deep_tree.xml` | 1840.90 | `pugixml` 1259.10 | 1.462 | PASS |
| `synthetic_cdata_mix.xml` | 2307.92 | `pugixml` 669.92 | 3.445 | PASS |
| `synthetic_wide_siblings.xml` | 1509.88 | `pugixml` 429.62 | 3.514 | PASS |
| `synthetic_mixed_content.xml` | 2200.81 | `pugixml` 528.42 | 4.165 | PASS |
| `synthetic_small_records.xml` | 1748.93 | `pugixml` 430.80 | 4.060 | PASS |
| `synthetic_tiny_empty.xml` | 1628.65 | `pugixml` 183.36 | 8.882 | PASS |
| `synthetic_tiny_text.xml` | 1719.21 | `pugixml` 176.77 | 9.726 | PASS |
| `synthetic_pretty_indented.xml` | 1848.85 | `pugixml` 480.67 | 3.846 | PASS |
| `synthetic_crlf_pretty.xml` | 1941.77 | `pugixml` 504.56 | 3.848 | PASS |

### Streaming Comparison (Advisory)

| Fixture | stream-permissive | ours-permissive | stream/ours | stream-validated | ours-validated | stream/ours |
|---|---:|---:|---:|---:|---:|---:|
| `note.xml` | 3165.11 | 2802.99 | 1.129 | 1362.65 | 1650.37 | 0.826 |
| `sitemaps.xml` | 3573.09 | 4101.84 | 0.871 | 1740.36 | 2036.69 | 0.855 |
| `plant_catalog.xml` | 3055.86 | 3481.61 | 0.878 | 1372.40 | 1705.50 | 0.805 |
| `cd_catalog.xml` | 2744.52 | 3271.40 | 0.839 | 1368.11 | 1672.17 | 0.818 |
| `hnrss.xml` | 8449.01 | 9668.42 | 0.874 | 4301.07 | 5384.51 | 0.799 |
| `xkcd_rss.xml` | 8425.40 | 8366.37 | 1.007 | 3353.36 | 3999.84 | 0.838 |
| `bbc_world.xml` | 5355.02 | 5940.00 | 0.902 | 3162.44 | 3356.84 | 0.942 |
| `arxiv_cs.xml` | 10359.37 | 8397.32 | 1.234 | 4461.78 | 4140.77 | 1.078 |
| `ecb_usd.xml` | 5888.88 | 6521.50 | 0.903 | 2751.61 | 3114.72 | 0.883 |
| `tree.xml` | 2990.02 | 2996.42 | 0.998 | 1329.29 | 1426.45 | 0.932 |
| `character.xml` | 3202.66 | 3316.56 | 0.966 | 1432.67 | 1422.39 | 1.007 |
| `xgconsole.xml` | 5832.01 | 5842.04 | 0.998 | 1279.46 | 1927.04 | 0.664 |
| `weekly_utf8.xml` | 3088.15 | 3633.24 | 0.850 | 665.27 | 1218.10 | 0.546 |
| `pugixml_large.xml` | 2013.20 | 2560.26 | 0.786 | 1621.66 | 1435.62 | 1.130 |
| `synthetic_deep_tree.xml` | 1728.09 | 1840.90 | 0.939 | 1056.93 | 1124.84 | 0.940 |
| `synthetic_cdata_mix.xml` | 2783.01 | 2307.92 | 1.206 | 1728.85 | 1705.25 | 1.014 |
| `synthetic_wide_siblings.xml` | 2170.45 | 1509.88 | 1.437 | 1065.07 | 1078.86 | 0.987 |
| `synthetic_mixed_content.xml` | 2996.76 | 2200.81 | 1.362 | 1321.31 | 1332.39 | 0.992 |
| `synthetic_small_records.xml` | 2642.90 | 1748.93 | 1.511 | 1283.69 | 1345.19 | 0.954 |
| `synthetic_tiny_empty.xml` | 6998.98 | 1628.65 | 4.297 | 7017.19 | 1627.16 | 4.313 |
| `synthetic_tiny_text.xml` | 16997.85 | 1719.21 | 9.887 | 16969.73 | 1699.57 | 9.985 |
| `synthetic_pretty_indented.xml` | 2163.61 | 1848.85 | 1.170 | 1305.03 | 1280.49 | 1.019 |
| `synthetic_crlf_pretty.xml` | 2786.91 | 1941.77 | 1.435 | 1341.92 | 1169.02 | 1.148 |

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
