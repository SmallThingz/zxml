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

Source: `bench/results/latest.json` (`quick` profile).

## Latest Benchmark Snapshot

### Parse Throughput Comparison (MB/s)

| Fixture | ours-turbo | ours-strict | stream-turbo | stream-strict | pugixml | rapidxml |
|---|---:|---:|---:|---:|---:|---:|
| `note.xml` | 2164.90 | 2222.21 | 2851.12 | 2721.45 | 1000.75 | 1850.06 |
| `sitemaps.xml` | 2163.78 | 2091.18 | 2592.26 | 2547.53 | 1836.92 | 1865.24 |
| `plant_catalog.xml` | 2054.40 | 1926.40 | 2822.16 | 2681.89 | 1426.47 | 1501.57 |
| `cd_catalog.xml` | 1915.22 | 1874.03 | 2764.71 | 2653.73 | 1353.70 | 1518.43 |
| `hnrss.xml` | 5392.69 | 5021.62 | 5860.17 | 5646.02 | 2798.12 | 2247.02 |
| `xkcd_rss.xml` | 6315.79 | 6195.11 | 7660.55 | 7290.42 | 2493.55 | 1797.80 |
| `bbc_world.xml` | 3572.87 | 3382.62 | 4547.00 | 4374.07 | 2567.42 | 2278.82 |
| `arxiv_cs.xml` | 6982.12 | 6679.45 | 8794.25 | 8766.35 | 2657.65 | 1612.40 |
| `ecb_usd.xml` | 4316.35 | 3955.79 | 4761.78 | 4619.57 | 2595.24 | 2395.64 |
| `pugixml_large.xml` | 1776.46 | 1847.78 | 2144.24 | 2141.00 | 460.29 | 295.89 |
| `weekly_utf8.xml` | 2521.22 | 2159.67 | 2801.03 | 2626.65 | 2098.78 | 2289.56 |
| `xgconsole.xml` | 2807.89 | 2649.75 | 3441.16 | 3339.73 | 1908.24 | 2132.04 |
| `synthetic_flat_attrs.xml` | 1598.11 | 1560.92 | 1761.33 | 1707.89 | 429.33 | 329.95 |
| `synthetic_deep_tree.xml` | 1349.59 | 1265.79 | 1855.53 | 1692.12 | 1144.59 | 478.15 |
| `synthetic_entities.xml` | 3724.32 | 3639.18 | 4495.13 | 4398.12 | 520.80 | 775.46 |
| `synthetic_cdata_mix.xml` | 2338.00 | 2312.74 | 2809.75 | 2649.63 | 901.11 | 839.17 |
| `synthetic_wide_siblings.xml` | 1797.96 | 1745.97 | 2563.43 | 2439.20 | 415.81 | 283.58 |
| `synthetic_namespace_mix.xml` | 2564.84 | 2409.58 | 2976.85 | 2836.49 | 652.06 | 520.23 |
| `synthetic_long_names.xml` | 3736.59 | 3448.65 | 4042.33 | 3567.12 | 1283.70 | 1349.39 |
| `synthetic_self_closing_swarm.xml` | 2461.44 | 2463.97 | 2960.03 | 2855.22 | 571.40 | 445.19 |

### Stable Gates

| Fixture | ours-turbo | best external | ours/best-ext | Result |
|---|---:|---|---:|---|
| `note.xml` | 2164.90 | `rapidxml` 1850.06 | 1.170 | PASS |
| `sitemaps.xml` | 2163.78 | `rapidxml` 1865.24 | 1.160 | PASS |
| `plant_catalog.xml` | 2054.40 | `rapidxml` 1501.57 | 1.368 | PASS |
| `cd_catalog.xml` | 1915.22 | `rapidxml` 1518.43 | 1.261 | PASS |
| `hnrss.xml` | 5392.69 | `pugixml` 2798.12 | 1.927 | PASS |
| `xkcd_rss.xml` | 6315.79 | `pugixml` 2493.55 | 2.533 | PASS |
| `bbc_world.xml` | 3572.87 | `pugixml` 2567.42 | 1.392 | PASS |
| `arxiv_cs.xml` | 6982.12 | `pugixml` 2657.65 | 2.627 | PASS |
| `ecb_usd.xml` | 4316.35 | `pugixml` 2595.24 | 1.663 | PASS |
| `pugixml_large.xml` | 1776.46 | `pugixml` 460.29 | 3.859 | PASS |
| `weekly_utf8.xml` | 2521.22 | `rapidxml` 2289.56 | 1.101 | PASS |
| `xgconsole.xml` | 2807.89 | `rapidxml` 2132.04 | 1.317 | PASS |
| `synthetic_flat_attrs.xml` | 1598.11 | `pugixml` 429.33 | 3.722 | PASS |
| `synthetic_deep_tree.xml` | 1349.59 | `pugixml` 1144.59 | 1.179 | PASS |
| `synthetic_entities.xml` | 3724.32 | `rapidxml` 775.46 | 4.803 | PASS |
| `synthetic_cdata_mix.xml` | 2338.00 | `pugixml` 901.11 | 2.595 | PASS |
| `synthetic_wide_siblings.xml` | 1797.96 | `pugixml` 415.81 | 4.324 | PASS |
| `synthetic_namespace_mix.xml` | 2564.84 | `pugixml` 652.06 | 3.933 | PASS |
| `synthetic_long_names.xml` | 3736.59 | `rapidxml` 1349.39 | 2.769 | PASS |
| `synthetic_self_closing_swarm.xml` | 2461.44 | `pugixml` 571.40 | 4.308 | PASS |

### Streaming Gates

| Fixture | stream-turbo | ours-turbo | stream/ours | stream-strict | ours-strict | stream/ours | Result |
|---|---:|---:|---:|---:|---:|---:|---|
| `note.xml` | 2851.12 | 2164.90 | 1.317 | 2721.45 | 2222.21 | 1.225 | PASS |
| `sitemaps.xml` | 2592.26 | 2163.78 | 1.198 | 2547.53 | 2091.18 | 1.218 | PASS |
| `plant_catalog.xml` | 2822.16 | 2054.40 | 1.374 | 2681.89 | 1926.40 | 1.392 | PASS |
| `cd_catalog.xml` | 2764.71 | 1915.22 | 1.444 | 2653.73 | 1874.03 | 1.416 | PASS |
| `hnrss.xml` | 5860.17 | 5392.69 | 1.087 | 5646.02 | 5021.62 | 1.124 | PASS |
| `xkcd_rss.xml` | 7660.55 | 6315.79 | 1.213 | 7290.42 | 6195.11 | 1.177 | PASS |
| `bbc_world.xml` | 4547.00 | 3572.87 | 1.273 | 4374.07 | 3382.62 | 1.293 | PASS |
| `arxiv_cs.xml` | 8794.25 | 6982.12 | 1.260 | 8766.35 | 6679.45 | 1.312 | PASS |
| `ecb_usd.xml` | 4761.78 | 4316.35 | 1.103 | 4619.57 | 3955.79 | 1.168 | PASS |
| `pugixml_large.xml` | 2144.24 | 1776.46 | 1.207 | 2141.00 | 1847.78 | 1.159 | PASS |
| `weekly_utf8.xml` | 2801.03 | 2521.22 | 1.111 | 2626.65 | 2159.67 | 1.216 | PASS |
| `xgconsole.xml` | 3441.16 | 2807.89 | 1.226 | 3339.73 | 2649.75 | 1.260 | PASS |
| `synthetic_flat_attrs.xml` | 1761.33 | 1598.11 | 1.102 | 1707.89 | 1560.92 | 1.094 | PASS |
| `synthetic_deep_tree.xml` | 1855.53 | 1349.59 | 1.375 | 1692.12 | 1265.79 | 1.337 | PASS |
| `synthetic_entities.xml` | 4495.13 | 3724.32 | 1.207 | 4398.12 | 3639.18 | 1.209 | PASS |
| `synthetic_cdata_mix.xml` | 2809.75 | 2338.00 | 1.202 | 2649.63 | 2312.74 | 1.146 | PASS |
| `synthetic_wide_siblings.xml` | 2563.43 | 1797.96 | 1.426 | 2439.20 | 1745.97 | 1.397 | PASS |
| `synthetic_namespace_mix.xml` | 2976.85 | 2564.84 | 1.161 | 2836.49 | 2409.58 | 1.177 | PASS |
| `synthetic_long_names.xml` | 4042.33 | 3736.59 | 1.082 | 3567.12 | 3448.65 | 1.034 | PASS |
| `synthetic_self_closing_swarm.xml` | 2960.03 | 2461.44 | 1.203 | 2855.22 | 2463.97 | 1.159 | PASS |

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
