# FastXML Benchmark Suite

This suite compares `fastxml` against:

- `strlen` (memory bandwidth baseline)
- `pugixml`
- `rapidxml`

The corpus mixes:

- downloaded real XML fixtures (`note.xml`, `sitemaps.xml`, `plant_catalog.xml`, `cd_catalog.xml`, `hnrss.xml`, `xkcd_rss.xml`, `bbc_world.xml`, `arxiv_cs.xml`, `ecb_usd.xml`, `planetpython.xml`)
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

| Fixture | ours-turbo | ours-strict | pugixml | rapidxml |
|---|---:|---:|---:|---:|
| `note.xml` | 1153.24 | 1249.28 | 943.08 | 1764.03 |
| `sitemaps.xml` | 1207.21 | 1137.18 | 1736.37 | 1785.53 |
| `plant_catalog.xml` | 950.66 | 1135.16 | 1338.94 | 1415.59 |
| `cd_catalog.xml` | 1012.19 | 916.80 | 1279.26 | 1398.93 |
| `hnrss.xml` | 3569.97 | 3245.51 | 2636.51 | 2081.84 |
| `xkcd_rss.xml` | 3810.56 | 4029.52 | 2378.29 | 1547.49 |
| `bbc_world.xml` | 2174.73 | 2505.23 | 2383.35 | 1899.49 |
| `arxiv_cs.xml` | 4213.30 | 4472.56 | 2165.70 | 1404.95 |
| `ecb_usd.xml` | 2196.61 | 2084.14 | 2430.66 | 2260.04 |
| `planetpython.xml` | 26871.77 | 27182.56 | 1301.09 | 1485.42 |
| `pugixml_large.xml` | 915.00 | 880.03 | 427.63 | 279.50 |
| `weekly_utf8.xml` | 1399.72 | 1278.61 | 1976.25 | 2164.75 |
| `xgconsole.xml` | 1480.86 | 1217.49 | 1482.88 | 2057.13 |
| `synthetic_flat_attrs.xml` | 517.04 | 546.57 | 371.55 | 278.48 |
| `synthetic_deep_tree.xml` | 597.19 | 598.55 | 1010.13 | 428.04 |
| `synthetic_entities.xml` | 2441.98 | 2610.50 | 466.60 | 640.37 |
| `synthetic_cdata_mix.xml` | 1410.38 | 1278.26 | 808.53 | 771.43 |
| `synthetic_wide_siblings.xml` | 906.11 | 888.12 | 324.68 | 241.48 |
| `synthetic_namespace_mix.xml` | 1125.73 | 1061.77 | 577.77 | 452.50 |
| `synthetic_long_names.xml` | 1875.10 | 1464.53 | 1224.24 | 1288.79 |
| `synthetic_self_closing_swarm.xml` | 1072.15 | 1043.55 | 476.42 | 364.18 |

### Stable Gates

| Fixture | ours-turbo | best external | ours/best-ext | Threshold | Result |
|---|---:|---|---:|---:|---|
| `note.xml` | 1153.24 | `rapidxml` 1764.03 | 0.654 | 1.00 | FAIL |
| `sitemaps.xml` | 1207.21 | `rapidxml` 1785.53 | 0.676 | 1.00 | FAIL |
| `plant_catalog.xml` | 950.66 | `rapidxml` 1415.59 | 0.672 | 1.00 | FAIL |
| `cd_catalog.xml` | 1012.19 | `rapidxml` 1398.93 | 0.724 | 1.00 | FAIL |
| `hnrss.xml` | 3569.97 | `pugixml` 2636.51 | 1.354 | 1.00 | PASS |
| `xkcd_rss.xml` | 3810.56 | `pugixml` 2378.29 | 1.602 | 1.00 | PASS |
| `bbc_world.xml` | 2174.73 | `pugixml` 2383.35 | 0.912 | 1.00 | FAIL |
| `arxiv_cs.xml` | 4213.30 | `pugixml` 2165.70 | 1.945 | 1.00 | PASS |
| `ecb_usd.xml` | 2196.61 | `pugixml` 2430.66 | 0.904 | 1.00 | FAIL |
| `planetpython.xml` | 26871.77 | `rapidxml` 1485.42 | 18.090 | 1.00 | PASS |
| `pugixml_large.xml` | 915.00 | `pugixml` 427.63 | 2.140 | 1.00 | PASS |
| `weekly_utf8.xml` | 1399.72 | `rapidxml` 2164.75 | 0.647 | 1.00 | FAIL |
| `xgconsole.xml` | 1480.86 | `rapidxml` 2057.13 | 0.720 | 1.00 | FAIL |
| `synthetic_flat_attrs.xml` | 517.04 | `pugixml` 371.55 | 1.392 | 1.00 | PASS |
| `synthetic_deep_tree.xml` | 597.19 | `pugixml` 1010.13 | 0.591 | 1.00 | FAIL |
| `synthetic_entities.xml` | 2441.98 | `rapidxml` 640.37 | 3.813 | 1.00 | PASS |
| `synthetic_cdata_mix.xml` | 1410.38 | `pugixml` 808.53 | 1.744 | 1.00 | PASS |
| `synthetic_wide_siblings.xml` | 906.11 | `pugixml` 324.68 | 2.791 | 1.00 | PASS |
| `synthetic_namespace_mix.xml` | 1125.73 | `pugixml` 577.77 | 1.948 | 1.00 | PASS |
| `synthetic_long_names.xml` | 1875.10 | `rapidxml` 1288.79 | 1.455 | 1.00 | PASS |
| `synthetic_self_closing_swarm.xml` | 1072.15 | `pugixml` 476.42 | 2.250 | 1.00 | PASS |

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
