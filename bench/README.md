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
| CPU frequency scaling | 71% |
| CPU MHz range | 400.0000–4400.0000 |
| Zig | 0.16.0 (`ReleaseFast -Dcpu=native`) |
| C++ driver | c++ (`-O3 -DNDEBUG -march=native`) |

### Parse Throughput Comparison (MB/s)

| Fixture | ours-turbo | ours-strict | stream-turbo | stream-strict | pugixml | rapidxml |
|---|---:|---:|---:|---:|---:|---:|
| `note.xml` | 1686.11 | 1243.73 | 1311.73 | 555.53 | 494.33 | 1047.10 |
| `sitemaps.xml` | 1838.85 | 1200.96 | 1466.80 | 703.19 | 1051.67 | 934.81 |
| `plant_catalog.xml` | 1470.19 | 1102.87 | 1294.66 | 693.02 | 849.08 | 887.11 |
| `cd_catalog.xml` | 2437.88 | 1291.05 | 2049.67 | 994.94 | 1146.65 | 1049.53 |
| `hnrss.xml` | 6289.14 | 5674.19 | 5960.54 | 1870.51 | 2070.08 | 1921.18 |
| `xkcd_rss.xml` | 4240.64 | 3561.08 | 5433.81 | 2541.37 | 1656.36 | 1822.67 |
| `bbc_world.xml` | 2938.79 | 2219.58 | 2140.71 | 1906.21 | 1334.61 | 1436.93 |
| `arxiv_cs.xml` | 8732.06 | 7170.69 | 8118.85 | 2801.15 | 2350.92 | 1473.89 |
| `ecb_usd.xml` | 6121.18 | 4007.11 | 4155.32 | 2588.37 | 2610.04 | 2589.26 |
| `tree.xml` | 2919.67 | 2356.14 | 2546.84 | 1285.06 | 1253.41 | 1828.42 |
| `character.xml` | 3631.57 | 2775.16 | 2630.01 | 1172.10 | 1092.17 | 2035.39 |
| `transitions.xml` | 3484.99 | - | 2848.85 | - | 1242.86 | 2144.24 |
| `xgconsole.xml` | 5409.40 | 4262.09 | 3001.26 | 1166.76 | 1871.76 | 2313.24 |
| `weekly_utf8.xml` | 4193.75 | 3021.09 | 3067.86 | 551.90 | 2051.42 | 2381.51 |
| `pugixml_large.xml` | 3210.80 | 1752.98 | 2476.28 | 1617.14 | 426.96 | 313.76 |
| `synthetic_flat_attrs.xml` | 5643.61 | 4926.59 | 2606.42 | 993.77 | 486.24 | 373.81 |
| `synthetic_deep_tree.xml` | 2078.30 | 1436.70 | 1757.40 | 927.95 | 1242.41 | 777.01 |
| `synthetic_entities.xml` | 4468.79 | 4494.52 | 4648.55 | 781.11 | 907.44 | 870.97 |
| `synthetic_cdata_mix.xml` | 2717.29 | 2550.98 | 2199.95 | 1538.11 | 677.45 | 513.87 |
| `synthetic_wide_siblings.xml` | 2739.32 | 2103.69 | 2062.52 | 983.16 | 442.36 | 341.92 |
| `synthetic_namespace_mix.xml` | 3890.10 | 3193.36 | 3037.16 | 1460.91 | 649.88 | 573.16 |
| `synthetic_long_names.xml` | 5679.88 | 5577.67 | 3631.39 | 2399.59 | 1271.73 | 1545.93 |
| `synthetic_self_closing_swarm.xml` | 3253.94 | 2831.61 | 3001.55 | 1207.28 | 516.23 | 404.11 |
| `synthetic_mixed_content.xml` | 1938.63 | 1627.00 | 2064.47 | 1040.67 | 301.20 | 258.64 |
| `synthetic_small_records.xml` | 2964.85 | 2101.89 | 1894.94 | 1000.36 | 347.92 | 292.87 |
| `synthetic_tiny_empty.xml` | 1991.25 | 1667.15 | 1550.31 | 1178.29 | 197.62 | 120.05 |
| `synthetic_tiny_text.xml` | 1330.79 | 1144.24 | 1128.06 | 531.98 | 133.14 | 105.95 |
| `synthetic_one_attr.xml` | 1971.52 | 1925.48 | 1614.90 | 814.04 | 173.23 | 144.26 |
| `synthetic_two_attr.xml` | 2473.70 | 1317.61 | 1413.15 | 799.80 | 246.92 | 117.25 |
| `synthetic_attrs4.xml` | 3048.38 | 2861.94 | 1773.62 | 674.62 | 225.65 | 182.75 |
| `synthetic_attrs8.xml` | 1906.76 | 1868.62 | 1076.50 | 448.43 | 156.49 | 135.58 |
| `synthetic_single_quotes.xml` | 2231.88 | 1636.32 | 1295.20 | 491.94 | 224.86 | 180.25 |
| `synthetic_unicode_names.xml` | 1577.46 | 1250.93 | 1244.94 | 204.92 | 258.03 | 232.70 |
| `synthetic_pretty_indented.xml` | 1255.82 | 946.82 | 951.78 | 518.18 | 211.66 | 192.93 |
| `synthetic_crlf_pretty.xml` | 1071.17 | 1096.45 | 1218.60 | 558.77 | 228.09 | 194.51 |
| `synthetic_token_whitespace_mix.xml` | 1823.80 | 1494.35 | 787.23 | 488.62 | 204.52 | 179.51 |
| `synthetic_attr_count_mix.xml` | 2963.30 | 2715.20 | 1227.28 | 461.32 | 170.13 | 155.03 |

### Stable Gates

| Fixture | ours-turbo | best external | ours/best-ext | Result |
|---|---:|---|---:|---|
| `note.xml` | 1686.11 | `rapidxml` 1047.10 | 1.610 | PASS |
| `sitemaps.xml` | 1838.85 | `pugixml` 1051.67 | 1.748 | PASS |
| `plant_catalog.xml` | 1470.19 | `rapidxml` 887.11 | 1.657 | PASS |
| `cd_catalog.xml` | 2437.88 | `pugixml` 1146.65 | 2.126 | PASS |
| `hnrss.xml` | 6289.14 | `pugixml` 2070.08 | 3.038 | PASS |
| `xkcd_rss.xml` | 4240.64 | `rapidxml` 1822.67 | 2.327 | PASS |
| `bbc_world.xml` | 2938.79 | `rapidxml` 1436.93 | 2.045 | PASS |
| `arxiv_cs.xml` | 8732.06 | `pugixml` 2350.92 | 3.714 | PASS |
| `ecb_usd.xml` | 6121.18 | `pugixml` 2610.04 | 2.345 | PASS |
| `tree.xml` | 2919.67 | `rapidxml` 1828.42 | 1.597 | PASS |
| `character.xml` | 3631.57 | `rapidxml` 2035.39 | 1.784 | PASS |
| `transitions.xml` | 3484.99 | `rapidxml` 2144.24 | 1.625 | PASS |
| `xgconsole.xml` | 5409.40 | `rapidxml` 2313.24 | 2.338 | PASS |
| `weekly_utf8.xml` | 4193.75 | `rapidxml` 2381.51 | 1.761 | PASS |
| `pugixml_large.xml` | 3210.80 | `pugixml` 426.96 | 7.520 | PASS |
| `synthetic_flat_attrs.xml` | 5643.61 | `pugixml` 486.24 | 11.607 | PASS |
| `synthetic_deep_tree.xml` | 2078.30 | `pugixml` 1242.41 | 1.673 | PASS |
| `synthetic_entities.xml` | 4468.79 | `pugixml` 907.44 | 4.925 | PASS |
| `synthetic_cdata_mix.xml` | 2717.29 | `pugixml` 677.45 | 4.011 | PASS |
| `synthetic_wide_siblings.xml` | 2739.32 | `pugixml` 442.36 | 6.193 | PASS |
| `synthetic_namespace_mix.xml` | 3890.10 | `pugixml` 649.88 | 5.986 | PASS |
| `synthetic_long_names.xml` | 5679.88 | `rapidxml` 1545.93 | 3.674 | PASS |
| `synthetic_self_closing_swarm.xml` | 3253.94 | `pugixml` 516.23 | 6.303 | PASS |
| `synthetic_mixed_content.xml` | 1938.63 | `pugixml` 301.20 | 6.436 | PASS |
| `synthetic_small_records.xml` | 2964.85 | `pugixml` 347.92 | 8.522 | PASS |
| `synthetic_tiny_empty.xml` | 1991.25 | `pugixml` 197.62 | 10.076 | PASS |
| `synthetic_tiny_text.xml` | 1330.79 | `pugixml` 133.14 | 9.995 | PASS |
| `synthetic_one_attr.xml` | 1971.52 | `pugixml` 173.23 | 11.381 | PASS |
| `synthetic_two_attr.xml` | 2473.70 | `pugixml` 246.92 | 10.018 | PASS |
| `synthetic_attrs4.xml` | 3048.38 | `pugixml` 225.65 | 13.510 | PASS |
| `synthetic_attrs8.xml` | 1906.76 | `pugixml` 156.49 | 12.184 | PASS |
| `synthetic_single_quotes.xml` | 2231.88 | `pugixml` 224.86 | 9.926 | PASS |
| `synthetic_unicode_names.xml` | 1577.46 | `pugixml` 258.03 | 6.114 | PASS |
| `synthetic_pretty_indented.xml` | 1255.82 | `pugixml` 211.66 | 5.933 | PASS |
| `synthetic_crlf_pretty.xml` | 1071.17 | `pugixml` 228.09 | 4.696 | PASS |
| `synthetic_token_whitespace_mix.xml` | 1823.80 | `pugixml` 204.52 | 8.917 | PASS |
| `synthetic_attr_count_mix.xml` | 2963.30 | `pugixml` 170.13 | 17.418 | PASS |

### Streaming Comparison (Advisory)

| Fixture | stream-turbo | ours-turbo | stream/ours | stream-strict | ours-strict | stream/ours |
|---|---:|---:|---:|---:|---:|---:|
| `note.xml` | 1311.73 | 1686.11 | 0.778 | 555.53 | 1243.73 | 0.447 |
| `sitemaps.xml` | 1466.80 | 1838.85 | 0.798 | 703.19 | 1200.96 | 0.586 |
| `plant_catalog.xml` | 1294.66 | 1470.19 | 0.881 | 693.02 | 1102.87 | 0.628 |
| `cd_catalog.xml` | 2049.67 | 2437.88 | 0.841 | 994.94 | 1291.05 | 0.771 |
| `hnrss.xml` | 5960.54 | 6289.14 | 0.948 | 1870.51 | 5674.19 | 0.330 |
| `xkcd_rss.xml` | 5433.81 | 4240.64 | 1.281 | 2541.37 | 3561.08 | 0.714 |
| `bbc_world.xml` | 2140.71 | 2938.79 | 0.728 | 1906.21 | 2219.58 | 0.859 |
| `arxiv_cs.xml` | 8118.85 | 8732.06 | 0.930 | 2801.15 | 7170.69 | 0.391 |
| `ecb_usd.xml` | 4155.32 | 6121.18 | 0.679 | 2588.37 | 4007.11 | 0.646 |
| `tree.xml` | 2546.84 | 2919.67 | 0.872 | 1285.06 | 2356.14 | 0.545 |
| `character.xml` | 2630.01 | 3631.57 | 0.724 | 1172.10 | 2775.16 | 0.422 |
| `xgconsole.xml` | 3001.26 | 5409.40 | 0.555 | 1166.76 | 4262.09 | 0.274 |
| `weekly_utf8.xml` | 3067.86 | 4193.75 | 0.732 | 551.90 | 3021.09 | 0.183 |
| `pugixml_large.xml` | 2476.28 | 3210.80 | 0.771 | 1617.14 | 1752.98 | 0.923 |
| `synthetic_flat_attrs.xml` | 2606.42 | 5643.61 | 0.462 | 993.77 | 4926.59 | 0.202 |
| `synthetic_deep_tree.xml` | 1757.40 | 2078.30 | 0.846 | 927.95 | 1436.70 | 0.646 |
| `synthetic_entities.xml` | 4648.55 | 4468.79 | 1.040 | 781.11 | 4494.52 | 0.174 |
| `synthetic_cdata_mix.xml` | 2199.95 | 2717.29 | 0.810 | 1538.11 | 2550.98 | 0.603 |
| `synthetic_wide_siblings.xml` | 2062.52 | 2739.32 | 0.753 | 983.16 | 2103.69 | 0.467 |
| `synthetic_namespace_mix.xml` | 3037.16 | 3890.10 | 0.781 | 1460.91 | 3193.36 | 0.457 |
| `synthetic_long_names.xml` | 3631.39 | 5679.88 | 0.639 | 2399.59 | 5577.67 | 0.430 |
| `synthetic_self_closing_swarm.xml` | 3001.55 | 3253.94 | 0.922 | 1207.28 | 2831.61 | 0.426 |
| `synthetic_mixed_content.xml` | 2064.47 | 1938.63 | 1.065 | 1040.67 | 1627.00 | 0.640 |
| `synthetic_small_records.xml` | 1894.94 | 2964.85 | 0.639 | 1000.36 | 2101.89 | 0.476 |
| `synthetic_tiny_empty.xml` | 1550.31 | 1991.25 | 0.779 | 1178.29 | 1667.15 | 0.707 |
| `synthetic_tiny_text.xml` | 1128.06 | 1330.79 | 0.848 | 531.98 | 1144.24 | 0.465 |
| `synthetic_one_attr.xml` | 1614.90 | 1971.52 | 0.819 | 814.04 | 1925.48 | 0.423 |
| `synthetic_two_attr.xml` | 1413.15 | 2473.70 | 0.571 | 799.80 | 1317.61 | 0.607 |
| `synthetic_attrs4.xml` | 1773.62 | 3048.38 | 0.582 | 674.62 | 2861.94 | 0.236 |
| `synthetic_attrs8.xml` | 1076.50 | 1906.76 | 0.565 | 448.43 | 1868.62 | 0.240 |
| `synthetic_single_quotes.xml` | 1295.20 | 2231.88 | 0.580 | 491.94 | 1636.32 | 0.301 |
| `synthetic_unicode_names.xml` | 1244.94 | 1577.46 | 0.789 | 204.92 | 1250.93 | 0.164 |
| `synthetic_pretty_indented.xml` | 951.78 | 1255.82 | 0.758 | 518.18 | 946.82 | 0.547 |
| `synthetic_crlf_pretty.xml` | 1218.60 | 1071.17 | 1.138 | 558.77 | 1096.45 | 0.510 |
| `synthetic_token_whitespace_mix.xml` | 787.23 | 1823.80 | 0.432 | 488.62 | 1494.35 | 0.327 |
| `synthetic_attr_count_mix.xml` | 1227.28 | 2963.30 | 0.414 | 461.32 | 2715.20 | 0.170 |

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
