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
| `note.xml` | 2196.24 | 2123.00 | 2663.75 | 2625.18 | 1000.76 | 1828.34 |
| `sitemaps.xml` | 2184.91 | 2160.54 | 2712.95 | 2503.55 | 1809.07 | 1916.66 |
| `plant_catalog.xml` | 2101.76 | 2068.76 | 2860.43 | 2676.85 | 1461.89 | 1539.77 |
| `cd_catalog.xml` | 1984.81 | 1954.58 | 2748.15 | 2562.88 | 1396.20 | 1534.80 |
| `hnrss.xml` | 5771.34 | 5460.66 | 6524.12 | 5648.00 | 2917.00 | 2298.07 |
| `xkcd_rss.xml` | 6530.65 | 6198.16 | 7672.61 | 6754.88 | 2501.07 | 1837.31 |
| `bbc_world.xml` | 3791.52 | 3463.16 | 4884.82 | 4526.75 | 2513.83 | 2249.26 |
| `arxiv_cs.xml` | 2826.28 | 2688.38 | 3640.34 | 3251.07 | 1949.86 | 2191.82 |
| `ecb_usd.xml` | 4288.45 | 3987.06 | 5119.10 | 4515.91 | 2585.64 | 2376.97 |
| `tree.xml` | 2273.42 | 2122.05 | 2749.73 | 2590.32 | 1271.60 | 2012.35 |
| `character.xml` | 2024.68 | 1917.56 | 2757.23 | 2613.49 | 1171.07 | 1917.87 |
| `transitions.xml` | 2163.19 | 1915.04 | 2892.30 | 2592.95 | 1288.86 | 1776.02 |
| `xgconsole.xml` | 2862.61 | 2567.77 | 3817.25 | 3464.28 | 1872.96 | 2139.70 |
| `weekly_utf8.xml` | 2559.96 | 2298.46 | 3187.47 | 2627.42 | 2052.24 | 2313.90 |
| `pugixml_large.xml` | 1888.68 | 1886.33 | 2228.77 | 2228.41 | 498.00 | 296.44 |
| `synthetic_flat_attrs.xml` | 1505.96 | 1247.06 | 1946.14 | 1922.34 | 448.71 | 345.30 |
| `synthetic_deep_tree.xml` | 1337.11 | 1128.62 | 2235.47 | 1688.69 | 1169.91 | 489.17 |
| `synthetic_entities.xml` | 3660.72 | 3400.63 | 4643.98 | 4481.31 | 523.75 | 844.30 |
| `synthetic_cdata_mix.xml` | 2474.30 | 2473.39 | 2814.39 | 2680.79 | 940.76 | 858.63 |
| `synthetic_wide_siblings.xml` | 1788.37 | 1638.76 | 2587.17 | 2423.54 | 415.09 | 309.80 |
| `synthetic_namespace_mix.xml` | 2552.08 | 2223.58 | 3306.68 | 2989.17 | 677.80 | 531.01 |
| `synthetic_long_names.xml` | 3919.77 | 3581.04 | 4992.65 | 4226.24 | 1340.27 | 1400.79 |
| `synthetic_self_closing_swarm.xml` | 2439.50 | 2121.15 | 3146.38 | 3104.06 | 580.27 | 473.36 |
| `synthetic_mixed_content.xml` | 2131.75 | 2090.92 | 2506.78 | 2385.27 | 640.49 | 493.48 |
| `synthetic_small_records.xml` | 2181.49 | 2005.94 | 2786.51 | 2344.39 | 433.14 | 323.33 |

### Stable Gates

| Fixture | ours-turbo | best external | ours/best-ext | Result |
|---|---:|---|---:|---|
| `note.xml` | 2196.24 | `rapidxml` 1828.34 | 1.201 | PASS |
| `sitemaps.xml` | 2184.91 | `rapidxml` 1916.66 | 1.140 | PASS |
| `plant_catalog.xml` | 2101.76 | `rapidxml` 1539.77 | 1.365 | PASS |
| `cd_catalog.xml` | 1984.81 | `rapidxml` 1534.80 | 1.293 | PASS |
| `hnrss.xml` | 5771.34 | `pugixml` 2917.00 | 1.979 | PASS |
| `xkcd_rss.xml` | 6530.65 | `pugixml` 2501.07 | 2.611 | PASS |
| `bbc_world.xml` | 3791.52 | `pugixml` 2513.83 | 1.508 | PASS |
| `arxiv_cs.xml` | 2826.28 | `rapidxml` 2191.82 | 1.289 | PASS |
| `ecb_usd.xml` | 4288.45 | `pugixml` 2585.64 | 1.659 | PASS |
| `tree.xml` | 2273.42 | `rapidxml` 2012.35 | 1.130 | PASS |
| `character.xml` | 2024.68 | `rapidxml` 1917.87 | 1.056 | PASS |
| `transitions.xml` | 2163.19 | `rapidxml` 1776.02 | 1.218 | PASS |
| `xgconsole.xml` | 2862.61 | `rapidxml` 2139.70 | 1.338 | PASS |
| `weekly_utf8.xml` | 2559.96 | `rapidxml` 2313.90 | 1.106 | PASS |
| `pugixml_large.xml` | 1888.68 | `pugixml` 498.00 | 3.793 | PASS |
| `synthetic_flat_attrs.xml` | 1505.96 | `pugixml` 448.71 | 3.356 | PASS |
| `synthetic_deep_tree.xml` | 1337.11 | `pugixml` 1169.91 | 1.143 | PASS |
| `synthetic_entities.xml` | 3660.72 | `rapidxml` 844.30 | 4.336 | PASS |
| `synthetic_cdata_mix.xml` | 2474.30 | `pugixml` 940.76 | 2.630 | PASS |
| `synthetic_wide_siblings.xml` | 1788.37 | `pugixml` 415.09 | 4.308 | PASS |
| `synthetic_namespace_mix.xml` | 2552.08 | `pugixml` 677.80 | 3.765 | PASS |
| `synthetic_long_names.xml` | 3919.77 | `rapidxml` 1400.79 | 2.798 | PASS |
| `synthetic_self_closing_swarm.xml` | 2439.50 | `pugixml` 580.27 | 4.204 | PASS |
| `synthetic_mixed_content.xml` | 2131.75 | `pugixml` 640.49 | 3.328 | PASS |
| `synthetic_small_records.xml` | 2181.49 | `pugixml` 433.14 | 5.036 | PASS |

### Streaming Gates

| Fixture | stream-turbo | ours-turbo | stream/ours | stream-strict | ours-strict | stream/ours | Result |
|---|---:|---:|---:|---:|---:|---:|---|
| `note.xml` | 2663.75 | 2196.24 | 1.213 | 2625.18 | 2123.00 | 1.237 | PASS |
| `sitemaps.xml` | 2712.95 | 2184.91 | 1.242 | 2503.55 | 2160.54 | 1.159 | PASS |
| `plant_catalog.xml` | 2860.43 | 2101.76 | 1.361 | 2676.85 | 2068.76 | 1.294 | PASS |
| `cd_catalog.xml` | 2748.15 | 1984.81 | 1.385 | 2562.88 | 1954.58 | 1.311 | PASS |
| `hnrss.xml` | 6524.12 | 5771.34 | 1.130 | 5648.00 | 5460.66 | 1.034 | PASS |
| `xkcd_rss.xml` | 7672.61 | 6530.65 | 1.175 | 6754.88 | 6198.16 | 1.090 | PASS |
| `bbc_world.xml` | 4884.82 | 3791.52 | 1.288 | 4526.75 | 3463.16 | 1.307 | PASS |
| `arxiv_cs.xml` | 3640.34 | 2826.28 | 1.288 | 3251.07 | 2688.38 | 1.209 | PASS |
| `ecb_usd.xml` | 5119.10 | 4288.45 | 1.194 | 4515.91 | 3987.06 | 1.133 | PASS |
| `tree.xml` | 2749.73 | 2273.42 | 1.210 | 2590.32 | 2122.05 | 1.221 | PASS |
| `character.xml` | 2757.23 | 2024.68 | 1.362 | 2613.49 | 1917.56 | 1.363 | PASS |
| `transitions.xml` | 2892.30 | 2163.19 | 1.337 | 2592.95 | 1915.04 | 1.354 | PASS |
| `xgconsole.xml` | 3817.25 | 2862.61 | 1.333 | 3464.28 | 2567.77 | 1.349 | PASS |
| `weekly_utf8.xml` | 3187.47 | 2559.96 | 1.245 | 2627.42 | 2298.46 | 1.143 | PASS |
| `pugixml_large.xml` | 2228.77 | 1888.68 | 1.180 | 2228.41 | 1886.33 | 1.181 | PASS |
| `synthetic_flat_attrs.xml` | 1946.14 | 1505.96 | 1.292 | 1922.34 | 1247.06 | 1.542 | PASS |
| `synthetic_deep_tree.xml` | 2235.47 | 1337.11 | 1.672 | 1688.69 | 1128.62 | 1.496 | PASS |
| `synthetic_entities.xml` | 4643.98 | 3660.72 | 1.269 | 4481.31 | 3400.63 | 1.318 | PASS |
| `synthetic_cdata_mix.xml` | 2814.39 | 2474.30 | 1.137 | 2680.79 | 2473.39 | 1.084 | PASS |
| `synthetic_wide_siblings.xml` | 2587.17 | 1788.37 | 1.447 | 2423.54 | 1638.76 | 1.479 | PASS |
| `synthetic_namespace_mix.xml` | 3306.68 | 2552.08 | 1.296 | 2989.17 | 2223.58 | 1.344 | PASS |
| `synthetic_long_names.xml` | 4992.65 | 3919.77 | 1.274 | 4226.24 | 3581.04 | 1.180 | PASS |
| `synthetic_self_closing_swarm.xml` | 3146.38 | 2439.50 | 1.290 | 3104.06 | 2121.15 | 1.463 | PASS |
| `synthetic_mixed_content.xml` | 2506.78 | 2131.75 | 1.176 | 2385.27 | 2090.92 | 1.141 | PASS |
| `synthetic_small_records.xml` | 2786.51 | 2181.49 | 1.277 | 2344.39 | 2005.94 | 1.169 | PASS |

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
