# FastXML Benchmark Suite

This suite compares `fastxml` against:

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

| Fixture | ours-turbo | ours-strict | pugixml | rapidxml |
|---|---:|---:|---:|---:|
| `note.xml` | 2191.64 | 2231.03 | 1008.33 | 1936.53 |
| `sitemaps.xml` | 2064.82 | 2124.24 | 1887.19 | 1935.97 |
| `plant_catalog.xml` | 2057.33 | 2040.71 | 1351.26 | 1485.09 |
| `cd_catalog.xml` | 1884.08 | 1792.74 | 1288.75 | 1504.69 |
| `hnrss.xml` | 5234.35 | 4835.61 | 2696.45 | 2263.35 |
| `xkcd_rss.xml` | 6407.88 | 6363.92 | 2533.45 | 1848.96 |
| `bbc_world.xml` | 3667.80 | 3623.14 | 2570.42 | 2291.75 |
| `arxiv_cs.xml` | 7283.81 | 7109.66 | 2691.38 | 1615.65 |
| `ecb_usd.xml` | 4229.09 | 4133.27 | 2639.78 | 2381.11 |
| `tree.xml` | 2246.07 | 2269.23 | 1331.52 | 2112.97 |
| `character.xml` | 2144.77 | 2132.92 | 1238.52 | 2074.47 |
| `transitions.xml` | 2254.70 | 2145.99 | 1361.35 | 1918.56 |
| `xgconsole.xml` | 2904.54 | 2861.32 | 1961.97 | 2199.69 |
| `weekly_utf8.xml` | 2432.27 | 2209.16 | 2090.02 | 2337.12 |
| `pugixml_large.xml` | 1725.88 | 1772.44 | 462.76 | 294.77 |
| `synthetic_flat_attrs.xml` | 1657.11 | 1672.37 | 433.43 | 332.23 |
| `synthetic_deep_tree.xml` | 1408.36 | 1314.35 | 1181.58 | 474.29 |
| `synthetic_entities.xml` | 3828.75 | 3780.80 | 520.63 | 775.54 |
| `synthetic_cdata_mix.xml` | 2447.90 | 2384.26 | 912.76 | 843.89 |
| `synthetic_wide_siblings.xml` | 1873.73 | 1810.93 | 418.43 | 286.02 |
| `synthetic_namespace_mix.xml` | 2684.81 | 2478.22 | 650.56 | 516.22 |
| `synthetic_long_names.xml` | 3937.00 | 3553.78 | 1279.35 | 1358.00 |
| `synthetic_self_closing_swarm.xml` | 2584.71 | 2553.68 | 568.45 | 441.99 |
| `synthetic_mixed_content.xml` | 1942.52 | 1894.42 | 623.93 | 478.03 |
| `synthetic_small_records.xml` | 2044.45 | 1915.01 | 425.85 | 308.10 |

### Stable Gates

| Fixture | ours-turbo | best external | ours/best-ext | Result |
|---|---:|---|---:|---|
| `note.xml` | 2191.64 | `rapidxml` 1936.53 | 1.132 | PASS |
| `sitemaps.xml` | 2064.82 | `rapidxml` 1935.97 | 1.067 | PASS |
| `plant_catalog.xml` | 2057.33 | `rapidxml` 1485.09 | 1.385 | PASS |
| `cd_catalog.xml` | 1884.08 | `rapidxml` 1504.69 | 1.252 | PASS |
| `hnrss.xml` | 5234.35 | `pugixml` 2696.45 | 1.941 | PASS |
| `xkcd_rss.xml` | 6407.88 | `pugixml` 2533.45 | 2.529 | PASS |
| `bbc_world.xml` | 3667.80 | `pugixml` 2570.42 | 1.427 | PASS |
| `arxiv_cs.xml` | 7283.81 | `pugixml` 2691.38 | 2.706 | PASS |
| `ecb_usd.xml` | 4229.09 | `pugixml` 2639.78 | 1.602 | PASS |
| `tree.xml` | 2246.07 | `rapidxml` 2112.97 | 1.063 | PASS |
| `character.xml` | 2144.77 | `rapidxml` 2074.47 | 1.034 | PASS |
| `transitions.xml` | 2254.70 | `rapidxml` 1918.56 | 1.175 | PASS |
| `xgconsole.xml` | 2904.54 | `rapidxml` 2199.69 | 1.320 | PASS |
| `weekly_utf8.xml` | 2432.27 | `rapidxml` 2337.12 | 1.041 | PASS |
| `pugixml_large.xml` | 1725.88 | `pugixml` 462.76 | 3.730 | PASS |
| `synthetic_flat_attrs.xml` | 1657.11 | `pugixml` 433.43 | 3.823 | PASS |
| `synthetic_deep_tree.xml` | 1408.36 | `pugixml` 1181.58 | 1.192 | PASS |
| `synthetic_entities.xml` | 3828.75 | `rapidxml` 775.54 | 4.937 | PASS |
| `synthetic_cdata_mix.xml` | 2447.90 | `pugixml` 912.76 | 2.682 | PASS |
| `synthetic_wide_siblings.xml` | 1873.73 | `pugixml` 418.43 | 4.478 | PASS |
| `synthetic_namespace_mix.xml` | 2684.81 | `pugixml` 650.56 | 4.127 | PASS |
| `synthetic_long_names.xml` | 3937.00 | `rapidxml` 1358.00 | 2.899 | PASS |
| `synthetic_self_closing_swarm.xml` | 2584.71 | `pugixml` 568.45 | 4.547 | PASS |
| `synthetic_mixed_content.xml` | 1942.52 | `pugixml` 623.93 | 3.113 | PASS |
| `synthetic_small_records.xml` | 2044.45 | `pugixml` 425.85 | 4.801 | PASS |

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
zig-out/bin/fastxml-bench parse strict bench/fixtures/sitemaps.xml 400
zig-out/bin/fastxml-bench parse turbo bench/fixtures/sitemaps.xml 2000
```
