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

Source: `bench/results/latest.json` (`quick` profile).

## Latest Benchmark Snapshot

### Parse Throughput Comparison (MB/s)

| Fixture | ours-turbo | ours-strict | pugixml | rapidxml |
|---|---:|---:|---:|---:|
| `note.xml` | 1170.11 | 1060.49 | 829.67 | 1569.25 |
| `sitemaps.xml` | 1091.17 | 1084.37 | 1535.21 | 1585.14 |
| `plant_catalog.xml` | 1006.92 | 982.60 | 1229.45 | 1286.33 |
| `cd_catalog.xml` | 928.36 | 925.31 | 1164.95 | 1181.82 |
| `hnrss.xml` | 3306.84 | 2657.78 | 2437.26 | 1992.78 |
| `xkcd_rss.xml` | 3906.33 | 3838.17 | 2147.81 | 1516.18 |
| `bbc_world.xml` | 2395.03 | 2302.84 | 2258.04 | 1930.97 |
| `arxiv_cs.xml` | 4603.88 | 4369.39 | 2426.13 | 1373.40 |
| `ecb_usd.xml` | 2073.48 | 1972.84 | 2210.47 | 2056.29 |
| `pugixml_large.xml` | 797.86 | 772.52 | 410.83 | 264.68 |
| `weekly_utf8.xml` | 1256.17 | 1162.68 | 1710.31 | 1884.66 |
| `xgconsole.xml` | 1336.10 | 1281.95 | 1600.47 | 1782.54 |
| `synthetic_flat_attrs.xml` | 579.95 | 564.07 | 360.82 | 290.69 |
| `synthetic_deep_tree.xml` | 602.21 | 694.50 | 1016.74 | 426.38 |
| `synthetic_entities.xml` | 2552.46 | 2267.88 | 453.66 | 699.70 |
| `synthetic_cdata_mix.xml` | 1381.92 | 1335.22 | 732.06 | 736.21 |
| `synthetic_wide_siblings.xml` | 881.62 | 866.07 | 367.37 | 262.80 |
| `synthetic_namespace_mix.xml` | 1112.54 | 1065.37 | 578.21 | 418.57 |
| `synthetic_long_names.xml` | 1731.13 | 1400.64 | 1208.38 | 1279.59 |
| `synthetic_self_closing_swarm.xml` | 1017.07 | 1010.57 | 498.31 | 356.29 |

### Stable Gates

| Fixture | ours-turbo | best external | ours/best-ext | Result |
|---|---:|---|---:|---|
| `note.xml` | 1170.11 | `rapidxml` 1569.25 | 0.746 | FAIL |
| `sitemaps.xml` | 1091.17 | `rapidxml` 1585.14 | 0.688 | FAIL |
| `plant_catalog.xml` | 1006.92 | `rapidxml` 1286.33 | 0.783 | FAIL |
| `cd_catalog.xml` | 928.36 | `rapidxml` 1181.82 | 0.786 | FAIL |
| `hnrss.xml` | 3306.84 | `pugixml` 2437.26 | 1.357 | PASS |
| `xkcd_rss.xml` | 3906.33 | `pugixml` 2147.81 | 1.819 | PASS |
| `bbc_world.xml` | 2395.03 | `pugixml` 2258.04 | 1.061 | PASS |
| `arxiv_cs.xml` | 4603.88 | `pugixml` 2426.13 | 1.898 | PASS |
| `ecb_usd.xml` | 2073.48 | `pugixml` 2210.47 | 0.938 | FAIL |
| `pugixml_large.xml` | 797.86 | `pugixml` 410.83 | 1.942 | PASS |
| `weekly_utf8.xml` | 1256.17 | `rapidxml` 1884.66 | 0.667 | FAIL |
| `xgconsole.xml` | 1336.10 | `rapidxml` 1782.54 | 0.750 | FAIL |
| `synthetic_flat_attrs.xml` | 579.95 | `pugixml` 360.82 | 1.607 | PASS |
| `synthetic_deep_tree.xml` | 602.21 | `pugixml` 1016.74 | 0.592 | FAIL |
| `synthetic_entities.xml` | 2552.46 | `rapidxml` 699.70 | 3.648 | PASS |
| `synthetic_cdata_mix.xml` | 1381.92 | `rapidxml` 736.21 | 1.877 | PASS |
| `synthetic_wide_siblings.xml` | 881.62 | `pugixml` 367.37 | 2.400 | PASS |
| `synthetic_namespace_mix.xml` | 1112.54 | `pugixml` 578.21 | 1.924 | PASS |
| `synthetic_long_names.xml` | 1731.13 | `rapidxml` 1279.59 | 1.353 | PASS |
| `synthetic_self_closing_swarm.xml` | 1017.07 | `pugixml` 498.31 | 2.041 | PASS |

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
