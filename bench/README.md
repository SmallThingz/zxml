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
| `note.xml` | 2145.75 | 2038.67 | 2915.60 | 2814.18 | 1024.88 | 1837.21 |
| `sitemaps.xml` | 2161.69 | 1997.86 | 3000.88 | 2901.07 | 1920.33 | 1901.58 |
| `plant_catalog.xml` | 2036.53 | 1834.67 | 3081.86 | 2839.59 | 1510.53 | 1537.13 |
| `cd_catalog.xml` | 1896.12 | 1810.49 | 3072.63 | 2835.03 | 1374.80 | 1597.87 |
| `hnrss.xml` | 5364.44 | 4794.50 | 6431.49 | 5770.48 | 2718.02 | 2260.28 |
| `xkcd_rss.xml` | 6342.06 | 5983.89 | 8252.95 | 7351.87 | 2494.80 | 1837.27 |
| `bbc_world.xml` | 3397.25 | 3262.97 | 4779.41 | 4387.63 | 2575.75 | 2292.94 |
| `arxiv_cs.xml` | 7094.64 | 6681.59 | 9298.30 | 8922.12 | 2692.95 | 1695.16 |
| `ecb_usd.xml` | 4134.45 | 3866.29 | 4989.79 | 4460.99 | 2658.14 | 2368.75 |
| `tree.xml` | 2200.46 | 2078.34 | 2678.92 | 2390.42 | 1322.85 | 2088.78 |
| `character.xml` | 2006.47 | 1929.45 | 2704.82 | 2319.08 | 1227.74 | 1933.98 |
| `transitions.xml` | 2207.47 | 1932.16 | 2833.79 | 2305.90 | 1399.26 | 1773.44 |
| `xgconsole.xml` | 2644.51 | 2514.09 | 3722.08 | 3408.65 | 1993.73 | 2127.41 |
| `weekly_utf8.xml` | 2314.66 | 2066.98 | 3079.63 | 2502.80 | 2073.51 | 2304.10 |
| `pugixml_large.xml` | 1606.68 | 1570.55 | 2313.99 | 2305.85 | 480.42 | 309.93 |
| `synthetic_flat_attrs.xml` | 1459.42 | 1271.14 | 1947.37 | 1653.66 | 459.75 | 342.61 |
| `synthetic_deep_tree.xml` | 1311.46 | 1154.92 | 2113.16 | 1757.29 | 1225.40 | 489.61 |
| `synthetic_entities.xml` | 3651.54 | 3373.82 | 4830.49 | 4522.34 | 534.64 | 817.65 |
| `synthetic_cdata_mix.xml` | 2398.14 | 2329.49 | 2903.95 | 2699.19 | 925.64 | 860.17 |
| `synthetic_wide_siblings.xml` | 1796.73 | 1633.17 | 2834.59 | 2525.51 | 440.03 | 310.93 |
| `synthetic_namespace_mix.xml` | 2518.08 | 2219.96 | 3413.04 | 2927.09 | 685.77 | 529.31 |
| `synthetic_long_names.xml` | 3527.68 | 3394.62 | 3884.11 | 3438.99 | 1317.14 | 1379.72 |
| `synthetic_self_closing_swarm.xml` | 2372.60 | 2163.56 | 3195.18 | 2823.60 | 598.43 | 474.36 |
| `synthetic_mixed_content.xml` | 1978.03 | 1904.09 | 2749.83 | 2521.29 | 639.59 | 492.19 |
| `synthetic_small_records.xml` | 2051.80 | 1853.17 | 3030.26 | 2672.49 | 436.36 | 322.53 |

### Stable Gates

| Fixture | ours-turbo | best external | ours/best-ext | Result |
|---|---:|---|---:|---|
| `note.xml` | 2145.75 | `rapidxml` 1837.21 | 1.168 | PASS |
| `sitemaps.xml` | 2161.69 | `pugixml` 1920.33 | 1.126 | PASS |
| `plant_catalog.xml` | 2036.53 | `rapidxml` 1537.13 | 1.325 | PASS |
| `cd_catalog.xml` | 1896.12 | `rapidxml` 1597.87 | 1.187 | PASS |
| `hnrss.xml` | 5364.44 | `pugixml` 2718.02 | 1.974 | PASS |
| `xkcd_rss.xml` | 6342.06 | `pugixml` 2494.80 | 2.542 | PASS |
| `bbc_world.xml` | 3397.25 | `pugixml` 2575.75 | 1.319 | PASS |
| `arxiv_cs.xml` | 7094.64 | `pugixml` 2692.95 | 2.635 | PASS |
| `ecb_usd.xml` | 4134.45 | `pugixml` 2658.14 | 1.555 | PASS |
| `tree.xml` | 2200.46 | `rapidxml` 2088.78 | 1.053 | PASS |
| `character.xml` | 2006.47 | `rapidxml` 1933.98 | 1.037 | PASS |
| `transitions.xml` | 2207.47 | `rapidxml` 1773.44 | 1.245 | PASS |
| `xgconsole.xml` | 2644.51 | `rapidxml` 2127.41 | 1.243 | PASS |
| `weekly_utf8.xml` | 2314.66 | `rapidxml` 2304.10 | 1.005 | PASS |
| `pugixml_large.xml` | 1606.68 | `pugixml` 480.42 | 3.344 | PASS |
| `synthetic_flat_attrs.xml` | 1459.42 | `pugixml` 459.75 | 3.174 | PASS |
| `synthetic_deep_tree.xml` | 1311.46 | `pugixml` 1225.40 | 1.070 | PASS |
| `synthetic_entities.xml` | 3651.54 | `rapidxml` 817.65 | 4.466 | PASS |
| `synthetic_cdata_mix.xml` | 2398.14 | `pugixml` 925.64 | 2.591 | PASS |
| `synthetic_wide_siblings.xml` | 1796.73 | `pugixml` 440.03 | 4.083 | PASS |
| `synthetic_namespace_mix.xml` | 2518.08 | `pugixml` 685.77 | 3.672 | PASS |
| `synthetic_long_names.xml` | 3527.68 | `rapidxml` 1379.72 | 2.557 | PASS |
| `synthetic_self_closing_swarm.xml` | 2372.60 | `pugixml` 598.43 | 3.965 | PASS |
| `synthetic_mixed_content.xml` | 1978.03 | `pugixml` 639.59 | 3.093 | PASS |
| `synthetic_small_records.xml` | 2051.80 | `pugixml` 436.36 | 4.702 | PASS |

### Streaming Gates

| Fixture | stream-turbo | ours-turbo | stream/ours | stream-strict | ours-strict | stream/ours | Result |
|---|---:|---:|---:|---:|---:|---:|---|
| `note.xml` | 2915.60 | 2145.75 | 1.359 | 2814.18 | 2038.67 | 1.380 | PASS |
| `sitemaps.xml` | 3000.88 | 2161.69 | 1.388 | 2901.07 | 1997.86 | 1.452 | PASS |
| `plant_catalog.xml` | 3081.86 | 2036.53 | 1.513 | 2839.59 | 1834.67 | 1.548 | PASS |
| `cd_catalog.xml` | 3072.63 | 1896.12 | 1.620 | 2835.03 | 1810.49 | 1.566 | PASS |
| `hnrss.xml` | 6431.49 | 5364.44 | 1.199 | 5770.48 | 4794.50 | 1.204 | PASS |
| `xkcd_rss.xml` | 8252.95 | 6342.06 | 1.301 | 7351.87 | 5983.89 | 1.229 | PASS |
| `bbc_world.xml` | 4779.41 | 3397.25 | 1.407 | 4387.63 | 3262.97 | 1.345 | PASS |
| `arxiv_cs.xml` | 9298.30 | 7094.64 | 1.311 | 8922.12 | 6681.59 | 1.335 | PASS |
| `ecb_usd.xml` | 4989.79 | 4134.45 | 1.207 | 4460.99 | 3866.29 | 1.154 | PASS |
| `tree.xml` | 2678.92 | 2200.46 | 1.217 | 2390.42 | 2078.34 | 1.150 | PASS |
| `character.xml` | 2704.82 | 2006.47 | 1.348 | 2319.08 | 1929.45 | 1.202 | PASS |
| `transitions.xml` | 2833.79 | 2207.47 | 1.284 | 2305.90 | 1932.16 | 1.193 | PASS |
| `xgconsole.xml` | 3722.08 | 2644.51 | 1.407 | 3408.65 | 2514.09 | 1.356 | PASS |
| `weekly_utf8.xml` | 3079.63 | 2314.66 | 1.330 | 2502.80 | 2066.98 | 1.211 | PASS |
| `pugixml_large.xml` | 2313.99 | 1606.68 | 1.440 | 2305.85 | 1570.55 | 1.468 | PASS |
| `synthetic_flat_attrs.xml` | 1947.37 | 1459.42 | 1.334 | 1653.66 | 1271.14 | 1.301 | PASS |
| `synthetic_deep_tree.xml` | 2113.16 | 1311.46 | 1.611 | 1757.29 | 1154.92 | 1.522 | PASS |
| `synthetic_entities.xml` | 4830.49 | 3651.54 | 1.323 | 4522.34 | 3373.82 | 1.340 | PASS |
| `synthetic_cdata_mix.xml` | 2903.95 | 2398.14 | 1.211 | 2699.19 | 2329.49 | 1.159 | PASS |
| `synthetic_wide_siblings.xml` | 2834.59 | 1796.73 | 1.578 | 2525.51 | 1633.17 | 1.546 | PASS |
| `synthetic_namespace_mix.xml` | 3413.04 | 2518.08 | 1.355 | 2927.09 | 2219.96 | 1.319 | PASS |
| `synthetic_long_names.xml` | 3884.11 | 3527.68 | 1.101 | 3438.99 | 3394.62 | 1.013 | PASS |
| `synthetic_self_closing_swarm.xml` | 3195.18 | 2372.60 | 1.347 | 2823.60 | 2163.56 | 1.305 | PASS |
| `synthetic_mixed_content.xml` | 2749.83 | 1978.03 | 1.390 | 2521.29 | 1904.09 | 1.324 | PASS |
| `synthetic_small_records.xml` | 3030.26 | 2051.80 | 1.477 | 2672.49 | 1853.17 | 1.442 | PASS |

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
