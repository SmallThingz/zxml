# ZXML Benchmark Results

Generated (unix): 1788779623

Profile: `stable`

Sampling: 5 rounds, target 40.0 ms per parser sample.

Collection: independently guarded fixture windows on CPU6, not one continuous quiet interval. Every retained fixture passed its complete calibration/sample guard.

## Benchmark Environment

| Property | Value |
|---|---|
| OS / kernel | Linux 7.2.2-zen1-1-zen |
| Architecture | x86_64 |
| CPU | 12th Gen Intel(R) Core(TM) i5-12450H |
| CPU frequency scaling | 25% |
| CPU MHz range | 400.0000–4400.0000 |
| Zig | 0.16.0 (`ReleaseFast -Dcpu=native`) |
| C++ driver | c++ (`-O3 -DNDEBUG -march=native`) |

## Parse Throughput

| Fixture | Parser | Throughput (MB/s) | Median Time (ms) | Iterations |
|---|---|---:|---:|---:|
| note.xml | ours-validated | 1671.65 | 39.13 | 398831 |
| note.xml | ours-permissive | 2876.74 | 38.72 | 679156 |
| note.xml | stream-validated | 1392.80 | 36.23 | 307716 |
| note.xml | stream-permissive | 3282.15 | 36.35 | 727494 |
| note.xml | pugixml | 977.97 | 36.57 | 218059 |
| note.xml | rapidxml | 1773.58 | 34.70 | 375235 |
| sitemaps.xml | ours-validated | 2128.56 | 38.17 | 9424 |
| sitemaps.xml | ours-permissive | 4223.02 | 38.42 | 18817 |
| sitemaps.xml | stream-validated | 1802.19 | 40.49 | 8464 |
| sitemaps.xml | stream-permissive | 3720.77 | 39.93 | 17233 |
| sitemaps.xml | pugixml | 2067.23 | 39.55 | 9483 |
| sitemaps.xml | rapidxml | 2101.88 | 36.89 | 8992 |
| plant_catalog.xml | ours-validated | 1866.88 | 38.81 | 9374 |
| plant_catalog.xml | ours-permissive | 3624.58 | 40.63 | 19054 |
| plant_catalog.xml | stream-validated | 1529.97 | 38.67 | 7654 |
| plant_catalog.xml | stream-permissive | 3215.44 | 40.47 | 16836 |
| plant_catalog.xml | pugixml | 1574.25 | 37.98 | 7735 |
| plant_catalog.xml | rapidxml | 1680.87 | 38.88 | 8455 |
| cd_catalog.xml | ours-validated | 1736.88 | 40.24 | 14364 |
| cd_catalog.xml | ours-permissive | 3255.46 | 40.02 | 26772 |
| cd_catalog.xml | stream-validated | 1407.95 | 40.75 | 11791 |
| cd_catalog.xml | stream-permissive | 2810.06 | 40.54 | 23409 |
| cd_catalog.xml | pugixml | 1503.05 | 37.31 | 11525 |
| cd_catalog.xml | rapidxml | 1656.73 | 37.76 | 12857 |
| hnrss.xml | ours-validated | 5510.29 | 37.47 | 11171 |
| hnrss.xml | ours-permissive | 9970.37 | 38.94 | 21008 |
| hnrss.xml | stream-validated | 4432.99 | 39.86 | 9560 |
| hnrss.xml | stream-permissive | 8570.10 | 41.31 | 19156 |
| hnrss.xml | pugixml | 2984.76 | 39.29 | 6345 |
| hnrss.xml | rapidxml | 2722.01 | 39.18 | 5770 |
| xkcd_rss.xml | ours-validated | 4106.10 | 40.41 | 67321 |
| xkcd_rss.xml | ours-permissive | 8670.15 | 42.13 | 148189 |
| xkcd_rss.xml | stream-validated | 3439.53 | 36.53 | 50976 |
| xkcd_rss.xml | stream-permissive | 8792.88 | 40.53 | 144585 |
| xkcd_rss.xml | pugixml | 2530.09 | 37.21 | 38196 |
| xkcd_rss.xml | rapidxml | 2650.42 | 40.03 | 43046 |
| bbc_world.xml | ours-validated | 3459.30 | 38.47 | 5749 |
| bbc_world.xml | ours-permissive | 5957.65 | 38.65 | 9945 |
| bbc_world.xml | stream-validated | 3144.30 | 40.30 | 5473 |
| bbc_world.xml | stream-permissive | 5433.30 | 37.79 | 8868 |
| bbc_world.xml | pugixml | 2628.28 | 37.53 | 4261 |
| bbc_world.xml | rapidxml | 2561.22 | 38.45 | 4254 |
| arxiv_cs.xml | ours-validated | 4158.79 | 39.54 | 76 |
| arxiv_cs.xml | ours-permissive | 8451.59 | 46.08 | 180 |
| arxiv_cs.xml | stream-validated | 4577.96 | 40.17 | 85 |
| arxiv_cs.xml | stream-permissive | 10686.52 | 36.44 | 180 |
| arxiv_cs.xml | pugixml | 2733.14 | 41.16 | 52 |
| arxiv_cs.xml | rapidxml | 1897.48 | 39.91 | 35 |
| ecb_usd.xml | ours-validated | 3207.87 | 38.64 | 16976 |
| ecb_usd.xml | ours-permissive | 6813.26 | 36.92 | 34445 |
| ecb_usd.xml | stream-validated | 2859.11 | 37.94 | 14857 |
| ecb_usd.xml | stream-permissive | 6032.57 | 41.06 | 33925 |
| ecb_usd.xml | pugixml | 2705.87 | 34.57 | 12809 |
| ecb_usd.xml | rapidxml | 2751.16 | 38.98 | 14686 |
| tree.xml | ours-validated | 1465.52 | 17.99 | 107147 |
| tree.xml | ours-permissive | 2977.17 | 36.09 | 436761 |
| tree.xml | stream-validated | 1368.22 | 33.79 | 187915 |
| tree.xml | stream-permissive | 3109.66 | 33.30 | 420942 |
| tree.xml | pugixml | 1275.77 | 32.41 | 168097 |
| tree.xml | rapidxml | 2105.11 | 32.24 | 275918 |
| character.xml | ours-validated | 1477.28 | 13.20 | 107767 |
| character.xml | ours-permissive | 3498.75 | 13.39 | 258791 |
| character.xml | stream-validated | 1437.93 | 9.65 | 76653 |
| character.xml | stream-permissive | 3293.65 | 10.71 | 194892 |
| character.xml | pugixml | 1181.24 | 14.03 | 91581 |
| character.xml | rapidxml | 2132.49 | 11.20 | 132010 |
| transitions.xml | ours-permissive | 3726.03 | 37.18 | 662885 |
| transitions.xml | stream-permissive | 3408.92 | 37.96 | 619159 |
| transitions.xml | pugixml | 1472.48 | 34.01 | 239582 |
| transitions.xml | rapidxml | 2268.62 | 38.93 | 422559 |
| xgconsole.xml | ours-validated | 2012.75 | 37.47 | 104455 |
| xgconsole.xml | ours-permissive | 6011.79 | 36.37 | 302823 |
| xgconsole.xml | stream-validated | 1334.16 | 39.18 | 72401 |
| xgconsole.xml | stream-permissive | 6078.22 | 39.62 | 333525 |
| xgconsole.xml | pugixml | 1895.04 | 38.02 | 99781 |
| xgconsole.xml | rapidxml | 2492.48 | 39.15 | 135161 |
| weekly_utf8.xml | ours-validated | 1272.68 | 38.14 | 18520 |
| weekly_utf8.xml | ours-permissive | 3828.66 | 36.97 | 54000 |
| weekly_utf8.xml | stream-validated | 691.95 | 36.51 | 9638 |
| weekly_utf8.xml | stream-permissive | 3160.34 | 39.41 | 47517 |
| weekly_utf8.xml | pugixml | 2248.38 | 36.76 | 31531 |
| weekly_utf8.xml | rapidxml | 2435.64 | 38.13 | 35438 |
| pugixml_large.xml | ours-validated | 1489.42 | 39.72 | 845 |
| pugixml_large.xml | ours-permissive | 2567.86 | 40.82 | 1497 |
| pugixml_large.xml | stream-validated | 1677.26 | 39.24 | 940 |
| pugixml_large.xml | stream-permissive | 2113.79 | 41.07 | 1240 |
| pugixml_large.xml | pugixml | 481.54 | 40.86 | 281 |
| pugixml_large.xml | rapidxml | 308.00 | 38.64 | 170 |
| synthetic_flat_attrs.xml | ours-validated | 1329.41 | 47.79 | 280 |
| synthetic_flat_attrs.xml | ours-permissive | 6787.72 | 40.98 | 1226 |
| synthetic_flat_attrs.xml | stream-validated | 1235.85 | 51.41 | 280 |
| synthetic_flat_attrs.xml | stream-permissive | 8721.19 | 40.33 | 1550 |
| synthetic_flat_attrs.xml | pugixml | 467.18 | 39.83 | 82 |
| synthetic_flat_attrs.xml | rapidxml | 351.47 | 41.96 | 65 |
| synthetic_deep_tree.xml | ours-validated | 1163.96 | 38.52 | 24717 |
| synthetic_deep_tree.xml | ours-permissive | 1905.42 | 40.96 | 43029 |
| synthetic_deep_tree.xml | stream-validated | 1113.43 | 37.13 | 22788 |
| synthetic_deep_tree.xml | stream-permissive | 1768.84 | 41.34 | 40310 |
| synthetic_deep_tree.xml | pugixml | 1283.16 | 40.00 | 28298 |
| synthetic_deep_tree.xml | rapidxml | 777.19 | 26.27 | 11254 |
| synthetic_entities.xml | ours-validated | 10244.35 | 40.28 | 628 |
| synthetic_entities.xml | ours-permissive | 10451.86 | 39.98 | 636 |
| synthetic_entities.xml | stream-validated | 31127.85 | 40.04 | 1897 |
| synthetic_entities.xml | stream-permissive | 31495.76 | 40.32 | 1933 |
| synthetic_entities.xml | pugixml | 919.99 | 39.99 | 56 |
| synthetic_entities.xml | rapidxml | 930.96 | 39.52 | 56 |
| synthetic_cdata_mix.xml | ours-validated | 1783.06 | 39.31 | 567 |
| synthetic_cdata_mix.xml | ours-permissive | 2361.87 | 40.51 | 774 |
| synthetic_cdata_mix.xml | stream-validated | 1824.68 | 38.01 | 561 |
| synthetic_cdata_mix.xml | stream-permissive | 2889.12 | 39.88 | 932 |
| synthetic_cdata_mix.xml | pugixml | 690.78 | 42.95 | 240 |
| synthetic_cdata_mix.xml | rapidxml | 525.21 | 56.49 | 240 |
| synthetic_wide_siblings.xml | ours-validated | 1129.72 | 40.03 | 125 |
| synthetic_wide_siblings.xml | ours-permissive | 1552.51 | 60.59 | 260 |
| synthetic_wide_siblings.xml | stream-validated | 1126.05 | 40.16 | 125 |
| synthetic_wide_siblings.xml | stream-permissive | 2251.36 | 41.78 | 260 |
| synthetic_wide_siblings.xml | pugixml | 430.08 | 40.38 | 48 |
| synthetic_wide_siblings.xml | rapidxml | 316.79 | 41.11 | 36 |
| synthetic_namespace_mix.xml | ours-validated | 1452.84 | 40.32 | 99 |
| synthetic_namespace_mix.xml | ours-permissive | 3785.66 | 34.39 | 220 |
| synthetic_namespace_mix.xml | stream-validated | 1484.34 | 40.66 | 102 |
| synthetic_namespace_mix.xml | stream-permissive | 4411.76 | 29.51 | 220 |
| synthetic_namespace_mix.xml | pugixml | 700.09 | 39.73 | 47 |
| synthetic_namespace_mix.xml | rapidxml | 577.30 | 39.98 | 39 |
| synthetic_long_names.xml | ours-validated | 3271.51 | 63.26 | 220 |
| synthetic_long_names.xml | ours-permissive | 6430.58 | 32.18 | 220 |
| synthetic_long_names.xml | stream-validated | 2596.65 | 79.70 | 220 |
| synthetic_long_names.xml | stream-permissive | 6204.73 | 33.36 | 220 |
| synthetic_long_names.xml | pugixml | 1392.15 | 39.87 | 59 |
| synthetic_long_names.xml | rapidxml | 1654.52 | 40.37 | 71 |
| synthetic_self_closing_swarm.xml | ours-validated | 1157.32 | 43.45 | 36 |
| synthetic_self_closing_swarm.xml | ours-permissive | 4670.28 | 65.80 | 220 |
| synthetic_self_closing_swarm.xml | stream-validated | 1354.86 | 40.21 | 39 |
| synthetic_self_closing_swarm.xml | stream-permissive | 5471.68 | 56.17 | 220 |
| synthetic_self_closing_swarm.xml | pugixml | 574.86 | 41.31 | 17 |
| synthetic_self_closing_swarm.xml | rapidxml | 460.87 | 42.43 | 14 |
| synthetic_mixed_content.xml | ours-validated | 1362.48 | 38.80 | 84 |
| synthetic_mixed_content.xml | ours-permissive | 2306.95 | 60.02 | 220 |
| synthetic_mixed_content.xml | stream-validated | 1392.69 | 40.22 | 89 |
| synthetic_mixed_content.xml | stream-permissive | 3130.30 | 44.23 | 220 |
| synthetic_mixed_content.xml | pugixml | 524.03 | 40.83 | 34 |
| synthetic_mixed_content.xml | rapidxml | 396.20 | 38.12 | 24 |
| synthetic_small_records.xml | ours-validated | 1378.95 | 39.72 | 46 |
| synthetic_small_records.xml | ours-permissive | 1916.97 | 39.75 | 64 |
| synthetic_small_records.xml | stream-validated | 1344.09 | 40.75 | 46 |
| synthetic_small_records.xml | stream-permissive | 2783.71 | 40.21 | 94 |
| synthetic_small_records.xml | pugixml | 425.77 | 41.95 | 15 |
| synthetic_small_records.xml | rapidxml | 301.11 | 43.50 | 11 |
| synthetic_tiny_empty.xml | ours-validated | 1720.05 | 40.42 | 79 |
| synthetic_tiny_empty.xml | ours-permissive | 1732.05 | 39.63 | 78 |
| synthetic_tiny_empty.xml | stream-validated | 7394.28 | 42.84 | 360 |
| synthetic_tiny_empty.xml | stream-permissive | 7416.80 | 42.71 | 360 |
| synthetic_tiny_empty.xml | pugixml | 192.12 | 41.22 | 9 |
| synthetic_tiny_empty.xml | rapidxml | 120.16 | 43.94 | 6 |
| synthetic_tiny_text.xml | ours-validated | 1749.24 | 40.61 | 74 |
| synthetic_tiny_text.xml | ours-permissive | 1763.30 | 40.29 | 74 |
| synthetic_tiny_text.xml | stream-validated | 15133.66 | 21.57 | 340 |
| synthetic_tiny_text.xml | stream-permissive | 15198.86 | 21.48 | 340 |
| synthetic_tiny_text.xml | pugixml | 181.29 | 42.36 | 8 |
| synthetic_tiny_text.xml | rapidxml | 123.27 | 46.73 | 6 |
| synthetic_one_attr.xml | ours-validated | 2960.46 | 40.43 | 133 |
| synthetic_one_attr.xml | ours-permissive | 2990.51 | 40.33 | 134 |
| synthetic_one_attr.xml | stream-validated | 10437.36 | 25.87 | 300 |
| synthetic_one_attr.xml | stream-permissive | 10505.99 | 25.70 | 300 |
| synthetic_one_attr.xml | pugixml | 236.77 | 30.41 | 8 |
| synthetic_one_attr.xml | rapidxml | 161.82 | 44.49 | 8 |
| synthetic_two_attr.xml | ours-validated | 5449.06 | 53.44 | 280 |
| synthetic_two_attr.xml | ours-permissive | 5461.72 | 53.32 | 280 |
| synthetic_two_attr.xml | stream-validated | 16705.59 | 40.34 | 648 |
| synthetic_two_attr.xml | stream-permissive | 16997.02 | 40.08 | 655 |
| synthetic_two_attr.xml | pugixml | 290.06 | 43.03 | 12 |
| synthetic_two_attr.xml | rapidxml | 213.50 | 43.84 | 9 |
| synthetic_attrs4.xml | ours-validated | 8540.75 | 29.90 | 240 |
| synthetic_attrs4.xml | ours-permissive | 8574.21 | 29.78 | 240 |
| synthetic_attrs4.xml | stream-validated | 21886.81 | 38.55 | 793 |
| synthetic_attrs4.xml | stream-permissive | 21832.56 | 39.23 | 805 |
| synthetic_attrs4.xml | pugixml | 329.26 | 42.01 | 13 |
| synthetic_attrs4.xml | rapidxml | 253.57 | 41.96 | 10 |
| synthetic_attrs8.xml | ours-validated | 12372.73 | 41.13 | 466 |
| synthetic_attrs8.xml | ours-permissive | 12609.67 | 40.18 | 464 |
| synthetic_attrs8.xml | stream-validated | 26089.28 | 40.60 | 970 |
| synthetic_attrs8.xml | stream-permissive | 25994.73 | 39.53 | 941 |
| synthetic_attrs8.xml | pugixml | 350.26 | 43.65 | 14 |
| synthetic_attrs8.xml | rapidxml | 266.27 | 41.01 | 10 |
| synthetic_single_quotes.xml | ours-validated | 9816.82 | 24.64 | 240 |
| synthetic_single_quotes.xml | ours-permissive | 9786.17 | 24.72 | 240 |
| synthetic_single_quotes.xml | stream-validated | 23385.45 | 38.75 | 899 |
| synthetic_single_quotes.xml | stream-permissive | 23297.40 | 39.94 | 923 |
| synthetic_single_quotes.xml | pugixml | 489.95 | 41.15 | 20 |
| synthetic_single_quotes.xml | rapidxml | 375.99 | 42.89 | 16 |
| synthetic_unicode_names.xml | ours-validated | 8489.89 | 26.12 | 180 |
| synthetic_unicode_names.xml | ours-permissive | 8592.19 | 25.81 | 180 |
| synthetic_unicode_names.xml | stream-validated | 29101.26 | 40.26 | 951 |
| synthetic_unicode_names.xml | stream-permissive | 29237.23 | 39.19 | 930 |
| synthetic_unicode_names.xml | pugixml | 642.70 | 40.26 | 21 |
| synthetic_unicode_names.xml | rapidxml | 544.00 | 40.76 | 18 |
| synthetic_pretty_indented.xml | ours-validated | 1346.93 | 40.12 | 57 |
| synthetic_pretty_indented.xml | ours-permissive | 1932.42 | 39.74 | 81 |
| synthetic_pretty_indented.xml | stream-validated | 1346.08 | 40.85 | 58 |
| synthetic_pretty_indented.xml | stream-permissive | 2271.95 | 38.81 | 93 |
| synthetic_pretty_indented.xml | pugixml | 497.21 | 41.95 | 22 |
| synthetic_pretty_indented.xml | rapidxml | 400.80 | 40.21 | 17 |
| synthetic_crlf_pretty.xml | ours-validated | 1222.65 | 40.04 | 60 |
| synthetic_crlf_pretty.xml | ours-permissive | 2031.23 | 38.97 | 97 |
| synthetic_crlf_pretty.xml | stream-validated | 1415.76 | 40.35 | 70 |
| synthetic_crlf_pretty.xml | stream-permissive | 2932.27 | 55.66 | 200 |
| synthetic_crlf_pretty.xml | pugixml | 524.77 | 40.43 | 26 |
| synthetic_crlf_pretty.xml | rapidxml | 437.24 | 41.06 | 22 |
| synthetic_token_whitespace_mix.xml | ours-validated | 8904.10 | 40.23 | 428 |
| synthetic_token_whitespace_mix.xml | ours-permissive | 9022.22 | 39.89 | 430 |
| synthetic_token_whitespace_mix.xml | stream-validated | 21278.67 | 40.08 | 1019 |
| synthetic_token_whitespace_mix.xml | stream-permissive | 21260.64 | 39.72 | 1009 |
| synthetic_token_whitespace_mix.xml | pugixml | 437.93 | 42.05 | 22 |
| synthetic_token_whitespace_mix.xml | rapidxml | 363.87 | 39.10 | 17 |
| synthetic_attr_count_mix.xml | ours-validated | 1419.09 | 41.91 | 14 |
| synthetic_attr_count_mix.xml | ours-permissive | 6628.53 | 41.02 | 64 |
| synthetic_attr_count_mix.xml | stream-validated | 1484.03 | 40.07 | 14 |
| synthetic_attr_count_mix.xml | stream-permissive | 8960.68 | 75.85 | 160 |
| synthetic_attr_count_mix.xml | pugixml | 394.33 | 43.09 | 4 |
| synthetic_attr_count_mix.xml | rapidxml | 310.12 | 41.09 | 3 |

## External Parser Gates

| Fixture | ours-permissive | pugixml | rapidxml | best external | ours/best-ext | Result |
|---|---:|---:|---:|---|---:|---|
| note.xml | 2876.74 | 977.97 | 1773.58 | rapidxml 1773.58 | 1.622 | PASS |
| sitemaps.xml | 4223.02 | 2067.23 | 2101.88 | rapidxml 2101.88 | 2.009 | PASS |
| plant_catalog.xml | 3624.58 | 1574.25 | 1680.87 | rapidxml 1680.87 | 2.156 | PASS |
| cd_catalog.xml | 3255.46 | 1503.05 | 1656.73 | rapidxml 1656.73 | 1.965 | PASS |
| hnrss.xml | 9970.37 | 2984.76 | 2722.01 | pugixml 2984.76 | 3.340 | PASS |
| xkcd_rss.xml | 8670.15 | 2530.09 | 2650.42 | rapidxml 2650.42 | 3.271 | PASS |
| bbc_world.xml | 5957.65 | 2628.28 | 2561.22 | pugixml 2628.28 | 2.267 | PASS |
| arxiv_cs.xml | 8451.59 | 2733.14 | 1897.48 | pugixml 2733.14 | 3.092 | PASS |
| ecb_usd.xml | 6813.26 | 2705.87 | 2751.16 | rapidxml 2751.16 | 2.477 | PASS |
| tree.xml | 2977.17 | 1275.77 | 2105.11 | rapidxml 2105.11 | 1.414 | PASS |
| character.xml | 3498.75 | 1181.24 | 2132.49 | rapidxml 2132.49 | 1.641 | PASS |
| transitions.xml | 3726.03 | 1472.48 | 2268.62 | rapidxml 2268.62 | 1.642 | PASS |
| xgconsole.xml | 6011.79 | 1895.04 | 2492.48 | rapidxml 2492.48 | 2.412 | PASS |
| weekly_utf8.xml | 3828.66 | 2248.38 | 2435.64 | rapidxml 2435.64 | 1.572 | PASS |
| pugixml_large.xml | 2567.86 | 481.54 | 308.00 | pugixml 481.54 | 5.333 | PASS |
| synthetic_flat_attrs.xml | 6787.72 | 467.18 | 351.47 | pugixml 467.18 | 14.529 | PASS |
| synthetic_deep_tree.xml | 1905.42 | 1283.16 | 777.19 | pugixml 1283.16 | 1.485 | PASS |
| synthetic_entities.xml | 10451.86 | 919.99 | 930.96 | rapidxml 930.96 | 11.227 | PASS |
| synthetic_cdata_mix.xml | 2361.87 | 690.78 | 525.21 | pugixml 690.78 | 3.419 | PASS |
| synthetic_wide_siblings.xml | 1552.51 | 430.08 | 316.79 | pugixml 430.08 | 3.610 | PASS |
| synthetic_namespace_mix.xml | 3785.66 | 700.09 | 577.30 | pugixml 700.09 | 5.407 | PASS |
| synthetic_long_names.xml | 6430.58 | 1392.15 | 1654.52 | rapidxml 1654.52 | 3.887 | PASS |
| synthetic_self_closing_swarm.xml | 4670.28 | 574.86 | 460.87 | pugixml 574.86 | 8.124 | PASS |
| synthetic_mixed_content.xml | 2306.95 | 524.03 | 396.20 | pugixml 524.03 | 4.402 | PASS |
| synthetic_small_records.xml | 1916.97 | 425.77 | 301.11 | pugixml 425.77 | 4.502 | PASS |
| synthetic_tiny_empty.xml | 1732.05 | 192.12 | 120.16 | pugixml 192.12 | 9.015 | PASS |
| synthetic_tiny_text.xml | 1763.30 | 181.29 | 123.27 | pugixml 181.29 | 9.727 | PASS |
| synthetic_one_attr.xml | 2990.51 | 236.77 | 161.82 | pugixml 236.77 | 12.630 | PASS |
| synthetic_two_attr.xml | 5461.72 | 290.06 | 213.50 | pugixml 290.06 | 18.829 | PASS |
| synthetic_attrs4.xml | 8574.21 | 329.26 | 253.57 | pugixml 329.26 | 26.041 | PASS |
| synthetic_attrs8.xml | 12609.67 | 350.26 | 266.27 | pugixml 350.26 | 36.001 | PASS |
| synthetic_single_quotes.xml | 9786.17 | 489.95 | 375.99 | pugixml 489.95 | 19.974 | PASS |
| synthetic_unicode_names.xml | 8592.19 | 642.70 | 544.00 | pugixml 642.70 | 13.369 | PASS |
| synthetic_pretty_indented.xml | 1932.42 | 497.21 | 400.80 | pugixml 497.21 | 3.887 | PASS |
| synthetic_crlf_pretty.xml | 2031.23 | 524.77 | 437.24 | pugixml 524.77 | 3.871 | PASS |
| synthetic_token_whitespace_mix.xml | 9022.22 | 437.93 | 363.87 | pugixml 437.93 | 20.602 | PASS |
| synthetic_attr_count_mix.xml | 6628.53 | 394.33 | 310.12 | pugixml 394.33 | 16.810 | PASS |

## Streaming Comparison (Advisory)

| Fixture | stream-permissive | ours-permissive | stream/ours | stream-validated | ours-validated | stream/ours |
|---|---:|---:|---:|---:|---:|---:|
| note.xml | 3282.15 | 2876.74 | 1.141 | 1392.80 | 1671.65 | 0.833 |
| sitemaps.xml | 3720.77 | 4223.02 | 0.881 | 1802.19 | 2128.56 | 0.847 |
| plant_catalog.xml | 3215.44 | 3624.58 | 0.887 | 1529.97 | 1866.88 | 0.820 |
| cd_catalog.xml | 2810.06 | 3255.46 | 0.863 | 1407.95 | 1736.88 | 0.811 |
| hnrss.xml | 8570.10 | 9970.37 | 0.860 | 4432.99 | 5510.29 | 0.804 |
| xkcd_rss.xml | 8792.88 | 8670.15 | 1.014 | 3439.53 | 4106.10 | 0.838 |
| bbc_world.xml | 5433.30 | 5957.65 | 0.912 | 3144.30 | 3459.30 | 0.909 |
| arxiv_cs.xml | 10686.52 | 8451.59 | 1.264 | 4577.96 | 4158.79 | 1.101 |
| ecb_usd.xml | 6032.57 | 6813.26 | 0.885 | 2859.11 | 3207.87 | 0.891 |
| tree.xml | 3109.66 | 2977.17 | 1.044 | 1368.22 | 1465.52 | 0.934 |
| character.xml | 3293.65 | 3498.75 | 0.941 | 1437.93 | 1477.28 | 0.973 |
| xgconsole.xml | 6078.22 | 6011.79 | 1.011 | 1334.16 | 2012.75 | 0.663 |
| weekly_utf8.xml | 3160.34 | 3828.66 | 0.825 | 691.95 | 1272.68 | 0.544 |
| pugixml_large.xml | 2113.79 | 2567.86 | 0.823 | 1677.26 | 1489.42 | 1.126 |
| synthetic_flat_attrs.xml | 8721.19 | 6787.72 | 1.285 | 1235.85 | 1329.41 | 0.930 |
| synthetic_deep_tree.xml | 1768.84 | 1905.42 | 0.928 | 1113.43 | 1163.96 | 0.957 |
| synthetic_entities.xml | 31495.76 | 10451.86 | 3.013 | 31127.85 | 10244.35 | 3.039 |
| synthetic_cdata_mix.xml | 2889.12 | 2361.87 | 1.223 | 1824.68 | 1783.06 | 1.023 |
| synthetic_wide_siblings.xml | 2251.36 | 1552.51 | 1.450 | 1126.05 | 1129.72 | 0.997 |
| synthetic_namespace_mix.xml | 4411.76 | 3785.66 | 1.165 | 1484.34 | 1452.84 | 1.022 |
| synthetic_long_names.xml | 6204.73 | 6430.58 | 0.965 | 2596.65 | 3271.51 | 0.794 |
| synthetic_self_closing_swarm.xml | 5471.68 | 4670.28 | 1.172 | 1354.86 | 1157.32 | 1.171 |
| synthetic_mixed_content.xml | 3130.30 | 2306.95 | 1.357 | 1392.69 | 1362.48 | 1.022 |
| synthetic_small_records.xml | 2783.71 | 1916.97 | 1.452 | 1344.09 | 1378.95 | 0.975 |
| synthetic_tiny_empty.xml | 7416.80 | 1732.05 | 4.282 | 7394.28 | 1720.05 | 4.299 |
| synthetic_tiny_text.xml | 15198.86 | 1763.30 | 8.620 | 15133.66 | 1749.24 | 8.652 |
| synthetic_one_attr.xml | 10505.99 | 2990.51 | 3.513 | 10437.36 | 2960.46 | 3.526 |
| synthetic_two_attr.xml | 16997.02 | 5461.72 | 3.112 | 16705.59 | 5449.06 | 3.066 |
| synthetic_attrs4.xml | 21832.56 | 8574.21 | 2.546 | 21886.81 | 8540.75 | 2.563 |
| synthetic_attrs8.xml | 25994.73 | 12609.67 | 2.061 | 26089.28 | 12372.73 | 2.109 |
| synthetic_single_quotes.xml | 23297.40 | 9786.17 | 2.381 | 23385.45 | 9816.82 | 2.382 |
| synthetic_unicode_names.xml | 29237.23 | 8592.19 | 3.403 | 29101.26 | 8489.89 | 3.428 |
| synthetic_pretty_indented.xml | 2271.95 | 1932.42 | 1.176 | 1346.08 | 1346.93 | 0.999 |
| synthetic_crlf_pretty.xml | 2932.27 | 2031.23 | 1.444 | 1415.76 | 1222.65 | 1.158 |
| synthetic_token_whitespace_mix.xml | 21260.64 | 9022.22 | 2.356 | 21278.67 | 8904.10 | 2.390 |
| synthetic_attr_count_mix.xml | 8960.68 | 6628.53 | 1.352 | 1484.03 | 1419.09 | 1.046 |

## Validated Pathology Regression Checks

2/2 passed. These fixtures are excluded from headline averages and stable external gates.
Detailed timings remain in `bench/results/latest.json` for regression analysis.
