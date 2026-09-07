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
# full 37-fixture comparison, optimized for day-to-day runs
zig build bench-compare

# publication-grade 37-fixture comparison
zig build bench-compare -- --profile stable
zig build bench-interleaved -- ../zxml-base ../zxml-candidate --profile quick --repeats 9 --core-a 0 --core-b 2
zig build conformance

# direct tool invocation after setup, when needed
zig build tools -- run-benchmarks --profile quick
zig build tools -- run-benchmarks --profile full
zig build tools -- run-benchmarks --profile stable
zig-out/bin/zxml-tools run-benchmarks --profile stable --no-build --guard-fixtures
```

`full` and `stable` cover the same 37 headline fixtures and compute the same external and validated-pathology comparisons. `full` is the default developer profile: three samples targeted at 5 ms each, scaled-down calibration hints, and reuse of an in-range calibration measurement as sample 1. `stable` remains the publication profile: five independent samples targeted at 40 ms each and hard-fails its gates. `full` reports gate failures but does not make them fatal because its short samples are intended for fast feedback. `quick` keeps its smaller fixture subset.

Developer profiles also reuse already-built pugixml/rapidxml runners when their runner sources and parser headers are older than the binaries. `stable` always rebuilds both external runners so publication evidence never depends on a stale C++ artifact.

A successful `stable` run also updates:

- `README.md` auto-summary block
- `bench/README.md` latest benchmark snapshot block

`full` writes `bench/results/full.{json,md}` for the developer run and leaves `latest.{json,md}` plus the publication README snapshots untouched.

For a frozen-binary measurement, build the runners first and use `zig-out/bin/zxml-tools run-benchmarks --profile stable --no-build` inside the quiet-host guard. This skips compilation, not parsing or validation; the caller must verify that all four runner binaries match the intended source revision.

Results are written to:

- `bench/results/full.json` and `full.md` for the default `full` profile
- `bench/results/latest.json` and `latest.md` for `stable` (and the smaller legacy profiles)

Headline DOM benchmarks instantiate the actual generated parser types: `permissive` is `ParseOptions{}` and `validated` sets only `validate_well_formedness = true`. Misc-node storage is not silently enabled. The benchmark workflow follows zhtml. zxml keeps input/setup outside the timed region and constructs and frees a fresh generated `Document` in every timed iteration. Parser scratch and node growth are included; finished node capacity is not retained between DOM parses. Streaming reuses its generated parser state. An optimization barrier keeps each completed DOM observable before destruction. The node-only DOM uses parent links for nesting and no attribute-record array. Its small-document inline node buffer is rebuilt on each iteration, not retained across parses. The default permissive DOM may reject raw `>` within a quoted attribute value; the validated policy preserves that grammar. Corpus membership and external gates are unchanged. External runners use their native repeat-parse lifecycle. zxml runners are
built with `ReleaseFast -Dcpu=native`; C++ runners use `-O3 -DNDEBUG -march=native`.
The harness uses a system `c++` driver when available and falls back to `zig c++`
on minimal hosts. Each generated report records the kernel, architecture, CPU model,
frequency-scaling state, advertised CPU MHz range, Zig version, and C++ driver.

On a shared Linux host, `--no-build --guard-fixtures` collects each fixture in an
independent clean window using `host-quiet`, `guarded-run`, and CPU6 via `taskset`.
The guard covers calibration and every interleaved sample round for each applicable parser. `full` uses three rounds; `stable` uses five. Exit 75 discards that entire fixture attempt and retries it;
other failures stop collection. Parser/fixture coverage, lifecycle, exclusions,
and performance gates are unchanged. JSON records `guarded_fixtures: true`, and
Markdown identifies this collection mode. This is not one continuous quiet run.

Guarded collection neither reads nor writes timing checkpoints and cannot be
combined with `--resume` or runner compilation. The older `--resume` option is
not a contamination guard: never reuse a checkpoint from a contaminated run.

The default node-only fast path may reject literal `>` in quoted attribute values; full validated mode retains that syntax. A passing external gate does not establish the original absolute throughput objectives; see [validation](VALIDATION.md).

Fixture setup rejects extremely opaque feeds. `synthetic_long_text.xml` remains
a generated diagnostic-only fixture and is excluded from quick/full/stable profiles.
`synthetic_doctype_entities.xml` is also excluded from headline profiles and
external gates; full and stable runs exercise it only in the validated-only regression lane.
That lane compares it against `synthetic_entities_reference.xml`, a deliberately
non-repeating ordinary-entity workload so exact-repeat DOM acceleration cannot
artificially inflate the denominator. The 1.25x minimum ratio is unchanged. Detailed
regression timings stay out of the human benchmark tables and remain available only
in `bench/results/latest.json`.

<!-- BENCH_README_AUTO_SNAPSHOT:START -->

Source: `bench/results/latest.json` (`stable` profile).

## Latest Benchmark Snapshot

### Benchmark Environment

| Property | Value |
|---|---|
| OS / kernel | Linux 7.2.2-zen1-1-zen |
| Architecture | x86_64 |
| CPU | 12th Gen Intel(R) Core(TM) i5-12450H |
| CPU frequency scaling | 61% |
| CPU MHz range | 400.0000–4400.0000 |
| Zig | 0.16.0 (`ReleaseFast -Dcpu=native`) |
| C++ driver | c++ (`-O3 -DNDEBUG -march=native`) |

### Parse Throughput Comparison (MB/s)

| Fixture | ours-permissive | ours-validated | stream-permissive | stream-validated | pugixml | rapidxml |
|---|---:|---:|---:|---:|---:|---:|
| `note.xml` | 2896.59 | 1700.81 | 3397.09 | 1359.56 | 1004.39 | 1777.77 |
| `sitemaps.xml` | 4143.51 | 2064.18 | 3585.86 | 1718.95 | 2005.55 | 2016.09 |
| `plant_catalog.xml` | 3693.96 | 1864.61 | 3125.16 | 1523.58 | 1568.34 | 1744.29 |
| `cd_catalog.xml` | 3389.45 | 1757.73 | 2801.73 | 1388.91 | 1510.87 | 1636.23 |
| `hnrss.xml` | 10064.06 | 5541.31 | 8372.60 | 4309.44 | 3014.61 | 2706.89 |
| `xkcd_rss.xml` | 8720.08 | 4140.86 | 8617.95 | 3208.49 | 2519.39 | 2588.01 |
| `bbc_world.xml` | 6130.75 | 3470.61 | 5034.80 | 3103.76 | 2654.27 | 2561.68 |
| `arxiv_cs.xml` | 8499.86 | 4160.02 | 10331.91 | 4507.49 | 2738.87 | 1929.20 |
| `ecb_usd.xml` | 6787.37 | 3253.73 | 5249.54 | 2794.58 | 2765.87 | 2824.94 |
| `tree.xml` | 3169.99 | 1476.76 | 2803.41 | 1439.60 | 1304.25 | 2115.65 |
| `character.xml` | 3291.46 | 1387.48 | 2545.73 | 1427.26 | 1101.20 | 2021.02 |
| `transitions.xml` | 3576.53 | - | 2243.44 | - | 1404.53 | 2176.05 |
| `xgconsole.xml` | 6079.60 | 2027.04 | 3788.93 | 1341.56 | 1913.95 | 2517.80 |
| `weekly_utf8.xml` | 3730.22 | 1291.42 | 3272.71 | 689.53 | 2282.23 | 2461.79 |
| `pugixml_large.xml` | 2636.98 | 1520.66 | 2165.66 | 1705.47 | 495.04 | 317.60 |
| `synthetic_flat_attrs.xml` | 6967.31 | 1349.42 | 2784.60 | 1013.17 | 485.24 | 382.07 |
| `synthetic_deep_tree.xml` | 1949.86 | 1196.36 | 1525.05 | 1046.97 | 1335.70 | 803.21 |
| `synthetic_entities.xml` | 10747.98 | 10631.20 | 6031.90 | 848.00 | 952.89 | 967.42 |
| `synthetic_cdata_mix.xml` | 2442.64 | 1826.01 | 3007.99 | 1783.90 | 697.09 | 537.14 |
| `synthetic_wide_siblings.xml` | 1236.34 | 963.56 | 2362.38 | 976.39 | 421.00 | 310.13 |
| `synthetic_namespace_mix.xml` | 3835.42 | 1469.58 | 3302.78 | 1525.50 | 719.81 | 593.40 |
| `synthetic_long_names.xml` | 6786.15 | 3379.33 | 4827.34 | 2553.45 | 1388.39 | 1701.42 |
| `synthetic_self_closing_swarm.xml` | 4781.37 | 1261.78 | 3411.99 | 1461.59 | 630.78 | 524.63 |
| `synthetic_mixed_content.xml` | 2340.58 | 1383.38 | 3021.33 | 1348.66 | 545.16 | 398.08 |
| `synthetic_small_records.xml` | 1896.25 | 1299.81 | 2612.33 | 1260.37 | 422.98 | 297.44 |
| `synthetic_tiny_empty.xml` | 1703.60 | 1718.34 | 1565.09 | 1288.58 | 191.78 | 118.46 |
| `synthetic_tiny_text.xml` | 1773.60 | 1764.77 | 1344.36 | 697.94 | 179.39 | 122.31 |
| `synthetic_one_attr.xml` | 3727.10 | 3699.31 | 1816.53 | 1091.93 | 284.39 | 189.07 |
| `synthetic_two_attr.xml` | 5588.00 | 5547.62 | 2052.47 | 1073.86 | 312.37 | 220.78 |
| `synthetic_attrs4.xml` | 8607.36 | 8472.63 | 2346.34 | 970.10 | 338.39 | 248.75 |
| `synthetic_attrs8.xml` | 12911.00 | 12530.89 | 2468.69 | 947.13 | 335.35 | 255.90 |
| `synthetic_single_quotes.xml` | 10097.03 | 9964.43 | 3058.01 | 1272.07 | 533.26 | 425.13 |
| `synthetic_unicode_names.xml` | 8587.17 | 8476.01 | 3418.14 | 568.14 | 653.29 | 551.73 |
| `synthetic_pretty_indented.xml` | 1930.66 | 1355.12 | 2439.05 | 1245.59 | 523.17 | 414.64 |
| `synthetic_crlf_pretty.xml` | 2016.92 | 1150.47 | 2925.20 | 1261.10 | 503.59 | 422.12 |
| `synthetic_token_whitespace_mix.xml` | 9248.32 | 8987.29 | 1439.68 | 967.24 | 406.32 | 368.87 |
| `synthetic_attr_count_mix.xml` | 6789.05 | 1427.08 | 2849.51 | 1067.51 | 392.92 | 308.65 |

### Stable Gates

| Fixture | ours-permissive | best external | ours/best-ext | Result |
|---|---:|---|---:|---|
| `note.xml` | 2896.59 | `rapidxml` 1777.77 | 1.629 | PASS |
| `sitemaps.xml` | 4143.51 | `rapidxml` 2016.09 | 2.055 | PASS |
| `plant_catalog.xml` | 3693.96 | `rapidxml` 1744.29 | 2.118 | PASS |
| `cd_catalog.xml` | 3389.45 | `rapidxml` 1636.23 | 2.072 | PASS |
| `hnrss.xml` | 10064.06 | `pugixml` 3014.61 | 3.338 | PASS |
| `xkcd_rss.xml` | 8720.08 | `rapidxml` 2588.01 | 3.369 | PASS |
| `bbc_world.xml` | 6130.75 | `pugixml` 2654.27 | 2.310 | PASS |
| `arxiv_cs.xml` | 8499.86 | `pugixml` 2738.87 | 3.103 | PASS |
| `ecb_usd.xml` | 6787.37 | `rapidxml` 2824.94 | 2.403 | PASS |
| `tree.xml` | 3169.99 | `rapidxml` 2115.65 | 1.498 | PASS |
| `character.xml` | 3291.46 | `rapidxml` 2021.02 | 1.629 | PASS |
| `transitions.xml` | 3576.53 | `rapidxml` 2176.05 | 1.644 | PASS |
| `xgconsole.xml` | 6079.60 | `rapidxml` 2517.80 | 2.415 | PASS |
| `weekly_utf8.xml` | 3730.22 | `rapidxml` 2461.79 | 1.515 | PASS |
| `pugixml_large.xml` | 2636.98 | `pugixml` 495.04 | 5.327 | PASS |
| `synthetic_flat_attrs.xml` | 6967.31 | `pugixml` 485.24 | 14.359 | PASS |
| `synthetic_deep_tree.xml` | 1949.86 | `pugixml` 1335.70 | 1.460 | PASS |
| `synthetic_entities.xml` | 10747.98 | `rapidxml` 967.42 | 11.110 | PASS |
| `synthetic_cdata_mix.xml` | 2442.64 | `pugixml` 697.09 | 3.504 | PASS |
| `synthetic_wide_siblings.xml` | 1236.34 | `pugixml` 421.00 | 2.937 | PASS |
| `synthetic_namespace_mix.xml` | 3835.42 | `pugixml` 719.81 | 5.328 | PASS |
| `synthetic_long_names.xml` | 6786.15 | `rapidxml` 1701.42 | 3.989 | PASS |
| `synthetic_self_closing_swarm.xml` | 4781.37 | `pugixml` 630.78 | 7.580 | PASS |
| `synthetic_mixed_content.xml` | 2340.58 | `pugixml` 545.16 | 4.293 | PASS |
| `synthetic_small_records.xml` | 1896.25 | `pugixml` 422.98 | 4.483 | PASS |
| `synthetic_tiny_empty.xml` | 1703.60 | `pugixml` 191.78 | 8.883 | PASS |
| `synthetic_tiny_text.xml` | 1773.60 | `pugixml` 179.39 | 9.887 | PASS |
| `synthetic_one_attr.xml` | 3727.10 | `pugixml` 284.39 | 13.106 | PASS |
| `synthetic_two_attr.xml` | 5588.00 | `pugixml` 312.37 | 17.889 | PASS |
| `synthetic_attrs4.xml` | 8607.36 | `pugixml` 338.39 | 25.436 | PASS |
| `synthetic_attrs8.xml` | 12911.00 | `pugixml` 335.35 | 38.500 | PASS |
| `synthetic_single_quotes.xml` | 10097.03 | `pugixml` 533.26 | 18.935 | PASS |
| `synthetic_unicode_names.xml` | 8587.17 | `pugixml` 653.29 | 13.145 | PASS |
| `synthetic_pretty_indented.xml` | 1930.66 | `pugixml` 523.17 | 3.690 | PASS |
| `synthetic_crlf_pretty.xml` | 2016.92 | `pugixml` 503.59 | 4.005 | PASS |
| `synthetic_token_whitespace_mix.xml` | 9248.32 | `pugixml` 406.32 | 22.761 | PASS |
| `synthetic_attr_count_mix.xml` | 6789.05 | `pugixml` 392.92 | 17.278 | PASS |

### Streaming Comparison (Advisory)

| Fixture | stream-permissive | ours-permissive | stream/ours | stream-validated | ours-validated | stream/ours |
|---|---:|---:|---:|---:|---:|---:|
| `note.xml` | 3397.09 | 2896.59 | 1.173 | 1359.56 | 1700.81 | 0.799 |
| `sitemaps.xml` | 3585.86 | 4143.51 | 0.865 | 1718.95 | 2064.18 | 0.833 |
| `plant_catalog.xml` | 3125.16 | 3693.96 | 0.846 | 1523.58 | 1864.61 | 0.817 |
| `cd_catalog.xml` | 2801.73 | 3389.45 | 0.827 | 1388.91 | 1757.73 | 0.790 |
| `hnrss.xml` | 8372.60 | 10064.06 | 0.832 | 4309.44 | 5541.31 | 0.778 |
| `xkcd_rss.xml` | 8617.95 | 8720.08 | 0.988 | 3208.49 | 4140.86 | 0.775 |
| `bbc_world.xml` | 5034.80 | 6130.75 | 0.821 | 3103.76 | 3470.61 | 0.894 |
| `arxiv_cs.xml` | 10331.91 | 8499.86 | 1.216 | 4507.49 | 4160.02 | 1.084 |
| `ecb_usd.xml` | 5249.54 | 6787.37 | 0.773 | 2794.58 | 3253.73 | 0.859 |
| `tree.xml` | 2803.41 | 3169.99 | 0.884 | 1439.60 | 1476.76 | 0.975 |
| `character.xml` | 2545.73 | 3291.46 | 0.773 | 1427.26 | 1387.48 | 1.029 |
| `xgconsole.xml` | 3788.93 | 6079.60 | 0.623 | 1341.56 | 2027.04 | 0.662 |
| `weekly_utf8.xml` | 3272.71 | 3730.22 | 0.877 | 689.53 | 1291.42 | 0.534 |
| `pugixml_large.xml` | 2165.66 | 2636.98 | 0.821 | 1705.47 | 1520.66 | 1.122 |
| `synthetic_flat_attrs.xml` | 2784.60 | 6967.31 | 0.400 | 1013.17 | 1349.42 | 0.751 |
| `synthetic_deep_tree.xml` | 1525.05 | 1949.86 | 0.782 | 1046.97 | 1196.36 | 0.875 |
| `synthetic_entities.xml` | 6031.90 | 10747.98 | 0.561 | 848.00 | 10631.20 | 0.080 |
| `synthetic_cdata_mix.xml` | 3007.99 | 2442.64 | 1.231 | 1783.90 | 1826.01 | 0.977 |
| `synthetic_wide_siblings.xml` | 2362.38 | 1236.34 | 1.911 | 976.39 | 963.56 | 1.013 |
| `synthetic_namespace_mix.xml` | 3302.78 | 3835.42 | 0.861 | 1525.50 | 1469.58 | 1.038 |
| `synthetic_long_names.xml` | 4827.34 | 6786.15 | 0.711 | 2553.45 | 3379.33 | 0.756 |
| `synthetic_self_closing_swarm.xml` | 3411.99 | 4781.37 | 0.714 | 1461.59 | 1261.78 | 1.158 |
| `synthetic_mixed_content.xml` | 3021.33 | 2340.58 | 1.291 | 1348.66 | 1383.38 | 0.975 |
| `synthetic_small_records.xml` | 2612.33 | 1896.25 | 1.378 | 1260.37 | 1299.81 | 0.970 |
| `synthetic_tiny_empty.xml` | 1565.09 | 1703.60 | 0.919 | 1288.58 | 1718.34 | 0.750 |
| `synthetic_tiny_text.xml` | 1344.36 | 1773.60 | 0.758 | 697.94 | 1764.77 | 0.395 |
| `synthetic_one_attr.xml` | 1816.53 | 3727.10 | 0.487 | 1091.93 | 3699.31 | 0.295 |
| `synthetic_two_attr.xml` | 2052.47 | 5588.00 | 0.367 | 1073.86 | 5547.62 | 0.194 |
| `synthetic_attrs4.xml` | 2346.34 | 8607.36 | 0.273 | 970.10 | 8472.63 | 0.114 |
| `synthetic_attrs8.xml` | 2468.69 | 12911.00 | 0.191 | 947.13 | 12530.89 | 0.076 |
| `synthetic_single_quotes.xml` | 3058.01 | 10097.03 | 0.303 | 1272.07 | 9964.43 | 0.128 |
| `synthetic_unicode_names.xml` | 3418.14 | 8587.17 | 0.398 | 568.14 | 8476.01 | 0.067 |
| `synthetic_pretty_indented.xml` | 2439.05 | 1930.66 | 1.263 | 1245.59 | 1355.12 | 0.919 |
| `synthetic_crlf_pretty.xml` | 2925.20 | 2016.92 | 1.450 | 1261.10 | 1150.47 | 1.096 |
| `synthetic_token_whitespace_mix.xml` | 1439.68 | 9248.32 | 0.156 | 967.24 | 8987.29 | 0.108 |
| `synthetic_attr_count_mix.xml` | 2849.51 | 6789.05 | 0.420 | 1067.51 | 1427.08 | 0.748 |

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

- `"profile": "validated"` for a validating generated parser
- `"profiles": ["validated", "permissive"]` to run the same assertions in both generated policies

## Parser Perf Guardrail

The hard gate is:

- `ours-permissive >= max(pugixml, rapidxml)` per fixture

For parser-only optimization passes, use the paired A/B harness below.

Optional validated/permissive spot checks:

```bash
zig-out/bin/zxml-bench parse validated bench/fixtures/sitemaps.xml 400
zig-out/bin/zxml-bench parse permissive bench/fixtures/sitemaps.xml 2000
```

For sub-percent parser A/B work, use `bench/paired_bench.py`. It runs baseline
and candidate simultaneously on two pinned CPUs, swaps the CPU assignments,
geometrically combines each assignment pair, then uses the median paired ratio
across repeats to reject scheduler outliers. Reported ratios are candidate time
divided by baseline time, so values below `1.0` are faster.
