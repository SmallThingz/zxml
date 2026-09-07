# ZXML Benchmark Results

Generated (unix): 1788790378

Profile: `stable`

Sampling: 5 rounds, target 40.0 ms per parser sample.

Collection: independently guarded fixture windows on CPU6, not one continuous quiet interval. Every retained fixture passed its complete calibration/sample guard.

## Benchmark Environment

| Property | Value |
|---|---|
| OS / kernel | Linux 7.2.2-zen1-1-zen |
| Architecture | x86_64 |
| CPU | 12th Gen Intel(R) Core(TM) i5-12450H |
| CPU frequency scaling | 47% |
| CPU MHz range | 400.0000–4400.0000 |
| Zig | 0.16.0 (`ReleaseFast -Dcpu=native`) |
| C++ driver | c++ (`-O3 -DNDEBUG -march=native`) |

## Parse Throughput

| Fixture | Parser | Throughput (MiB/s) | Median Time (ms) | Iterations |
|---|---|---:|---:|---:|
| note.xml | ours-validated | 1650.37 | 29.06 | 306616 |
| note.xml | ours-permissive | 2802.99 | 36.50 | 654058 |
| note.xml | stream-validated | 1362.65 | 31.00 | 270119 |
| note.xml | stream-permissive | 3165.11 | 33.88 | 685715 |
| note.xml | pugixml | 944.23 | 22.35 | 134938 |
| note.xml | rapidxml | 1710.93 | 26.47 | 289562 |
| sitemaps.xml | ours-validated | 2036.69 | 39.35 | 9746 |
| sitemaps.xml | ours-permissive | 4101.84 | 39.25 | 19581 |
| sitemaps.xml | stream-validated | 1740.36 | 39.55 | 8370 |
| sitemaps.xml | stream-permissive | 3573.09 | 38.77 | 16846 |
| sitemaps.xml | pugixml | 1974.59 | 39.89 | 9579 |
| sitemaps.xml | rapidxml | 2017.44 | 40.52 | 9941 |
| plant_catalog.xml | ours-validated | 1705.50 | 19.35 | 4478 |
| plant_catalog.xml | ours-permissive | 3481.61 | 17.27 | 8158 |
| plant_catalog.xml | stream-validated | 1372.40 | 19.42 | 3616 |
| plant_catalog.xml | stream-permissive | 3055.86 | 18.16 | 7530 |
| plant_catalog.xml | pugixml | 1471.49 | 24.42 | 4875 |
| plant_catalog.xml | rapidxml | 1560.99 | 24.50 | 5188 |
| cd_catalog.xml | ours-validated | 1672.17 | 37.27 | 13430 |
| cd_catalog.xml | ours-permissive | 3271.40 | 39.16 | 27609 |
| cd_catalog.xml | stream-validated | 1368.11 | 39.71 | 11706 |
| cd_catalog.xml | stream-permissive | 2744.52 | 40.47 | 23933 |
| cd_catalog.xml | pugixml | 1420.96 | 39.63 | 12136 |
| cd_catalog.xml | rapidxml | 1572.07 | 38.89 | 13174 |
| hnrss.xml | ours-validated | 5384.51 | 37.72 | 11525 |
| hnrss.xml | ours-permissive | 9668.42 | 38.64 | 21197 |
| hnrss.xml | stream-validated | 4301.07 | 39.74 | 9699 |
| hnrss.xml | stream-permissive | 8449.01 | 38.78 | 18590 |
| hnrss.xml | pugixml | 2916.30 | 37.49 | 6204 |
| hnrss.xml | rapidxml | 2600.42 | 38.73 | 5715 |
| xkcd_rss.xml | ours-validated | 3999.84 | 36.74 | 62508 |
| xkcd_rss.xml | ours-permissive | 8366.37 | 39.67 | 141178 |
| xkcd_rss.xml | stream-validated | 3353.36 | 39.49 | 56332 |
| xkcd_rss.xml | stream-permissive | 8425.40 | 40.18 | 143989 |
| xkcd_rss.xml | pugixml | 2042.62 | 45.06 | 39153 |
| xkcd_rss.xml | rapidxml | 2574.45 | 37.15 | 40685 |
| bbc_world.xml | ours-validated | 3356.84 | 37.65 | 5725 |
| bbc_world.xml | ours-permissive | 5940.00 | 38.80 | 10438 |
| bbc_world.xml | stream-validated | 3162.44 | 39.70 | 5686 |
| bbc_world.xml | stream-permissive | 5355.02 | 39.60 | 9605 |
| bbc_world.xml | pugixml | 2590.99 | 39.44 | 4628 |
| bbc_world.xml | rapidxml | 2500.23 | 38.41 | 4350 |
| arxiv_cs.xml | ours-validated | 4140.77 | 24.92 | 50 |
| arxiv_cs.xml | ours-permissive | 8397.32 | 44.23 | 180 |
| arxiv_cs.xml | stream-validated | 4461.78 | 40.23 | 87 |
| arxiv_cs.xml | stream-permissive | 10359.37 | 35.85 | 180 |
| arxiv_cs.xml | pugixml | 2625.27 | 26.72 | 34 |
| arxiv_cs.xml | rapidxml | 1843.41 | 27.98 | 25 |
| ecb_usd.xml | ours-validated | 3114.72 | 37.39 | 16725 |
| ecb_usd.xml | ours-permissive | 6521.50 | 40.55 | 37975 |
| ecb_usd.xml | stream-validated | 2751.61 | 38.94 | 15388 |
| ecb_usd.xml | stream-permissive | 5888.88 | 40.09 | 33905 |
| ecb_usd.xml | pugixml | 2664.57 | 38.08 | 14569 |
| ecb_usd.xml | rapidxml | 2663.92 | 39.91 | 15267 |
| tree.xml | ours-validated | 1426.45 | 36.04 | 219109 |
| tree.xml | ours-permissive | 2996.42 | 35.77 | 456839 |
| tree.xml | stream-validated | 1329.29 | 36.89 | 209046 |
| tree.xml | stream-permissive | 2990.02 | 37.74 | 480987 |
| tree.xml | pugixml | 1236.79 | 31.49 | 166019 |
| tree.xml | rapidxml | 2044.61 | 36.72 | 320022 |
| character.xml | ours-validated | 1422.39 | 33.94 | 279698 |
| character.xml | ours-permissive | 3316.56 | 29.83 | 573098 |
| character.xml | stream-validated | 1432.67 | 37.11 | 307994 |
| character.xml | stream-permissive | 3202.66 | 36.01 | 668037 |
| character.xml | pugixml | 1134.51 | 33.66 | 221249 |
| character.xml | rapidxml | 2019.61 | 35.49 | 415220 |
| transitions.xml | ours-permissive | 3538.62 | 38.73 | 687604 |
| transitions.xml | stream-permissive | 3213.94 | 37.84 | 610079 |
| transitions.xml | pugixml | 1369.08 | 34.60 | 237666 |
| transitions.xml | rapidxml | 2159.92 | 37.58 | 407269 |
| xgconsole.xml | ours-validated | 1927.04 | 36.97 | 103476 |
| xgconsole.xml | ours-permissive | 5842.04 | 38.57 | 327266 |
| xgconsole.xml | stream-validated | 1279.46 | 38.90 | 72290 |
| xgconsole.xml | stream-permissive | 5832.01 | 39.96 | 338473 |
| xgconsole.xml | pugixml | 1828.42 | 36.94 | 98080 |
| xgconsole.xml | rapidxml | 2412.94 | 38.63 | 135367 |
| weekly_utf8.xml | ours-validated | 1218.10 | 33.46 | 16305 |
| weekly_utf8.xml | ours-permissive | 3633.24 | 32.52 | 47268 |
| weekly_utf8.xml | stream-validated | 665.27 | 33.81 | 8998 |
| weekly_utf8.xml | stream-permissive | 3088.15 | 33.62 | 41536 |
| weekly_utf8.xml | pugixml | 2151.54 | 32.53 | 28003 |
| weekly_utf8.xml | rapidxml | 2332.82 | 30.39 | 28363 |
| pugixml_large.xml | ours-validated | 1435.62 | 38.23 | 822 |
| pugixml_large.xml | ours-permissive | 2560.26 | 38.75 | 1486 |
| pugixml_large.xml | stream-validated | 1621.66 | 37.39 | 908 |
| pugixml_large.xml | stream-permissive | 2013.20 | 38.24 | 1153 |
| pugixml_large.xml | pugixml | 473.25 | 37.95 | 269 |
| pugixml_large.xml | rapidxml | 300.14 | 33.37 | 150 |
| synthetic_deep_tree.xml | ours-validated | 1124.84 | 39.74 | 25841 |
| synthetic_deep_tree.xml | ours-permissive | 1840.90 | 36.97 | 39342 |
| synthetic_deep_tree.xml | stream-validated | 1056.93 | 37.89 | 23149 |
| synthetic_deep_tree.xml | stream-permissive | 1728.09 | 38.59 | 38547 |
| synthetic_deep_tree.xml | pugixml | 1259.10 | 38.28 | 27861 |
| synthetic_deep_tree.xml | rapidxml | 756.76 | 40.33 | 17642 |
| synthetic_cdata_mix.xml | ours-validated | 1705.25 | 36.09 | 522 |
| synthetic_cdata_mix.xml | ours-permissive | 2307.92 | 40.05 | 784 |
| synthetic_cdata_mix.xml | stream-validated | 1728.85 | 39.62 | 581 |
| synthetic_cdata_mix.xml | stream-permissive | 2783.01 | 40.29 | 951 |
| synthetic_cdata_mix.xml | pugixml | 669.92 | 42.24 | 240 |
| synthetic_cdata_mix.xml | rapidxml | 517.66 | 54.66 | 240 |
| synthetic_wide_siblings.xml | ours-validated | 1078.86 | 39.98 | 125 |
| synthetic_wide_siblings.xml | ours-permissive | 1509.88 | 59.41 | 260 |
| synthetic_wide_siblings.xml | stream-validated | 1065.07 | 40.82 | 126 |
| synthetic_wide_siblings.xml | stream-permissive | 2170.45 | 41.33 | 260 |
| synthetic_wide_siblings.xml | pugixml | 429.62 | 40.96 | 51 |
| synthetic_wide_siblings.xml | rapidxml | 318.78 | 41.13 | 38 |
| synthetic_mixed_content.xml | ours-validated | 1332.39 | 40.54 | 90 |
| synthetic_mixed_content.xml | ours-permissive | 2200.81 | 60.00 | 220 |
| synthetic_mixed_content.xml | stream-validated | 1321.31 | 39.07 | 86 |
| synthetic_mixed_content.xml | stream-permissive | 2996.76 | 44.06 | 220 |
| synthetic_mixed_content.xml | pugixml | 528.42 | 39.76 | 35 |
| synthetic_mixed_content.xml | rapidxml | 396.35 | 39.37 | 26 |
| synthetic_small_records.xml | ours-validated | 1345.19 | 25.32 | 30 |
| synthetic_small_records.xml | ours-permissive | 1748.93 | 29.87 | 46 |
| synthetic_small_records.xml | stream-validated | 1283.69 | 40.69 | 46 |
| synthetic_small_records.xml | stream-permissive | 2642.90 | 40.39 | 94 |
| synthetic_small_records.xml | pugixml | 430.80 | 42.17 | 16 |
| synthetic_small_records.xml | rapidxml | 301.51 | 45.19 | 12 |
| synthetic_tiny_empty.xml | ours-validated | 1627.16 | 37.14 | 72 |
| synthetic_tiny_empty.xml | ours-permissive | 1628.65 | 40.71 | 79 |
| synthetic_tiny_empty.xml | stream-validated | 7017.19 | 43.06 | 360 |
| synthetic_tiny_empty.xml | stream-permissive | 6998.98 | 43.17 | 360 |
| synthetic_tiny_empty.xml | pugixml | 183.36 | 41.19 | 9 |
| synthetic_tiny_empty.xml | rapidxml | 113.81 | 44.24 | 6 |
| synthetic_tiny_text.xml | ours-validated | 1699.57 | 40.40 | 75 |
| synthetic_tiny_text.xml | ours-permissive | 1719.21 | 40.47 | 76 |
| synthetic_tiny_text.xml | stream-validated | 16969.73 | 40.79 | 756 |
| synthetic_tiny_text.xml | stream-permissive | 16997.85 | 41.04 | 762 |
| synthetic_tiny_text.xml | pugixml | 176.77 | 41.43 | 8 |
| synthetic_tiny_text.xml | rapidxml | 117.90 | 46.59 | 6 |
| synthetic_pretty_indented.xml | ours-validated | 1280.49 | 37.42 | 53 |
| synthetic_pretty_indented.xml | ours-permissive | 1848.85 | 37.16 | 76 |
| synthetic_pretty_indented.xml | stream-validated | 1305.03 | 36.72 | 53 |
| synthetic_pretty_indented.xml | stream-permissive | 2163.61 | 38.03 | 91 |
| synthetic_pretty_indented.xml | pugixml | 480.67 | 37.62 | 20 |
| synthetic_pretty_indented.xml | rapidxml | 384.56 | 35.26 | 15 |
| synthetic_crlf_pretty.xml | ours-validated | 1169.02 | 40.61 | 61 |
| synthetic_crlf_pretty.xml | ours-permissive | 1941.77 | 80.15 | 200 |
| synthetic_crlf_pretty.xml | stream-validated | 1341.92 | 40.59 | 70 |
| synthetic_crlf_pretty.xml | stream-permissive | 2786.91 | 55.85 | 200 |
| synthetic_crlf_pretty.xml | pugixml | 504.56 | 40.10 | 26 |
| synthetic_crlf_pretty.xml | rapidxml | 414.48 | 41.31 | 22 |

## Synthetic Regression Fixtures

These fixtures are mandatory regression coverage but are excluded from headline averages and headline external gates.

| Fixture | ours-permissive | ours-validated | stream-permissive | stream-validated | pugixml | rapidxml |
|---|---:|---:|---:|---:|---:|---:|
| `synthetic_token_whitespace_mix.xml` | 9696.10 | 9470.30 | 28637.42 | 28501.03 | 425.43 | 335.83 |
| `synthetic_attr_count_mix.xml` | 6486.76 | 1353.29 | 8576.56 | 1400.55 | 369.58 | 288.80 |
| `synthetic_one_attr.xml` | 3595.14 | 3646.61 | 14909.00 | 14870.66 | 266.31 | 180.03 |
| `synthetic_two_attr.xml` | 5609.10 | 5613.87 | 20141.71 | 20337.67 | 295.14 | 209.21 |
| `synthetic_attrs4.xml` | 9022.85 | 9023.75 | 27962.03 | 27825.19 | 319.84 | 238.06 |
| `synthetic_attrs8.xml` | 14357.04 | 14163.34 | 36084.41 | 35767.22 | 336.80 | 255.89 |
| `synthetic_single_quotes.xml` | 11005.11 | 10884.39 | 31102.06 | 30905.01 | 492.19 | 378.68 |
| `synthetic_unicode_names.xml` | 9075.71 | 8985.15 | 41853.92 | 41670.41 | 618.88 | 527.13 |
| `synthetic_self_closing_swarm.xml` | 4380.22 | 1132.17 | 5106.80 | 1259.37 | 545.74 | 439.86 |
| `synthetic_long_names.xml` | 6329.52 | 3160.07 | 5834.46 | 2482.50 | 1322.08 | 1574.03 |
| `synthetic_namespace_mix.xml` | 3650.98 | 1398.11 | 4230.24 | 1408.00 | 661.60 | 543.84 |
| `synthetic_entities.xml` | 11160.92 | 11147.61 | 44613.03 | 44103.58 | 880.65 | 895.57 |
| `synthetic_flat_attrs.xml` | 6216.80 | 1142.63 | 7970.14 | 1242.38 | 416.71 | 330.21 |

Synthetic regression gate: 13/13 PASS, 0 FAIL.

## External Parser Gates

| Fixture | ours-permissive | pugixml | rapidxml | best external | ours/best-ext | Result |
|---|---:|---:|---:|---|---:|---|
| note.xml | 2802.99 | 944.23 | 1710.93 | rapidxml 1710.93 | 1.638 | PASS |
| sitemaps.xml | 4101.84 | 1974.59 | 2017.44 | rapidxml 2017.44 | 2.033 | PASS |
| plant_catalog.xml | 3481.61 | 1471.49 | 1560.99 | rapidxml 1560.99 | 2.230 | PASS |
| cd_catalog.xml | 3271.40 | 1420.96 | 1572.07 | rapidxml 1572.07 | 2.081 | PASS |
| hnrss.xml | 9668.42 | 2916.30 | 2600.42 | pugixml 2916.30 | 3.315 | PASS |
| xkcd_rss.xml | 8366.37 | 2042.62 | 2574.45 | rapidxml 2574.45 | 3.250 | PASS |
| bbc_world.xml | 5940.00 | 2590.99 | 2500.23 | pugixml 2590.99 | 2.293 | PASS |
| arxiv_cs.xml | 8397.32 | 2625.27 | 1843.41 | pugixml 2625.27 | 3.199 | PASS |
| ecb_usd.xml | 6521.50 | 2664.57 | 2663.92 | pugixml 2664.57 | 2.447 | PASS |
| tree.xml | 2996.42 | 1236.79 | 2044.61 | rapidxml 2044.61 | 1.466 | PASS |
| character.xml | 3316.56 | 1134.51 | 2019.61 | rapidxml 2019.61 | 1.642 | PASS |
| transitions.xml | 3538.62 | 1369.08 | 2159.92 | rapidxml 2159.92 | 1.638 | PASS |
| xgconsole.xml | 5842.04 | 1828.42 | 2412.94 | rapidxml 2412.94 | 2.421 | PASS |
| weekly_utf8.xml | 3633.24 | 2151.54 | 2332.82 | rapidxml 2332.82 | 1.557 | PASS |
| pugixml_large.xml | 2560.26 | 473.25 | 300.14 | pugixml 473.25 | 5.410 | PASS |
| synthetic_deep_tree.xml | 1840.90 | 1259.10 | 756.76 | pugixml 1259.10 | 1.462 | PASS |
| synthetic_cdata_mix.xml | 2307.92 | 669.92 | 517.66 | pugixml 669.92 | 3.445 | PASS |
| synthetic_wide_siblings.xml | 1509.88 | 429.62 | 318.78 | pugixml 429.62 | 3.514 | PASS |
| synthetic_mixed_content.xml | 2200.81 | 528.42 | 396.35 | pugixml 528.42 | 4.165 | PASS |
| synthetic_small_records.xml | 1748.93 | 430.80 | 301.51 | pugixml 430.80 | 4.060 | PASS |
| synthetic_tiny_empty.xml | 1628.65 | 183.36 | 113.81 | pugixml 183.36 | 8.882 | PASS |
| synthetic_tiny_text.xml | 1719.21 | 176.77 | 117.90 | pugixml 176.77 | 9.726 | PASS |
| synthetic_pretty_indented.xml | 1848.85 | 480.67 | 384.56 | pugixml 480.67 | 3.846 | PASS |
| synthetic_crlf_pretty.xml | 1941.77 | 504.56 | 414.48 | pugixml 504.56 | 3.848 | PASS |

## Streaming Comparison (Advisory)

| Fixture | stream-permissive | ours-permissive | stream/ours | stream-validated | ours-validated | stream/ours |
|---|---:|---:|---:|---:|---:|---:|
| note.xml | 3165.11 | 2802.99 | 1.129 | 1362.65 | 1650.37 | 0.826 |
| sitemaps.xml | 3573.09 | 4101.84 | 0.871 | 1740.36 | 2036.69 | 0.855 |
| plant_catalog.xml | 3055.86 | 3481.61 | 0.878 | 1372.40 | 1705.50 | 0.805 |
| cd_catalog.xml | 2744.52 | 3271.40 | 0.839 | 1368.11 | 1672.17 | 0.818 |
| hnrss.xml | 8449.01 | 9668.42 | 0.874 | 4301.07 | 5384.51 | 0.799 |
| xkcd_rss.xml | 8425.40 | 8366.37 | 1.007 | 3353.36 | 3999.84 | 0.838 |
| bbc_world.xml | 5355.02 | 5940.00 | 0.902 | 3162.44 | 3356.84 | 0.942 |
| arxiv_cs.xml | 10359.37 | 8397.32 | 1.234 | 4461.78 | 4140.77 | 1.078 |
| ecb_usd.xml | 5888.88 | 6521.50 | 0.903 | 2751.61 | 3114.72 | 0.883 |
| tree.xml | 2990.02 | 2996.42 | 0.998 | 1329.29 | 1426.45 | 0.932 |
| character.xml | 3202.66 | 3316.56 | 0.966 | 1432.67 | 1422.39 | 1.007 |
| xgconsole.xml | 5832.01 | 5842.04 | 0.998 | 1279.46 | 1927.04 | 0.664 |
| weekly_utf8.xml | 3088.15 | 3633.24 | 0.850 | 665.27 | 1218.10 | 0.546 |
| pugixml_large.xml | 2013.20 | 2560.26 | 0.786 | 1621.66 | 1435.62 | 1.130 |
| synthetic_deep_tree.xml | 1728.09 | 1840.90 | 0.939 | 1056.93 | 1124.84 | 0.940 |
| synthetic_cdata_mix.xml | 2783.01 | 2307.92 | 1.206 | 1728.85 | 1705.25 | 1.014 |
| synthetic_wide_siblings.xml | 2170.45 | 1509.88 | 1.437 | 1065.07 | 1078.86 | 0.987 |
| synthetic_mixed_content.xml | 2996.76 | 2200.81 | 1.362 | 1321.31 | 1332.39 | 0.992 |
| synthetic_small_records.xml | 2642.90 | 1748.93 | 1.511 | 1283.69 | 1345.19 | 0.954 |
| synthetic_tiny_empty.xml | 6998.98 | 1628.65 | 4.297 | 7017.19 | 1627.16 | 4.313 |
| synthetic_tiny_text.xml | 16997.85 | 1719.21 | 9.887 | 16969.73 | 1699.57 | 9.985 |
| synthetic_pretty_indented.xml | 2163.61 | 1848.85 | 1.170 | 1305.03 | 1280.49 | 1.019 |
| synthetic_crlf_pretty.xml | 2786.91 | 1941.77 | 1.435 | 1341.92 | 1169.02 | 1.148 |

## Validated Pathology Regression Checks

2/2 passed. These fixtures are excluded from headline averages and stable external gates.
Detailed timings remain in `bench/results/latest.json` for regression analysis.
