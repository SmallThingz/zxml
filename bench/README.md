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

Source: `bench/results/latest.json` (`quick` profile).

## Latest Benchmark Snapshot

### Parse Throughput Comparison (MB/s)

| Fixture | ours-turbo | ours-strict | pugixml | rapidxml |
|---|---:|---:|---:|---:|
| `note.xml` | 2138.11 | 1670.62 | 1002.18 | 1875.52 |
| `sitemaps.xml` | 2106.51 | 1773.01 | 1857.15 | 1882.49 |
| `plant_catalog.xml` | 2075.27 | 1386.78 | 1435.43 | 1472.30 |
| `cd_catalog.xml` | 1881.80 | 1395.01 | 1345.78 | 1518.21 |
| `hnrss.xml` | 5344.65 | 3616.23 | 2794.01 | 2241.38 |
| `xkcd_rss.xml` | 6477.93 | 2156.18 | 2485.34 | 1816.39 |
| `bbc_world.xml` | 3662.29 | 2658.84 | 2549.75 | 2242.66 |
| `arxiv_cs.xml` | 7048.81 | 4586.39 | 2603.40 | 1557.34 |
| `ecb_usd.xml` | 4235.08 | 2771.78 | 2596.37 | 2335.46 |
| `pugixml_large.xml` | 1744.36 | 1360.61 | 453.04 | 289.14 |
| `weekly_utf8.xml` | 2516.25 | 1880.34 | 2100.27 | 2314.12 |
| `xgconsole.xml` | 2903.11 | 1901.38 | 1904.38 | 2145.26 |
| `synthetic_flat_attrs.xml` | 1618.57 | 924.41 | 426.60 | 326.37 |
| `synthetic_deep_tree.xml` | 1358.69 | 967.21 | 1154.35 | 474.71 |
| `synthetic_entities.xml` | 3705.49 | 751.91 | 507.89 | 762.94 |
| `synthetic_cdata_mix.xml` | 2402.13 | 2064.21 | 898.18 | 821.95 |
| `synthetic_wide_siblings.xml` | 1825.50 | 1034.82 | 395.79 | 267.51 |
| `synthetic_namespace_mix.xml` | 2535.60 | 1457.34 | 619.51 | 486.99 |
| `synthetic_long_names.xml` | 4143.94 | 2237.34 | 1267.48 | 1337.55 |
| `synthetic_self_closing_swarm.xml` | 2511.97 | 1292.98 | 540.46 | 426.11 |

### Stable Gates

| Fixture | ours-turbo | best external | ours/best-ext | Result |
|---|---:|---|---:|---|
| `note.xml` | 2138.11 | `rapidxml` 1875.52 | 1.140 | PASS |
| `sitemaps.xml` | 2106.51 | `rapidxml` 1882.49 | 1.119 | PASS |
| `plant_catalog.xml` | 2075.27 | `rapidxml` 1472.30 | 1.410 | PASS |
| `cd_catalog.xml` | 1881.80 | `rapidxml` 1518.21 | 1.239 | PASS |
| `hnrss.xml` | 5344.65 | `pugixml` 2794.01 | 1.913 | PASS |
| `xkcd_rss.xml` | 6477.93 | `pugixml` 2485.34 | 2.606 | PASS |
| `bbc_world.xml` | 3662.29 | `pugixml` 2549.75 | 1.436 | PASS |
| `arxiv_cs.xml` | 7048.81 | `pugixml` 2603.40 | 2.708 | PASS |
| `ecb_usd.xml` | 4235.08 | `pugixml` 2596.37 | 1.631 | PASS |
| `pugixml_large.xml` | 1744.36 | `pugixml` 453.04 | 3.850 | PASS |
| `weekly_utf8.xml` | 2516.25 | `rapidxml` 2314.12 | 1.087 | PASS |
| `xgconsole.xml` | 2903.11 | `rapidxml` 2145.26 | 1.353 | PASS |
| `synthetic_flat_attrs.xml` | 1618.57 | `pugixml` 426.60 | 3.794 | PASS |
| `synthetic_deep_tree.xml` | 1358.69 | `pugixml` 1154.35 | 1.177 | PASS |
| `synthetic_entities.xml` | 3705.49 | `rapidxml` 762.94 | 4.857 | PASS |
| `synthetic_cdata_mix.xml` | 2402.13 | `pugixml` 898.18 | 2.674 | PASS |
| `synthetic_wide_siblings.xml` | 1825.50 | `pugixml` 395.79 | 4.612 | PASS |
| `synthetic_namespace_mix.xml` | 2535.60 | `pugixml` 619.51 | 4.093 | PASS |
| `synthetic_long_names.xml` | 4143.94 | `rapidxml` 1337.55 | 3.098 | PASS |
| `synthetic_self_closing_swarm.xml` | 2511.97 | `pugixml` 540.46 | 4.648 | PASS |

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
