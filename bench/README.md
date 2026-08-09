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
| `note.xml` | 2246.64 | 2203.02 | 2951.95 | 2700.44 | 1002.87 | 1702.45 |
| `sitemaps.xml` | 2269.78 | 2002.97 | 2976.85 | 2551.08 | 1814.43 | 1889.63 |
| `plant_catalog.xml` | 2124.10 | 2003.97 | 2852.30 | 2658.77 | 1441.12 | 1486.15 |
| `cd_catalog.xml` | 1884.82 | 1985.89 | 2842.52 | 2537.18 | 1332.25 | 1532.43 |
| `hnrss.xml` | 5670.05 | 5153.91 | 6624.73 | 5828.62 | 2918.66 | 2293.47 |
| `xkcd_rss.xml` | 6560.77 | 6018.59 | 8035.08 | 6963.42 | 2353.46 | 1824.11 |
| `bbc_world.xml` | 3826.30 | 3506.88 | 4975.32 | 4614.82 | 2476.21 | 2277.90 |
| `arxiv_cs.xml` | 2824.22 | 2715.67 | 3726.99 | 3244.44 | 1933.35 | 2142.85 |
| `ecb_usd.xml` | 4291.38 | 4013.57 | 5199.98 | 4523.30 | 2566.45 | 2357.16 |
| `tree.xml` | 2284.02 | 2235.85 | 2843.86 | 2572.18 | 1174.28 | 2059.58 |
| `character.xml` | 2089.65 | 1997.84 | 2742.67 | 2554.98 | 1130.67 | 1915.82 |
| `transitions.xml` | 2178.46 | 2024.65 | 2958.93 | 2527.19 | 1286.05 | 1769.70 |
| `xgconsole.xml` | 2760.70 | 2583.28 | 3777.38 | 3319.87 | 1864.50 | 2131.81 |
| `weekly_utf8.xml` | 2607.99 | 2322.50 | 3286.31 | 2653.23 | 2052.88 | 2264.44 |
| `pugixml_large.xml` | 1860.60 | 1977.08 | 2223.74 | 2219.29 | 482.26 | 297.87 |
| `synthetic_flat_attrs.xml` | 1413.21 | 1270.53 | 1913.98 | 1990.56 | 429.83 | 329.61 |
| `synthetic_deep_tree.xml` | 1288.99 | 1149.13 | 2224.66 | 1686.57 | 1163.06 | 474.13 |
| `synthetic_entities.xml` | 3568.50 | 3359.93 | 4704.74 | 4474.26 | 513.36 | 811.27 |
| `synthetic_cdata_mix.xml` | 2508.22 | 2448.52 | 2905.19 | 2804.49 | 912.74 | 858.65 |
| `synthetic_wide_siblings.xml` | 1631.68 | 1682.41 | 2568.66 | 2369.63 | 417.94 | 304.06 |
| `synthetic_namespace_mix.xml` | 2543.01 | 2240.60 | 3327.41 | 2923.36 | 658.55 | 528.63 |
| `synthetic_long_names.xml` | 3860.81 | 3575.96 | 4835.35 | 4235.84 | 1329.72 | 1398.71 |
| `synthetic_self_closing_swarm.xml` | 2403.55 | 2159.90 | 3160.69 | 3038.59 | 578.94 | 471.45 |
| `synthetic_mixed_content.xml` | 2142.44 | 2124.43 | 2717.55 | 2485.38 | 640.49 | 501.67 |
| `synthetic_small_records.xml` | 2132.76 | 1984.97 | 2865.65 | 2494.29 | 434.56 | 319.20 |

### Stable Gates

| Fixture | ours-turbo | best external | ours/best-ext | Result |
|---|---:|---|---:|---|
| `note.xml` | 2246.64 | `rapidxml` 1702.45 | 1.320 | PASS |
| `sitemaps.xml` | 2269.78 | `rapidxml` 1889.63 | 1.201 | PASS |
| `plant_catalog.xml` | 2124.10 | `rapidxml` 1486.15 | 1.429 | PASS |
| `cd_catalog.xml` | 1884.82 | `rapidxml` 1532.43 | 1.230 | PASS |
| `hnrss.xml` | 5670.05 | `pugixml` 2918.66 | 1.943 | PASS |
| `xkcd_rss.xml` | 6560.77 | `pugixml` 2353.46 | 2.788 | PASS |
| `bbc_world.xml` | 3826.30 | `pugixml` 2476.21 | 1.545 | PASS |
| `arxiv_cs.xml` | 2824.22 | `rapidxml` 2142.85 | 1.318 | PASS |
| `ecb_usd.xml` | 4291.38 | `pugixml` 2566.45 | 1.672 | PASS |
| `tree.xml` | 2284.02 | `rapidxml` 2059.58 | 1.109 | PASS |
| `character.xml` | 2089.65 | `rapidxml` 1915.82 | 1.091 | PASS |
| `transitions.xml` | 2178.46 | `rapidxml` 1769.70 | 1.231 | PASS |
| `xgconsole.xml` | 2760.70 | `rapidxml` 2131.81 | 1.295 | PASS |
| `weekly_utf8.xml` | 2607.99 | `rapidxml` 2264.44 | 1.152 | PASS |
| `pugixml_large.xml` | 1860.60 | `pugixml` 482.26 | 3.858 | PASS |
| `synthetic_flat_attrs.xml` | 1413.21 | `pugixml` 429.83 | 3.288 | PASS |
| `synthetic_deep_tree.xml` | 1288.99 | `pugixml` 1163.06 | 1.108 | PASS |
| `synthetic_entities.xml` | 3568.50 | `rapidxml` 811.27 | 4.399 | PASS |
| `synthetic_cdata_mix.xml` | 2508.22 | `pugixml` 912.74 | 2.748 | PASS |
| `synthetic_wide_siblings.xml` | 1631.68 | `pugixml` 417.94 | 3.904 | PASS |
| `synthetic_namespace_mix.xml` | 2543.01 | `pugixml` 658.55 | 3.862 | PASS |
| `synthetic_long_names.xml` | 3860.81 | `rapidxml` 1398.71 | 2.760 | PASS |
| `synthetic_self_closing_swarm.xml` | 2403.55 | `pugixml` 578.94 | 4.152 | PASS |
| `synthetic_mixed_content.xml` | 2142.44 | `pugixml` 640.49 | 3.345 | PASS |
| `synthetic_small_records.xml` | 2132.76 | `pugixml` 434.56 | 4.908 | PASS |

### Streaming Gates

| Fixture | stream-turbo | ours-turbo | stream/ours | stream-strict | ours-strict | stream/ours | Result |
|---|---:|---:|---:|---:|---:|---:|---|
| `note.xml` | 2951.95 | 2246.64 | 1.314 | 2700.44 | 2203.02 | 1.226 | PASS |
| `sitemaps.xml` | 2976.85 | 2269.78 | 1.312 | 2551.08 | 2002.97 | 1.274 | PASS |
| `plant_catalog.xml` | 2852.30 | 2124.10 | 1.343 | 2658.77 | 2003.97 | 1.327 | PASS |
| `cd_catalog.xml` | 2842.52 | 1884.82 | 1.508 | 2537.18 | 1985.89 | 1.278 | PASS |
| `hnrss.xml` | 6624.73 | 5670.05 | 1.168 | 5828.62 | 5153.91 | 1.131 | PASS |
| `xkcd_rss.xml` | 8035.08 | 6560.77 | 1.225 | 6963.42 | 6018.59 | 1.157 | PASS |
| `bbc_world.xml` | 4975.32 | 3826.30 | 1.300 | 4614.82 | 3506.88 | 1.316 | PASS |
| `arxiv_cs.xml` | 3726.99 | 2824.22 | 1.320 | 3244.44 | 2715.67 | 1.195 | PASS |
| `ecb_usd.xml` | 5199.98 | 4291.38 | 1.212 | 4523.30 | 4013.57 | 1.127 | PASS |
| `tree.xml` | 2843.86 | 2284.02 | 1.245 | 2572.18 | 2235.85 | 1.150 | PASS |
| `character.xml` | 2742.67 | 2089.65 | 1.313 | 2554.98 | 1997.84 | 1.279 | PASS |
| `transitions.xml` | 2958.93 | 2178.46 | 1.358 | 2527.19 | 2024.65 | 1.248 | PASS |
| `xgconsole.xml` | 3777.38 | 2760.70 | 1.368 | 3319.87 | 2583.28 | 1.285 | PASS |
| `weekly_utf8.xml` | 3286.31 | 2607.99 | 1.260 | 2653.23 | 2322.50 | 1.142 | PASS |
| `pugixml_large.xml` | 2223.74 | 1860.60 | 1.195 | 2219.29 | 1977.08 | 1.123 | PASS |
| `synthetic_flat_attrs.xml` | 1913.98 | 1413.21 | 1.354 | 1990.56 | 1270.53 | 1.567 | PASS |
| `synthetic_deep_tree.xml` | 2224.66 | 1288.99 | 1.726 | 1686.57 | 1149.13 | 1.468 | PASS |
| `synthetic_entities.xml` | 4704.74 | 3568.50 | 1.318 | 4474.26 | 3359.93 | 1.332 | PASS |
| `synthetic_cdata_mix.xml` | 2905.19 | 2508.22 | 1.158 | 2804.49 | 2448.52 | 1.145 | PASS |
| `synthetic_wide_siblings.xml` | 2568.66 | 1631.68 | 1.574 | 2369.63 | 1682.41 | 1.408 | PASS |
| `synthetic_namespace_mix.xml` | 3327.41 | 2543.01 | 1.308 | 2923.36 | 2240.60 | 1.305 | PASS |
| `synthetic_long_names.xml` | 4835.35 | 3860.81 | 1.252 | 4235.84 | 3575.96 | 1.185 | PASS |
| `synthetic_self_closing_swarm.xml` | 3160.69 | 2403.55 | 1.315 | 3038.59 | 2159.90 | 1.407 | PASS |
| `synthetic_mixed_content.xml` | 2717.55 | 2142.44 | 1.268 | 2485.38 | 2124.43 | 1.170 | PASS |
| `synthetic_small_records.xml` | 2865.65 | 2132.76 | 1.344 | 2494.29 | 1984.97 | 1.257 | PASS |

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
