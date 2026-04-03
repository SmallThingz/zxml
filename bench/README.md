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
| `note.xml` | 1019.18 | 1776.74 | 535.90 | 870.68 |
| `sitemaps.xml` | 2331.31 | 1931.08 | 1846.56 | 1870.79 |
| `plant_catalog.xml` | 1939.67 | 1835.39 | 1413.97 | 1498.03 |
| `cd_catalog.xml` | 1867.57 | 1754.23 | 1277.89 | 1474.77 |
| `hnrss.xml` | 4940.86 | 4017.45 | 2465.41 | 2029.10 |
| `xkcd_rss.xml` | 5780.61 | 5370.66 | 2461.17 | 1780.66 |
| `bbc_world.xml` | 3589.87 | 3296.06 | 2535.82 | 2273.56 |
| `arxiv_cs.xml` | 6968.61 | 6502.00 | 2678.96 | 1603.84 |
| `ecb_usd.xml` | 4000.52 | 3595.45 | 2585.43 | 2368.31 |
| `tree.xml` | 2254.87 | 2060.13 | 1306.02 | 2076.02 |
| `character.xml` | 2058.23 | 1886.63 | 1207.00 | 2002.20 |
| `transitions.xml` | 2189.15 | 1901.01 | 1351.64 | 1850.87 |
| `xgconsole.xml` | 2584.43 | 2481.32 | 1896.75 | 2122.33 |
| `weekly_utf8.xml` | 2550.71 | 2044.05 | 2089.37 | 2302.18 |
| `pugixml_large.xml` | 1646.29 | 1620.84 | 457.85 | 293.38 |
| `synthetic_flat_attrs.xml` | 1265.77 | 1265.13 | 425.04 | 328.22 |
| `synthetic_deep_tree.xml` | 1175.40 | 1112.23 | 1127.79 | 477.93 |
| `synthetic_entities.xml` | 3345.85 | 3242.16 | 514.09 | 778.24 |
| `synthetic_cdata_mix.xml` | 2227.17 | 2187.55 | 914.79 | 840.55 |
| `synthetic_wide_siblings.xml` | 1605.17 | 1566.49 | 414.14 | 282.41 |
| `synthetic_namespace_mix.xml` | 2185.59 | 2091.83 | 646.10 | 483.55 |
| `synthetic_long_names.xml` | 3634.03 | 3000.93 | 1270.63 | 1359.75 |
| `synthetic_self_closing_swarm.xml` | 2010.58 | 2036.99 | 524.95 | 397.51 |
| `synthetic_mixed_content.xml` | 1859.69 | 1758.16 | 598.21 | 438.17 |
| `synthetic_small_records.xml` | 1732.07 | 1584.43 | 389.82 | 280.47 |

### Stable Gates

| Fixture | ours-turbo | best external | ours/best-ext | Result |
|---|---:|---|---:|---|
| `note.xml` | 1019.18 | `rapidxml` 870.68 | 1.171 | PASS |
| `sitemaps.xml` | 2331.31 | `rapidxml` 1870.79 | 1.246 | PASS |
| `plant_catalog.xml` | 1939.67 | `rapidxml` 1498.03 | 1.295 | PASS |
| `cd_catalog.xml` | 1867.57 | `rapidxml` 1474.77 | 1.266 | PASS |
| `hnrss.xml` | 4940.86 | `pugixml` 2465.41 | 2.004 | PASS |
| `xkcd_rss.xml` | 5780.61 | `pugixml` 2461.17 | 2.349 | PASS |
| `bbc_world.xml` | 3589.87 | `pugixml` 2535.82 | 1.416 | PASS |
| `arxiv_cs.xml` | 6968.61 | `pugixml` 2678.96 | 2.601 | PASS |
| `ecb_usd.xml` | 4000.52 | `pugixml` 2585.43 | 1.547 | PASS |
| `tree.xml` | 2254.87 | `rapidxml` 2076.02 | 1.086 | PASS |
| `character.xml` | 2058.23 | `rapidxml` 2002.20 | 1.028 | PASS |
| `transitions.xml` | 2189.15 | `rapidxml` 1850.87 | 1.183 | PASS |
| `xgconsole.xml` | 2584.43 | `rapidxml` 2122.33 | 1.218 | PASS |
| `weekly_utf8.xml` | 2550.71 | `rapidxml` 2302.18 | 1.108 | PASS |
| `pugixml_large.xml` | 1646.29 | `pugixml` 457.85 | 3.596 | PASS |
| `synthetic_flat_attrs.xml` | 1265.77 | `pugixml` 425.04 | 2.978 | PASS |
| `synthetic_deep_tree.xml` | 1175.40 | `pugixml` 1127.79 | 1.042 | PASS |
| `synthetic_entities.xml` | 3345.85 | `rapidxml` 778.24 | 4.299 | PASS |
| `synthetic_cdata_mix.xml` | 2227.17 | `pugixml` 914.79 | 2.435 | PASS |
| `synthetic_wide_siblings.xml` | 1605.17 | `pugixml` 414.14 | 3.876 | PASS |
| `synthetic_namespace_mix.xml` | 2185.59 | `pugixml` 646.10 | 3.383 | PASS |
| `synthetic_long_names.xml` | 3634.03 | `rapidxml` 1359.75 | 2.673 | PASS |
| `synthetic_self_closing_swarm.xml` | 2010.58 | `pugixml` 524.95 | 3.830 | PASS |
| `synthetic_mixed_content.xml` | 1859.69 | `pugixml` 598.21 | 3.109 | PASS |
| `synthetic_small_records.xml` | 1732.07 | `pugixml` 389.82 | 4.443 | PASS |

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
