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
| `note.xml` | 2097.27 | 1989.11 | 979.08 | 1813.56 |
| `sitemaps.xml` | 1957.99 | 2047.59 | 1752.85 | 1782.99 |
| `plant_catalog.xml` | 1985.15 | 1935.04 | 1416.82 | 1437.87 |
| `cd_catalog.xml` | 1781.88 | 1781.86 | 1249.53 | 1432.57 |
| `hnrss.xml` | 5127.43 | 4631.72 | 2728.87 | 2216.91 |
| `xkcd_rss.xml` | 6036.43 | 5590.78 | 2362.12 | 1694.34 |
| `bbc_world.xml` | 3434.49 | 3251.55 | 2484.95 | 2239.45 |
| `arxiv_cs.xml` | 6615.98 | 6443.63 | 2624.73 | 1595.60 |
| `ecb_usd.xml` | 3999.94 | 3730.37 | 2518.68 | 2303.85 |
| `tree.xml` | 2159.41 | 2152.25 | 1276.97 | 2041.52 |
| `character.xml` | 2014.60 | 2001.53 | 1164.62 | 1920.21 |
| `transitions.xml` | 2124.91 | 2018.83 | 1295.53 | 1800.80 |
| `xgconsole.xml` | 2653.27 | 2637.51 | 1852.45 | 2102.27 |
| `weekly_utf8.xml` | 2418.87 | 2026.78 | 2039.26 | 2262.58 |
| `pugixml_large.xml` | 1632.24 | 1605.28 | 458.21 | 296.18 |
| `synthetic_flat_attrs.xml` | 1598.81 | 1572.41 | 421.89 | 330.75 |
| `synthetic_deep_tree.xml` | 1305.78 | 1235.19 | 1106.57 | 477.18 |
| `synthetic_entities.xml` | 3584.19 | 3645.91 | 510.56 | 767.57 |
| `synthetic_cdata_mix.xml` | 2287.52 | 2296.00 | 913.15 | 841.32 |
| `synthetic_wide_siblings.xml` | 1738.98 | 1736.70 | 412.50 | 278.94 |
| `synthetic_namespace_mix.xml` | 2477.06 | 2375.67 | 633.21 | 462.23 |
| `synthetic_long_names.xml` | 3991.65 | 3060.84 | 1175.76 | 1356.93 |
| `synthetic_self_closing_swarm.xml` | 2404.24 | 2400.76 | 564.04 | 443.15 |
| `synthetic_mixed_content.xml` | 1822.41 | 1770.24 | 571.30 | 465.89 |
| `synthetic_small_records.xml` | 1951.73 | 1576.40 | 384.36 | 294.65 |

### Stable Gates

| Fixture | ours-turbo | best external | ours/best-ext | Result |
|---|---:|---|---:|---|
| `note.xml` | 2097.27 | `rapidxml` 1813.56 | 1.156 | PASS |
| `sitemaps.xml` | 1957.99 | `rapidxml` 1782.99 | 1.098 | PASS |
| `plant_catalog.xml` | 1985.15 | `rapidxml` 1437.87 | 1.381 | PASS |
| `cd_catalog.xml` | 1781.88 | `rapidxml` 1432.57 | 1.244 | PASS |
| `hnrss.xml` | 5127.43 | `pugixml` 2728.87 | 1.879 | PASS |
| `xkcd_rss.xml` | 6036.43 | `pugixml` 2362.12 | 2.556 | PASS |
| `bbc_world.xml` | 3434.49 | `pugixml` 2484.95 | 1.382 | PASS |
| `arxiv_cs.xml` | 6615.98 | `pugixml` 2624.73 | 2.521 | PASS |
| `ecb_usd.xml` | 3999.94 | `pugixml` 2518.68 | 1.588 | PASS |
| `tree.xml` | 2159.41 | `rapidxml` 2041.52 | 1.058 | PASS |
| `character.xml` | 2014.60 | `rapidxml` 1920.21 | 1.049 | PASS |
| `transitions.xml` | 2124.91 | `rapidxml` 1800.80 | 1.180 | PASS |
| `xgconsole.xml` | 2653.27 | `rapidxml` 2102.27 | 1.262 | PASS |
| `weekly_utf8.xml` | 2418.87 | `rapidxml` 2262.58 | 1.069 | PASS |
| `pugixml_large.xml` | 1632.24 | `pugixml` 458.21 | 3.562 | PASS |
| `synthetic_flat_attrs.xml` | 1598.81 | `pugixml` 421.89 | 3.790 | PASS |
| `synthetic_deep_tree.xml` | 1305.78 | `pugixml` 1106.57 | 1.180 | PASS |
| `synthetic_entities.xml` | 3584.19 | `rapidxml` 767.57 | 4.670 | PASS |
| `synthetic_cdata_mix.xml` | 2287.52 | `pugixml` 913.15 | 2.505 | PASS |
| `synthetic_wide_siblings.xml` | 1738.98 | `pugixml` 412.50 | 4.216 | PASS |
| `synthetic_namespace_mix.xml` | 2477.06 | `pugixml` 633.21 | 3.912 | PASS |
| `synthetic_long_names.xml` | 3991.65 | `rapidxml` 1356.93 | 2.942 | PASS |
| `synthetic_self_closing_swarm.xml` | 2404.24 | `pugixml` 564.04 | 4.263 | PASS |
| `synthetic_mixed_content.xml` | 1822.41 | `pugixml` 571.30 | 3.190 | PASS |
| `synthetic_small_records.xml` | 1951.73 | `pugixml` 384.36 | 5.078 | PASS |

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
