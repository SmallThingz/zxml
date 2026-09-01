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
zig build tools -- run-benchmarks --profile quick
zig build tools -- run-benchmarks --profile stable
zig build conformance
```

`run-benchmarks` also updates:

- `README.md` auto-summary block
- `bench/README.md` latest benchmark snapshot block

Results are written to:

- `bench/results/latest.json`
- `bench/results/latest.md`

Benchmarks build the full DOM, including declaration/comment/CDATA/PI/doctype
nodes, so CDATA-heavy feeds are measured fairly against `pugixml` and
`rapidxml`.

Fixture setup rejects extremely opaque feeds. If a file is mostly CDATA payload,
it benchmarks string scanning more than XML DOM work.

<!-- BENCH_README_AUTO_SNAPSHOT:START -->

Source: `bench/results/latest.json` (`stable` profile).

## Latest Benchmark Snapshot

### Parse Throughput Comparison (MB/s)

| Fixture | ours-turbo | ours-strict | stream-turbo | stream-strict | pugixml | rapidxml |
|---|---:|---:|---:|---:|---:|---:|
| `note.xml` | 2378.96 | 2380.36 | 2655.16 | 2668.31 | 1005.07 | 1868.40 |
| `sitemaps.xml` | 2356.27 | 2378.22 | 3151.28 | 2792.46 | 1841.45 | 1898.18 |
| `plant_catalog.xml` | 2325.70 | 2464.59 | 2874.42 | 2610.40 | 1440.88 | 1530.17 |
| `cd_catalog.xml` | 2164.14 | 2257.74 | 2703.15 | 2459.81 | 1323.83 | 1537.72 |
| `hnrss.xml` | 6280.57 | 5760.75 | 6625.50 | 5907.66 | 2924.93 | 2287.20 |
| `xkcd_rss.xml` | 7048.73 | 6470.62 | 7679.45 | 7041.15 | 2493.83 | 1829.48 |
| `bbc_world.xml` | 4052.37 | 4224.63 | 4961.70 | 4447.66 | 2540.85 | 2256.99 |
| `arxiv_cs.xml` | 3078.22 | 2986.66 | 3729.56 | 3418.84 | 1953.52 | 2183.34 |
| `ecb_usd.xml` | 4726.02 | 4227.53 | 5233.25 | 4501.32 | 2585.62 | 2374.65 |
| `tree.xml` | 2340.66 | 2213.36 | 2793.30 | 2367.79 | 1278.86 | 2058.39 |
| `character.xml` | 2244.69 | 2075.22 | 2662.49 | 2338.12 | 1140.21 | 1962.98 |
| `transitions.xml` | 2395.46 | 2115.04 | 2709.51 | 2344.48 | 1290.71 | 1785.01 |
| `xgconsole.xml` | 2933.03 | 2797.20 | 3665.56 | 3261.82 | 1865.50 | 2135.68 |
| `weekly_utf8.xml` | 2919.77 | 2887.41 | 3529.36 | 2694.76 | 2060.73 | 2300.86 |
| `pugixml_large.xml` | 2195.54 | 2198.05 | 2379.25 | 2064.92 | 496.08 | 311.65 |
| `synthetic_flat_attrs.xml` | 1550.83 | 1276.79 | 1829.35 | 1669.01 | 440.78 | 331.36 |
| `synthetic_deep_tree.xml` | 1395.22 | 1159.79 | 1971.12 | 1519.92 | 1168.71 | 489.59 |
| `synthetic_entities.xml` | 3916.39 | 3572.27 | 4054.24 | 4154.93 | 529.60 | 834.30 |
| `synthetic_cdata_mix.xml` | 2418.11 | 2545.28 | 2666.56 | 2613.59 | 913.63 | 854.95 |
| `synthetic_wide_siblings.xml` | 1876.19 | 1782.39 | 2107.12 | 2027.75 | 424.90 | 296.47 |
| `synthetic_namespace_mix.xml` | 2791.58 | 2368.05 | 3191.16 | 2739.53 | 678.22 | 544.24 |
| `synthetic_long_names.xml` | 4543.35 | 4257.79 | 4243.91 | 4251.94 | 1330.01 | 1401.08 |
| `synthetic_self_closing_swarm.xml` | 2589.17 | 2139.58 | 2914.65 | 2686.83 | 583.03 | 469.20 |
| `synthetic_mixed_content.xml` | 2200.18 | 2233.09 | 2761.36 | 2414.19 | 623.85 | 480.08 |
| `synthetic_small_records.xml` | 2275.02 | 2186.69 | 2616.18 | 2454.86 | 429.75 | 315.32 |

### Stable Gates

| Fixture | ours-turbo | best external | ours/best-ext | Result |
|---|---:|---|---:|---|
| `note.xml` | 2378.96 | `rapidxml` 1868.40 | 1.273 | PASS |
| `sitemaps.xml` | 2356.27 | `rapidxml` 1898.18 | 1.241 | PASS |
| `plant_catalog.xml` | 2325.70 | `rapidxml` 1530.17 | 1.520 | PASS |
| `cd_catalog.xml` | 2164.14 | `rapidxml` 1537.72 | 1.407 | PASS |
| `hnrss.xml` | 6280.57 | `pugixml` 2924.93 | 2.147 | PASS |
| `xkcd_rss.xml` | 7048.73 | `pugixml` 2493.83 | 2.826 | PASS |
| `bbc_world.xml` | 4052.37 | `pugixml` 2540.85 | 1.595 | PASS |
| `arxiv_cs.xml` | 3078.22 | `rapidxml` 2183.34 | 1.410 | PASS |
| `ecb_usd.xml` | 4726.02 | `pugixml` 2585.62 | 1.828 | PASS |
| `tree.xml` | 2340.66 | `rapidxml` 2058.39 | 1.137 | PASS |
| `character.xml` | 2244.69 | `rapidxml` 1962.98 | 1.144 | PASS |
| `transitions.xml` | 2395.46 | `rapidxml` 1785.01 | 1.342 | PASS |
| `xgconsole.xml` | 2933.03 | `rapidxml` 2135.68 | 1.373 | PASS |
| `weekly_utf8.xml` | 2919.77 | `rapidxml` 2300.86 | 1.269 | PASS |
| `pugixml_large.xml` | 2195.54 | `pugixml` 496.08 | 4.426 | PASS |
| `synthetic_flat_attrs.xml` | 1550.83 | `pugixml` 440.78 | 3.518 | PASS |
| `synthetic_deep_tree.xml` | 1395.22 | `pugixml` 1168.71 | 1.194 | PASS |
| `synthetic_entities.xml` | 3916.39 | `rapidxml` 834.30 | 4.694 | PASS |
| `synthetic_cdata_mix.xml` | 2418.11 | `pugixml` 913.63 | 2.647 | PASS |
| `synthetic_wide_siblings.xml` | 1876.19 | `pugixml` 424.90 | 4.416 | PASS |
| `synthetic_namespace_mix.xml` | 2791.58 | `pugixml` 678.22 | 4.116 | PASS |
| `synthetic_long_names.xml` | 4543.35 | `rapidxml` 1401.08 | 3.243 | PASS |
| `synthetic_self_closing_swarm.xml` | 2589.17 | `pugixml` 583.03 | 4.441 | PASS |
| `synthetic_mixed_content.xml` | 2200.18 | `pugixml` 623.85 | 3.527 | PASS |
| `synthetic_small_records.xml` | 2275.02 | `pugixml` 429.75 | 5.294 | PASS |

### Streaming Comparison (Advisory)

| Fixture | stream-turbo | ours-turbo | stream/ours | stream-strict | ours-strict | stream/ours |
|---|---:|---:|---:|---:|---:|---:|
| `note.xml` | 2655.16 | 2378.96 | 1.116 | 2668.31 | 2380.36 | 1.121 |
| `sitemaps.xml` | 3151.28 | 2356.27 | 1.337 | 2792.46 | 2378.22 | 1.174 |
| `plant_catalog.xml` | 2874.42 | 2325.70 | 1.236 | 2610.40 | 2464.59 | 1.059 |
| `cd_catalog.xml` | 2703.15 | 2164.14 | 1.249 | 2459.81 | 2257.74 | 1.089 |
| `hnrss.xml` | 6625.50 | 6280.57 | 1.055 | 5907.66 | 5760.75 | 1.026 |
| `xkcd_rss.xml` | 7679.45 | 7048.73 | 1.089 | 7041.15 | 6470.62 | 1.088 |
| `bbc_world.xml` | 4961.70 | 4052.37 | 1.224 | 4447.66 | 4224.63 | 1.053 |
| `arxiv_cs.xml` | 3729.56 | 3078.22 | 1.212 | 3418.84 | 2986.66 | 1.145 |
| `ecb_usd.xml` | 5233.25 | 4726.02 | 1.107 | 4501.32 | 4227.53 | 1.065 |
| `tree.xml` | 2793.30 | 2340.66 | 1.193 | 2367.79 | 2213.36 | 1.070 |
| `character.xml` | 2662.49 | 2244.69 | 1.186 | 2338.12 | 2075.22 | 1.127 |
| `transitions.xml` | 2709.51 | 2395.46 | 1.131 | 2344.48 | 2115.04 | 1.108 |
| `xgconsole.xml` | 3665.56 | 2933.03 | 1.250 | 3261.82 | 2797.20 | 1.166 |
| `weekly_utf8.xml` | 3529.36 | 2919.77 | 1.209 | 2694.76 | 2887.41 | 0.933 |
| `pugixml_large.xml` | 2379.25 | 2195.54 | 1.084 | 2064.92 | 2198.05 | 0.939 |
| `synthetic_flat_attrs.xml` | 1829.35 | 1550.83 | 1.180 | 1669.01 | 1276.79 | 1.307 |
| `synthetic_deep_tree.xml` | 1971.12 | 1395.22 | 1.413 | 1519.92 | 1159.79 | 1.311 |
| `synthetic_entities.xml` | 4054.24 | 3916.39 | 1.035 | 4154.93 | 3572.27 | 1.163 |
| `synthetic_cdata_mix.xml` | 2666.56 | 2418.11 | 1.103 | 2613.59 | 2545.28 | 1.027 |
| `synthetic_wide_siblings.xml` | 2107.12 | 1876.19 | 1.123 | 2027.75 | 1782.39 | 1.138 |
| `synthetic_namespace_mix.xml` | 3191.16 | 2791.58 | 1.143 | 2739.53 | 2368.05 | 1.157 |
| `synthetic_long_names.xml` | 4243.91 | 4543.35 | 0.934 | 4251.94 | 4257.79 | 0.999 |
| `synthetic_self_closing_swarm.xml` | 2914.65 | 2589.17 | 1.126 | 2686.83 | 2139.58 | 1.256 |
| `synthetic_mixed_content.xml` | 2761.36 | 2200.18 | 1.255 | 2414.19 | 2233.09 | 1.081 |
| `synthetic_small_records.xml` | 2616.18 | 2275.02 | 1.150 | 2454.86 | 2186.69 | 1.123 |
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

For parser-only optimization passes, keep a baseline and compare fixture-by-fixture:

```bash
zig build tools -- run-benchmarks --profile quick --write-baseline
zig build tools -- run-benchmarks --profile quick
```

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
