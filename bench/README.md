# FastXML Benchmark Suite

This suite compares `fastxml` against:

- `strlen` (memory bandwidth baseline)
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
| `note.xml` | 2234.61 | 2248.52 | 1005.28 | 1922.28 |
| `sitemaps.xml` | 2182.29 | 2211.70 | 1891.86 | 1951.71 |
| `plant_catalog.xml` | 2100.84 | 2120.87 | 1445.00 | 1561.92 |
| `cd_catalog.xml` | 1923.51 | 2023.12 | 1308.45 | 1495.71 |
| `hnrss.xml` | 5422.04 | 5055.54 | 2825.81 | 2249.64 |
| `xkcd_rss.xml` | 6509.40 | 6294.15 | 2511.77 | 1861.25 |
| `bbc_world.xml` | 3731.96 | 3588.93 | 2560.57 | 2291.90 |
| `arxiv_cs.xml` | 7302.65 | 7383.07 | 2675.48 | 1604.75 |
| `ecb_usd.xml` | 4217.32 | 4210.18 | 2640.20 | 2351.11 |
| `tree.xml` | 2242.27 | 2331.55 | 1312.22 | 2175.53 |
| `character.xml` | 2140.23 | 2185.87 | 1241.28 | 2094.49 |
| `transitions.xml` | 2253.64 | 2202.63 | 1389.34 | 1917.67 |
| `xgconsole.xml` | 2941.77 | 2916.85 | 1952.89 | 2161.81 |
| `weekly_utf8.xml` | 2459.38 | 2346.85 | 2079.36 | 2329.44 |
| `pugixml_large.xml` | 1754.56 | 1756.80 | 460.55 | 293.07 |
| `synthetic_flat_attrs.xml` | 1644.54 | 1653.31 | 429.92 | 330.79 |
| `synthetic_deep_tree.xml` | 1390.50 | 1345.57 | 1186.94 | 475.81 |
| `synthetic_entities.xml` | 3804.81 | 3894.36 | 514.87 | 792.47 |
| `synthetic_cdata_mix.xml` | 2381.28 | 2446.31 | 921.44 | 845.34 |
| `synthetic_wide_siblings.xml` | 1826.47 | 1872.27 | 418.58 | 294.16 |
| `synthetic_namespace_mix.xml` | 2627.20 | 2606.92 | 643.58 | 519.02 |
| `synthetic_long_names.xml` | 3765.68 | 3621.33 | 1282.73 | 1379.51 |
| `synthetic_self_closing_swarm.xml` | 2571.29 | 2476.10 | 570.79 | 443.77 |
| `synthetic_mixed_content.xml` | 1949.95 | 2012.08 | 621.59 | 471.33 |
| `synthetic_small_records.xml` | 2005.90 | 1974.55 | 404.62 | 292.64 |

### Stable Gates

| Fixture | ours-turbo | best external | ours/best-ext | Result |
|---|---:|---|---:|---|
| `note.xml` | 2234.61 | `rapidxml` 1922.28 | 1.162 | PASS |
| `sitemaps.xml` | 2182.29 | `rapidxml` 1951.71 | 1.118 | PASS |
| `plant_catalog.xml` | 2100.84 | `rapidxml` 1561.92 | 1.345 | PASS |
| `cd_catalog.xml` | 1923.51 | `rapidxml` 1495.71 | 1.286 | PASS |
| `hnrss.xml` | 5422.04 | `pugixml` 2825.81 | 1.919 | PASS |
| `xkcd_rss.xml` | 6509.40 | `pugixml` 2511.77 | 2.592 | PASS |
| `bbc_world.xml` | 3731.96 | `pugixml` 2560.57 | 1.457 | PASS |
| `arxiv_cs.xml` | 7302.65 | `pugixml` 2675.48 | 2.729 | PASS |
| `ecb_usd.xml` | 4217.32 | `pugixml` 2640.20 | 1.597 | PASS |
| `tree.xml` | 2242.27 | `rapidxml` 2175.53 | 1.031 | PASS |
| `character.xml` | 2140.23 | `rapidxml` 2094.49 | 1.022 | PASS |
| `transitions.xml` | 2253.64 | `rapidxml` 1917.67 | 1.175 | PASS |
| `xgconsole.xml` | 2941.77 | `rapidxml` 2161.81 | 1.361 | PASS |
| `weekly_utf8.xml` | 2459.38 | `rapidxml` 2329.44 | 1.056 | PASS |
| `pugixml_large.xml` | 1754.56 | `pugixml` 460.55 | 3.810 | PASS |
| `synthetic_flat_attrs.xml` | 1644.54 | `pugixml` 429.92 | 3.825 | PASS |
| `synthetic_deep_tree.xml` | 1390.50 | `pugixml` 1186.94 | 1.171 | PASS |
| `synthetic_entities.xml` | 3804.81 | `rapidxml` 792.47 | 4.801 | PASS |
| `synthetic_cdata_mix.xml` | 2381.28 | `pugixml` 921.44 | 2.584 | PASS |
| `synthetic_wide_siblings.xml` | 1826.47 | `pugixml` 418.58 | 4.363 | PASS |
| `synthetic_namespace_mix.xml` | 2627.20 | `pugixml` 643.58 | 4.082 | PASS |
| `synthetic_long_names.xml` | 3765.68 | `rapidxml` 1379.51 | 2.730 | PASS |
| `synthetic_self_closing_swarm.xml` | 2571.29 | `pugixml` 570.79 | 4.505 | PASS |
| `synthetic_mixed_content.xml` | 1949.95 | `pugixml` 621.59 | 3.137 | PASS |
| `synthetic_small_records.xml` | 2005.90 | `pugixml` 404.62 | 4.957 | PASS |

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
