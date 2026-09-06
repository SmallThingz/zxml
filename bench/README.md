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

Source: `bench/results/latest.json` (`stable` profile).

## Latest Benchmark Snapshot

### Benchmark Environment

| Property | Value |
|---|---|
| OS / kernel | Linux 7.2.2-zen1-1-zen |
| Architecture | x86_64 |
| CPU | 12th Gen Intel(R) Core(TM) i5-12450H |
| CPU frequency scaling | 16% |
| CPU MHz range | 400.0000–4400.0000 |
| Zig | 0.16.0 (`ReleaseFast -Dcpu=native`) |
| C++ driver | c++ (`-O3 -DNDEBUG -march=native`) |

### Parse Throughput Comparison (MB/s)

| Fixture | ours-permissive | ours-validated | stream-permissive | stream-validated | pugixml | rapidxml |
|---|---:|---:|---:|---:|---:|---:|
| `note.xml` | 2470.20 | 1556.45 | 3153.76 | 1360.44 | 982.67 | 1766.43 |
| `sitemaps.xml` | 3664.46 | 2013.66 | 3455.77 | 1762.69 | 2062.04 | 2126.97 |
| `plant_catalog.xml` | 3028.51 | 1783.13 | 2817.52 | 1549.65 | 1585.27 | 1768.17 |
| `cd_catalog.xml` | 2741.85 | 1689.79 | 2506.49 | 1422.24 | 1526.03 | 1669.29 |
| `hnrss.xml` | 8379.89 | 5083.19 | 8117.47 | 4330.62 | 3063.40 | 2765.72 |
| `xkcd_rss.xml` | 7699.98 | 4141.70 | 7918.53 | 3366.42 | 2612.82 | 2719.91 |
| `bbc_world.xml` | 5588.52 | 3305.64 | 4993.09 | 3227.11 | 2701.27 | 2616.43 |
| `arxiv_cs.xml` | 7741.99 | 4167.94 | 10095.32 | 4597.24 | 2819.77 | 1997.28 |
| `ecb_usd.xml` | 5918.46 | 3109.24 | 4987.27 | 2835.14 | 2780.86 | 2821.72 |
| `tree.xml` | 2690.63 | 1485.63 | 2746.60 | 1418.38 | 1294.47 | 2102.76 |
| `character.xml` | 2981.11 | 1423.06 | 2569.70 | 1529.35 | 1177.65 | 2127.43 |
| `transitions.xml` | 3235.15 | - | 2476.73 | - | 1492.72 | 2267.66 |
| `xgconsole.xml` | 5452.27 | 1898.90 | 3673.39 | 1327.20 | 1901.26 | 2490.00 |
| `weekly_utf8.xml` | 3653.82 | 793.82 | 3026.56 | 681.17 | 2212.47 | 2405.81 |
| `pugixml_large.xml` | 1268.51 | 999.69 | 2133.40 | 1691.46 | 486.34 | 308.95 |
| `synthetic_flat_attrs.xml` | 6164.92 | 936.66 | 2759.63 | 1004.83 | 480.03 | 380.55 |
| `synthetic_deep_tree.xml` | 1416.82 | 1001.70 | 1565.35 | 1045.37 | 1323.12 | 793.11 |
| `synthetic_entities.xml` | 3832.17 | 860.75 | 5755.89 | 855.09 | 928.03 | 941.28 |
| `synthetic_cdata_mix.xml` | 2125.97 | 1617.19 | 2912.63 | 1771.31 | 696.03 | 533.70 |
| `synthetic_wide_siblings.xml` | 1210.55 | 967.72 | 2388.65 | 1060.51 | 444.53 | 330.91 |
| `synthetic_namespace_mix.xml` | 3146.00 | 1438.08 | 3252.67 | 1514.40 | 705.04 | 584.74 |
| `synthetic_long_names.xml` | 6069.88 | 3191.96 | 4662.10 | 2503.04 | 1392.50 | 1677.29 |
| `synthetic_self_closing_swarm.xml` | 4185.02 | 1248.57 | 3245.10 | 1430.16 | 606.12 | 493.33 |
| `synthetic_mixed_content.xml` | 1921.63 | 1262.73 | 2857.17 | 1341.22 | 550.43 | 406.54 |
| `synthetic_small_records.xml` | 1585.47 | 1278.29 | 2282.02 | 1300.15 | 440.37 | 315.73 |
| `synthetic_tiny_empty.xml` | 1143.06 | 833.43 | 1564.11 | 1291.63 | 200.70 | 121.62 |
| `synthetic_tiny_text.xml` | 781.34 | 820.34 | 1003.50 | 696.63 | 186.71 | 126.87 |
| `synthetic_one_attr.xml` | 1175.24 | 843.21 | 1812.53 | 1083.55 | 291.95 | 196.48 |
| `synthetic_two_attr.xml` | 1836.77 | 894.85 | 1942.02 | 1063.26 | 322.46 | 225.78 |
| `synthetic_attrs4.xml` | 3253.39 | 881.09 | 2293.85 | 977.34 | 347.32 | 258.40 |
| `synthetic_attrs8.xml` | 5168.37 | 823.89 | 2566.50 | 955.51 | 336.71 | 264.11 |
| `synthetic_single_quotes.xml` | 3922.03 | 1157.37 | 3000.92 | 1265.69 | 539.24 | 420.03 |
| `synthetic_unicode_names.xml` | 2724.35 | 540.25 | 3206.28 | 554.06 | 644.29 | 549.13 |
| `synthetic_pretty_indented.xml` | 1561.51 | 1148.22 | 2279.58 | 1277.19 | 519.60 | 409.87 |
| `synthetic_crlf_pretty.xml` | 1679.30 | 1122.21 | 2958.47 | 1275.70 | 530.52 | 441.83 |
| `synthetic_token_whitespace_mix.xml` | 3196.61 | 891.43 | 1673.21 | 984.94 | 457.82 | 372.97 |
| `synthetic_attr_count_mix.xml` | 5635.31 | 971.35 | 2811.76 | 1072.56 | 426.95 | 336.49 |

### Stable Gates

| Fixture | ours-permissive | best external | ours/best-ext | Result |
|---|---:|---|---:|---|
| `note.xml` | 2470.20 | `rapidxml` 1766.43 | 1.398 | PASS |
| `sitemaps.xml` | 3664.46 | `rapidxml` 2126.97 | 1.723 | PASS |
| `plant_catalog.xml` | 3028.51 | `rapidxml` 1768.17 | 1.713 | PASS |
| `cd_catalog.xml` | 2741.85 | `rapidxml` 1669.29 | 1.643 | PASS |
| `hnrss.xml` | 8379.89 | `pugixml` 3063.40 | 2.735 | PASS |
| `xkcd_rss.xml` | 7699.98 | `rapidxml` 2719.91 | 2.831 | PASS |
| `bbc_world.xml` | 5588.52 | `pugixml` 2701.27 | 2.069 | PASS |
| `arxiv_cs.xml` | 7741.99 | `pugixml` 2819.77 | 2.746 | PASS |
| `ecb_usd.xml` | 5918.46 | `rapidxml` 2821.72 | 2.097 | PASS |
| `tree.xml` | 2690.63 | `rapidxml` 2102.76 | 1.280 | PASS |
| `character.xml` | 2981.11 | `rapidxml` 2127.43 | 1.401 | PASS |
| `transitions.xml` | 3235.15 | `rapidxml` 2267.66 | 1.427 | PASS |
| `xgconsole.xml` | 5452.27 | `rapidxml` 2490.00 | 2.190 | PASS |
| `weekly_utf8.xml` | 3653.82 | `rapidxml` 2405.81 | 1.519 | PASS |
| `pugixml_large.xml` | 1268.51 | `pugixml` 486.34 | 2.608 | PASS |
| `synthetic_flat_attrs.xml` | 6164.92 | `pugixml` 480.03 | 12.843 | PASS |
| `synthetic_deep_tree.xml` | 1416.82 | `pugixml` 1323.12 | 1.071 | PASS |
| `synthetic_entities.xml` | 3832.17 | `rapidxml` 941.28 | 4.071 | PASS |
| `synthetic_cdata_mix.xml` | 2125.97 | `pugixml` 696.03 | 3.054 | PASS |
| `synthetic_wide_siblings.xml` | 1210.55 | `pugixml` 444.53 | 2.723 | PASS |
| `synthetic_namespace_mix.xml` | 3146.00 | `pugixml` 705.04 | 4.462 | PASS |
| `synthetic_long_names.xml` | 6069.88 | `rapidxml` 1677.29 | 3.619 | PASS |
| `synthetic_self_closing_swarm.xml` | 4185.02 | `pugixml` 606.12 | 6.905 | PASS |
| `synthetic_mixed_content.xml` | 1921.63 | `pugixml` 550.43 | 3.491 | PASS |
| `synthetic_small_records.xml` | 1585.47 | `pugixml` 440.37 | 3.600 | PASS |
| `synthetic_tiny_empty.xml` | 1143.06 | `pugixml` 200.70 | 5.695 | PASS |
| `synthetic_tiny_text.xml` | 781.34 | `pugixml` 186.71 | 4.185 | PASS |
| `synthetic_one_attr.xml` | 1175.24 | `pugixml` 291.95 | 4.026 | PASS |
| `synthetic_two_attr.xml` | 1836.77 | `pugixml` 322.46 | 5.696 | PASS |
| `synthetic_attrs4.xml` | 3253.39 | `pugixml` 347.32 | 9.367 | PASS |
| `synthetic_attrs8.xml` | 5168.37 | `pugixml` 336.71 | 15.349 | PASS |
| `synthetic_single_quotes.xml` | 3922.03 | `pugixml` 539.24 | 7.273 | PASS |
| `synthetic_unicode_names.xml` | 2724.35 | `pugixml` 644.29 | 4.228 | PASS |
| `synthetic_pretty_indented.xml` | 1561.51 | `pugixml` 519.60 | 3.005 | PASS |
| `synthetic_crlf_pretty.xml` | 1679.30 | `pugixml` 530.52 | 3.165 | PASS |
| `synthetic_token_whitespace_mix.xml` | 3196.61 | `pugixml` 457.82 | 6.982 | PASS |
| `synthetic_attr_count_mix.xml` | 5635.31 | `pugixml` 426.95 | 13.199 | PASS |

### Streaming Comparison (Advisory)

| Fixture | stream-permissive | ours-permissive | stream/ours | stream-validated | ours-validated | stream/ours |
|---|---:|---:|---:|---:|---:|---:|
| `note.xml` | 3153.76 | 2470.20 | 1.277 | 1360.44 | 1556.45 | 0.874 |
| `sitemaps.xml` | 3455.77 | 3664.46 | 0.943 | 1762.69 | 2013.66 | 0.875 |
| `plant_catalog.xml` | 2817.52 | 3028.51 | 0.930 | 1549.65 | 1783.13 | 0.869 |
| `cd_catalog.xml` | 2506.49 | 2741.85 | 0.914 | 1422.24 | 1689.79 | 0.842 |
| `hnrss.xml` | 8117.47 | 8379.89 | 0.969 | 4330.62 | 5083.19 | 0.852 |
| `xkcd_rss.xml` | 7918.53 | 7699.98 | 1.028 | 3366.42 | 4141.70 | 0.813 |
| `bbc_world.xml` | 4993.09 | 5588.52 | 0.893 | 3227.11 | 3305.64 | 0.976 |
| `arxiv_cs.xml` | 10095.32 | 7741.99 | 1.304 | 4597.24 | 4167.94 | 1.103 |
| `ecb_usd.xml` | 4987.27 | 5918.46 | 0.843 | 2835.14 | 3109.24 | 0.912 |
| `tree.xml` | 2746.60 | 2690.63 | 1.021 | 1418.38 | 1485.63 | 0.955 |
| `character.xml` | 2569.70 | 2981.11 | 0.862 | 1529.35 | 1423.06 | 1.075 |
| `xgconsole.xml` | 3673.39 | 5452.27 | 0.674 | 1327.20 | 1898.90 | 0.699 |
| `weekly_utf8.xml` | 3026.56 | 3653.82 | 0.828 | 681.17 | 793.82 | 0.858 |
| `pugixml_large.xml` | 2133.40 | 1268.51 | 1.682 | 1691.46 | 999.69 | 1.692 |
| `synthetic_flat_attrs.xml` | 2759.63 | 6164.92 | 0.448 | 1004.83 | 936.66 | 1.073 |
| `synthetic_deep_tree.xml` | 1565.35 | 1416.82 | 1.105 | 1045.37 | 1001.70 | 1.044 |
| `synthetic_entities.xml` | 5755.89 | 3832.17 | 1.502 | 855.09 | 860.75 | 0.993 |
| `synthetic_cdata_mix.xml` | 2912.63 | 2125.97 | 1.370 | 1771.31 | 1617.19 | 1.095 |
| `synthetic_wide_siblings.xml` | 2388.65 | 1210.55 | 1.973 | 1060.51 | 967.72 | 1.096 |
| `synthetic_namespace_mix.xml` | 3252.67 | 3146.00 | 1.034 | 1514.40 | 1438.08 | 1.053 |
| `synthetic_long_names.xml` | 4662.10 | 6069.88 | 0.768 | 2503.04 | 3191.96 | 0.784 |
| `synthetic_self_closing_swarm.xml` | 3245.10 | 4185.02 | 0.775 | 1430.16 | 1248.57 | 1.145 |
| `synthetic_mixed_content.xml` | 2857.17 | 1921.63 | 1.487 | 1341.22 | 1262.73 | 1.062 |
| `synthetic_small_records.xml` | 2282.02 | 1585.47 | 1.439 | 1300.15 | 1278.29 | 1.017 |
| `synthetic_tiny_empty.xml` | 1564.11 | 1143.06 | 1.368 | 1291.63 | 833.43 | 1.550 |
| `synthetic_tiny_text.xml` | 1003.50 | 781.34 | 1.284 | 696.63 | 820.34 | 0.849 |
| `synthetic_one_attr.xml` | 1812.53 | 1175.24 | 1.542 | 1083.55 | 843.21 | 1.285 |
| `synthetic_two_attr.xml` | 1942.02 | 1836.77 | 1.057 | 1063.26 | 894.85 | 1.188 |
| `synthetic_attrs4.xml` | 2293.85 | 3253.39 | 0.705 | 977.34 | 881.09 | 1.109 |
| `synthetic_attrs8.xml` | 2566.50 | 5168.37 | 0.497 | 955.51 | 823.89 | 1.160 |
| `synthetic_single_quotes.xml` | 3000.92 | 3922.03 | 0.765 | 1265.69 | 1157.37 | 1.094 |
| `synthetic_unicode_names.xml` | 3206.28 | 2724.35 | 1.177 | 554.06 | 540.25 | 1.026 |
| `synthetic_pretty_indented.xml` | 2279.58 | 1561.51 | 1.460 | 1277.19 | 1148.22 | 1.112 |
| `synthetic_crlf_pretty.xml` | 2958.47 | 1679.30 | 1.762 | 1275.70 | 1122.21 | 1.137 |
| `synthetic_token_whitespace_mix.xml` | 1673.21 | 3196.61 | 0.523 | 984.94 | 891.43 | 1.105 |
| `synthetic_attr_count_mix.xml` | 2811.76 | 5635.31 | 0.499 | 1072.56 | 971.35 | 1.104 |

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
