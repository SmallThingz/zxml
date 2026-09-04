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
zig build tools -- run-benchmarks --profile stable --resume
```

`run-benchmarks` also updates:

- `README.md` auto-summary block
- `bench/README.md` latest benchmark snapshot block

Results are written to:

- `bench/results/latest.json`
- `bench/results/latest.md`

Benchmarks build the full DOM, including declaration/comment/CDATA/PI/doctype
nodes. The benchmark workflow follows zhtml. zxml keeps input/setup outside the timed
region and repeatedly resets the same logical `Document`, retaining its internal
node/attribute capacity between parses; streaming likewise reuses its parser
state. External runners use their native repeat-parse lifecycle. zxml runners are
built with `ReleaseFast -Dcpu=native`; C++ runners use `-O3 -DNDEBUG -march=native`.
The harness uses a system `c++` driver when available and falls back to `zig c++`
on minimal hosts. Each generated report records the kernel, architecture, CPU model,
frequency-scaling state, advertised CPU MHz range, Zig version, and C++ driver.

For noisy/shared machines, `--resume` checkpoints only fully completed stable
fixtures in `bench/results/stable.resume.json`. Restarting the same source revision
and benchmark environment skips those completed fixtures; the checkpoint is removed
automatically after the complete stable gate and README publication succeed.

Fixture setup rejects extremely opaque feeds. `synthetic_long_text.xml` remains
a generated diagnostic-only fixture and is excluded from quick/stable profiles.
`synthetic_doctype_entities.xml` is also excluded from headline profiles and
external gates; stable runs exercise it only in the strict-only regression lane.
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
| CPU frequency scaling | 50% |
| CPU MHz range | 400.0000–4400.0000 |
| Zig | 0.16.0 (`ReleaseFast -Dcpu=native`) |
| C++ driver | zig c++ (`-O3 -DNDEBUG -march=native`) |

### Parse Throughput Comparison (MB/s)

| Fixture | ours-turbo | ours-strict | stream-turbo | stream-strict | pugixml | rapidxml |
|---|---:|---:|---:|---:|---:|---:|
| `note.xml` | 2976.49 | 1463.64 | 2946.79 | 1339.16 | 922.59 | 1418.02 |
| `sitemaps.xml` | 3683.65 | 1864.88 | 3699.31 | 1700.21 | 2054.27 | 1779.22 |
| `plant_catalog.xml` | 3038.54 | 1400.10 | 2619.85 | 1443.57 | 1309.14 | 1374.32 |
| `cd_catalog.xml` | 2805.45 | 1389.74 | 2549.84 | 1277.05 | 1477.88 | 1427.99 |
| `hnrss.xml` | 8011.36 | 3752.66 | 8096.25 | 4109.22 | 2676.20 | 2473.02 |
| `xkcd_rss.xml` | 8394.76 | 4034.20 | 8422.88 | 3317.30 | 2464.46 | 2057.80 |
| `bbc_world.xml` | 4938.07 | 3070.13 | 5422.98 | 2948.31 | 2693.20 | 2228.70 |
| `arxiv_cs.xml` | 9727.18 | 4111.78 | 9682.07 | 4018.66 | 2312.68 | 1653.52 |
| `ecb_usd.xml` | 5016.33 | 2993.33 | 4699.35 | 2752.48 | 2616.72 | 2111.76 |
| `tree.xml` | 2326.47 | 1209.70 | 2892.09 | 1317.84 | 1136.33 | 1564.97 |
| `character.xml` | 2605.15 | 1321.06 | 2558.39 | 1311.06 | 1120.71 | 1700.49 |
| `transitions.xml` | 2151.95 | - | 2819.54 | - | 1471.84 | 1833.42 |
| `xgconsole.xml` | 3035.83 | 1649.65 | 3741.27 | 1281.15 | 1723.78 | 2011.21 |
| `weekly_utf8.xml` | 3078.29 | 522.71 | 3635.69 | 570.60 | 2129.02 | 2210.43 |
| `pugixml_large.xml` | 2308.05 | 1666.46 | 2453.68 | 1695.42 | 489.89 | 314.74 |
| `synthetic_flat_attrs.xml` | 1479.37 | 889.50 | 2484.98 | 939.38 | 426.65 | 377.10 |
| `synthetic_deep_tree.xml` | 1415.72 | 946.44 | 1767.55 | 908.02 | 1283.53 | 531.37 |
| `synthetic_entities.xml` | 4649.04 | 985.40 | 5293.71 | 922.18 | 918.55 | 811.71 |
| `synthetic_cdata_mix.xml` | 2606.41 | 2072.32 | 2478.22 | 1720.52 | 633.04 | 521.01 |
| `synthetic_wide_siblings.xml` | 2014.12 | 1181.64 | 2207.37 | 1038.19 | 420.47 | 318.61 |
| `synthetic_namespace_mix.xml` | 2911.27 | 1449.29 | 3428.15 | 1412.58 | 676.03 | 584.55 |
| `synthetic_long_names.xml` | 4555.74 | 3332.31 | 3960.44 | 2773.99 | 1276.09 | 1654.48 |
| `synthetic_self_closing_swarm.xml` | 2589.90 | 1197.71 | 3259.90 | 1268.99 | 523.72 | 482.21 |
| `synthetic_mixed_content.xml` | 2445.50 | 1456.22 | 2782.06 | 1344.05 | 503.14 | 380.64 |
| `synthetic_small_records.xml` | 2177.09 | 1567.24 | 2148.54 | 1217.49 | 426.26 | 297.11 |
| `synthetic_tiny_empty.xml` | 1155.70 | 836.62 | 1476.90 | 1281.36 | 195.88 | 119.54 |
| `synthetic_tiny_text.xml` | 926.43 | 815.20 | 966.85 | 672.53 | 184.62 | 119.53 |
| `synthetic_one_attr.xml` | 1338.76 | 1000.16 | 1806.50 | 877.97 | 290.18 | 197.70 |
| `synthetic_two_attr.xml` | 1474.26 | 941.82 | 1769.43 | 950.47 | 318.19 | 213.92 |
| `synthetic_attrs4.xml` | 1497.73 | 896.23 | 2176.22 | 916.08 | 319.14 | 264.44 |
| `synthetic_attrs8.xml` | 1636.02 | 900.78 | 2368.59 | 899.99 | 359.87 | 272.64 |
| `synthetic_attrs16.xml` | 1757.30 | 904.66 | 2925.72 | 1043.17 | 441.83 | 375.13 |
| `synthetic_attrs32.xml` | 1836.42 | 997.69 | 3023.84 | 628.88 | 450.58 | 399.51 |
| `synthetic_attrs48.xml` | 1901.56 | 1035.45 | 3118.34 | 691.67 | 472.64 | 414.51 |
| `synthetic_attrs64.xml` | 2022.83 | 1110.67 | 3146.95 | 697.61 | 533.20 | 454.10 |
| `synthetic_attrs96.xml` | 2108.82 | 1142.19 | 3261.21 | 528.91 | 546.26 | 468.23 |
| `synthetic_attrs128.xml` | 2176.24 | 1123.86 | 3283.83 | 558.02 | 556.15 | 482.82 |
| `synthetic_long_attr_values.xml` | 5246.61 | 3515.36 | 5604.79 | 3357.94 | 1407.37 | 1393.98 |
| `synthetic_single_quotes.xml` | 2000.94 | 1132.71 | 2709.92 | 1072.67 | 493.71 | 405.23 |
| `synthetic_unicode_names.xml` | 2844.57 | 450.28 | 3438.47 | 436.53 | 625.66 | 490.49 |
| `synthetic_pretty_indented.xml` | 2341.92 | 1367.28 | 2352.76 | 1132.57 | 492.00 | 386.29 |
| `synthetic_crlf_pretty.xml` | 2124.37 | 1220.50 | 2750.07 | 1237.14 | 515.37 | 391.01 |
| `synthetic_token_whitespace_mix.xml` | 1437.48 | 889.25 | 1523.55 | 903.83 | 441.50 | 367.15 |
| `synthetic_attr_count_mix.xml` | 1790.51 | 940.04 | 2605.58 | 914.74 | 371.13 | 313.85 |

### Stable Gates

| Fixture | ours-turbo | best external | ours/best-ext | Result |
|---|---:|---|---:|---|
| `note.xml` | 2976.49 | `rapidxml` 1418.02 | 2.099 | PASS |
| `sitemaps.xml` | 3683.65 | `pugixml` 2054.27 | 1.793 | PASS |
| `plant_catalog.xml` | 3038.54 | `rapidxml` 1374.32 | 2.211 | PASS |
| `cd_catalog.xml` | 2805.45 | `pugixml` 1477.88 | 1.898 | PASS |
| `hnrss.xml` | 8011.36 | `pugixml` 2676.20 | 2.994 | PASS |
| `xkcd_rss.xml` | 8394.76 | `pugixml` 2464.46 | 3.406 | PASS |
| `bbc_world.xml` | 4938.07 | `pugixml` 2693.20 | 1.834 | PASS |
| `arxiv_cs.xml` | 9727.18 | `pugixml` 2312.68 | 4.206 | PASS |
| `ecb_usd.xml` | 5016.33 | `pugixml` 2616.72 | 1.917 | PASS |
| `tree.xml` | 2326.47 | `rapidxml` 1564.97 | 1.487 | PASS |
| `character.xml` | 2605.15 | `rapidxml` 1700.49 | 1.532 | PASS |
| `transitions.xml` | 2151.95 | `rapidxml` 1833.42 | 1.174 | PASS |
| `xgconsole.xml` | 3035.83 | `rapidxml` 2011.21 | 1.509 | PASS |
| `weekly_utf8.xml` | 3078.29 | `rapidxml` 2210.43 | 1.393 | PASS |
| `pugixml_large.xml` | 2308.05 | `pugixml` 489.89 | 4.711 | PASS |
| `synthetic_flat_attrs.xml` | 1479.37 | `pugixml` 426.65 | 3.467 | PASS |
| `synthetic_deep_tree.xml` | 1415.72 | `pugixml` 1283.53 | 1.103 | PASS |
| `synthetic_entities.xml` | 4649.04 | `pugixml` 918.55 | 5.061 | PASS |
| `synthetic_cdata_mix.xml` | 2606.41 | `pugixml` 633.04 | 4.117 | PASS |
| `synthetic_wide_siblings.xml` | 2014.12 | `pugixml` 420.47 | 4.790 | PASS |
| `synthetic_namespace_mix.xml` | 2911.27 | `pugixml` 676.03 | 4.306 | PASS |
| `synthetic_long_names.xml` | 4555.74 | `rapidxml` 1654.48 | 2.754 | PASS |
| `synthetic_self_closing_swarm.xml` | 2589.90 | `pugixml` 523.72 | 4.945 | PASS |
| `synthetic_mixed_content.xml` | 2445.50 | `pugixml` 503.14 | 4.860 | PASS |
| `synthetic_small_records.xml` | 2177.09 | `pugixml` 426.26 | 5.107 | PASS |
| `synthetic_tiny_empty.xml` | 1155.70 | `pugixml` 195.88 | 5.900 | PASS |
| `synthetic_tiny_text.xml` | 926.43 | `pugixml` 184.62 | 5.018 | PASS |
| `synthetic_one_attr.xml` | 1338.76 | `pugixml` 290.18 | 4.613 | PASS |
| `synthetic_two_attr.xml` | 1474.26 | `pugixml` 318.19 | 4.633 | PASS |
| `synthetic_attrs4.xml` | 1497.73 | `pugixml` 319.14 | 4.693 | PASS |
| `synthetic_attrs8.xml` | 1636.02 | `pugixml` 359.87 | 4.546 | PASS |
| `synthetic_attrs16.xml` | 1757.30 | `pugixml` 441.83 | 3.977 | PASS |
| `synthetic_attrs32.xml` | 1836.42 | `pugixml` 450.58 | 4.076 | PASS |
| `synthetic_attrs48.xml` | 1901.56 | `pugixml` 472.64 | 4.023 | PASS |
| `synthetic_attrs64.xml` | 2022.83 | `pugixml` 533.20 | 3.794 | PASS |
| `synthetic_attrs96.xml` | 2108.82 | `pugixml` 546.26 | 3.860 | PASS |
| `synthetic_attrs128.xml` | 2176.24 | `pugixml` 556.15 | 3.913 | PASS |
| `synthetic_long_attr_values.xml` | 5246.61 | `pugixml` 1407.37 | 3.728 | PASS |
| `synthetic_single_quotes.xml` | 2000.94 | `pugixml` 493.71 | 4.053 | PASS |
| `synthetic_unicode_names.xml` | 2844.57 | `pugixml` 625.66 | 4.547 | PASS |
| `synthetic_pretty_indented.xml` | 2341.92 | `pugixml` 492.00 | 4.760 | PASS |
| `synthetic_crlf_pretty.xml` | 2124.37 | `pugixml` 515.37 | 4.122 | PASS |
| `synthetic_token_whitespace_mix.xml` | 1437.48 | `pugixml` 441.50 | 3.256 | PASS |
| `synthetic_attr_count_mix.xml` | 1790.51 | `pugixml` 371.13 | 4.824 | PASS |

### Streaming Comparison (Advisory)

| Fixture | stream-turbo | ours-turbo | stream/ours | stream-strict | ours-strict | stream/ours |
|---|---:|---:|---:|---:|---:|---:|
| `note.xml` | 2946.79 | 2976.49 | 0.990 | 1339.16 | 1463.64 | 0.915 |
| `sitemaps.xml` | 3699.31 | 3683.65 | 1.004 | 1700.21 | 1864.88 | 0.912 |
| `plant_catalog.xml` | 2619.85 | 3038.54 | 0.862 | 1443.57 | 1400.10 | 1.031 |
| `cd_catalog.xml` | 2549.84 | 2805.45 | 0.909 | 1277.05 | 1389.74 | 0.919 |
| `hnrss.xml` | 8096.25 | 8011.36 | 1.011 | 4109.22 | 3752.66 | 1.095 |
| `xkcd_rss.xml` | 8422.88 | 8394.76 | 1.003 | 3317.30 | 4034.20 | 0.822 |
| `bbc_world.xml` | 5422.98 | 4938.07 | 1.098 | 2948.31 | 3070.13 | 0.960 |
| `arxiv_cs.xml` | 9682.07 | 9727.18 | 0.995 | 4018.66 | 4111.78 | 0.977 |
| `ecb_usd.xml` | 4699.35 | 5016.33 | 0.937 | 2752.48 | 2993.33 | 0.920 |
| `tree.xml` | 2892.09 | 2326.47 | 1.243 | 1317.84 | 1209.70 | 1.089 |
| `character.xml` | 2558.39 | 2605.15 | 0.982 | 1311.06 | 1321.06 | 0.992 |
| `xgconsole.xml` | 3741.27 | 3035.83 | 1.232 | 1281.15 | 1649.65 | 0.777 |
| `weekly_utf8.xml` | 3635.69 | 3078.29 | 1.181 | 570.60 | 522.71 | 1.092 |
| `pugixml_large.xml` | 2453.68 | 2308.05 | 1.063 | 1695.42 | 1666.46 | 1.017 |
| `synthetic_flat_attrs.xml` | 2484.98 | 1479.37 | 1.680 | 939.38 | 889.50 | 1.056 |
| `synthetic_deep_tree.xml` | 1767.55 | 1415.72 | 1.249 | 908.02 | 946.44 | 0.959 |
| `synthetic_entities.xml` | 5293.71 | 4649.04 | 1.139 | 922.18 | 985.40 | 0.936 |
| `synthetic_cdata_mix.xml` | 2478.22 | 2606.41 | 0.951 | 1720.52 | 2072.32 | 0.830 |
| `synthetic_wide_siblings.xml` | 2207.37 | 2014.12 | 1.096 | 1038.19 | 1181.64 | 0.879 |
| `synthetic_namespace_mix.xml` | 3428.15 | 2911.27 | 1.178 | 1412.58 | 1449.29 | 0.975 |
| `synthetic_long_names.xml` | 3960.44 | 4555.74 | 0.869 | 2773.99 | 3332.31 | 0.832 |
| `synthetic_self_closing_swarm.xml` | 3259.90 | 2589.90 | 1.259 | 1268.99 | 1197.71 | 1.060 |
| `synthetic_mixed_content.xml` | 2782.06 | 2445.50 | 1.138 | 1344.05 | 1456.22 | 0.923 |
| `synthetic_small_records.xml` | 2148.54 | 2177.09 | 0.987 | 1217.49 | 1567.24 | 0.777 |
| `synthetic_tiny_empty.xml` | 1476.90 | 1155.70 | 1.278 | 1281.36 | 836.62 | 1.532 |
| `synthetic_tiny_text.xml` | 966.85 | 926.43 | 1.044 | 672.53 | 815.20 | 0.825 |
| `synthetic_one_attr.xml` | 1806.50 | 1338.76 | 1.349 | 877.97 | 1000.16 | 0.878 |
| `synthetic_two_attr.xml` | 1769.43 | 1474.26 | 1.200 | 950.47 | 941.82 | 1.009 |
| `synthetic_attrs4.xml` | 2176.22 | 1497.73 | 1.453 | 916.08 | 896.23 | 1.022 |
| `synthetic_attrs8.xml` | 2368.59 | 1636.02 | 1.448 | 899.99 | 900.78 | 0.999 |
| `synthetic_attrs16.xml` | 2925.72 | 1757.30 | 1.665 | 1043.17 | 904.66 | 1.153 |
| `synthetic_attrs32.xml` | 3023.84 | 1836.42 | 1.647 | 628.88 | 997.69 | 0.630 |
| `synthetic_attrs48.xml` | 3118.34 | 1901.56 | 1.640 | 691.67 | 1035.45 | 0.668 |
| `synthetic_attrs64.xml` | 3146.95 | 2022.83 | 1.556 | 697.61 | 1110.67 | 0.628 |
| `synthetic_attrs96.xml` | 3261.21 | 2108.82 | 1.546 | 528.91 | 1142.19 | 0.463 |
| `synthetic_attrs128.xml` | 3283.83 | 2176.24 | 1.509 | 558.02 | 1123.86 | 0.497 |
| `synthetic_long_attr_values.xml` | 5604.79 | 5246.61 | 1.068 | 3357.94 | 3515.36 | 0.955 |
| `synthetic_single_quotes.xml` | 2709.92 | 2000.94 | 1.354 | 1072.67 | 1132.71 | 0.947 |
| `synthetic_unicode_names.xml` | 3438.47 | 2844.57 | 1.209 | 436.53 | 450.28 | 0.969 |
| `synthetic_pretty_indented.xml` | 2352.76 | 2341.92 | 1.005 | 1132.57 | 1367.28 | 0.828 |
| `synthetic_crlf_pretty.xml` | 2750.07 | 2124.37 | 1.295 | 1237.14 | 1220.50 | 1.014 |
| `synthetic_token_whitespace_mix.xml` | 1523.55 | 1437.48 | 1.060 | 903.83 | 889.25 | 1.016 |
| `synthetic_attr_count_mix.xml` | 2605.58 | 1790.51 | 1.455 | 914.74 | 940.04 | 0.973 |

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

- `"profile": "strict"` for a single mode/profile
- `"profiles": ["strict", "turbo_default"]` to run the same assertions in both modes

## Parser Perf Guardrail

The hard gate is:

- `ours-turbo >= max(pugixml, rapidxml)` per fixture

For parser-only optimization passes, use the paired A/B harness below.

Optional strict/turbo spot checks:

```bash
zig-out/bin/zxml-bench parse strict bench/fixtures/sitemaps.xml 400
zig-out/bin/zxml-bench parse turbo bench/fixtures/sitemaps.xml 2000
```

For sub-percent parser A/B work, use `bench/paired_bench.py`. It runs baseline
and candidate simultaneously on two pinned CPUs, swaps the CPU assignments,
geometrically combines each assignment pair, then uses the median paired ratio
across repeats to reject scheduler outliers. Reported ratios are candidate time
divided by baseline time, so values below `1.0` are faster.
