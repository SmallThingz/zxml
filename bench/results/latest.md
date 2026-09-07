# ZXML Benchmark Results

Generated (unix): 1788787954

Profile: `stable`

Sampling: 5 rounds, target 40.0 ms per parser sample.

Collection: independently guarded fixture windows on CPU6, not one continuous quiet interval. Every retained fixture passed its complete calibration/sample guard.

## Benchmark Environment

| Property | Value |
|---|---|
| OS / kernel | Linux 7.2.2-zen1-1-zen |
| Architecture | x86_64 |
| CPU | 12th Gen Intel(R) Core(TM) i5-12450H |
| CPU frequency scaling | 85% |
| CPU MHz range | 400.0000–4400.0000 |
| Zig | 0.16.0 (`ReleaseFast -Dcpu=native`) |
| C++ driver | c++ (`-O3 -DNDEBUG -march=native`) |

## Parse Throughput

| Fixture | Parser | Throughput (MiB/s) | Median Time (ms) | Iterations |
|---|---|---:|---:|---:|
| note.xml | ours-validated | 1616.38 | 9.86 | 101886 |
| note.xml | ours-permissive | 2710.53 | 5.17 | 89577 |
| note.xml | stream-validated | 1344.83 | 6.63 | 57051 |
| note.xml | stream-permissive | 3060.98 | 8.28 | 161979 |
| note.xml | pugixml | 924.51 | 9.04 | 53414 |
| note.xml | rapidxml | 1670.73 | 10.28 | 109829 |
| sitemaps.xml | ours-validated | 1872.14 | 41.66 | 9486 |
| sitemaps.xml | ours-permissive | 3926.92 | 40.35 | 19272 |
| sitemaps.xml | stream-validated | 1680.71 | 38.70 | 7911 |
| sitemaps.xml | stream-permissive | 3349.58 | 39.08 | 15919 |
| sitemaps.xml | pugixml | 1894.83 | 38.82 | 8946 |
| sitemaps.xml | rapidxml | 1945.90 | 38.94 | 9215 |
| plant_catalog.xml | ours-validated | 1772.09 | 40.04 | 9626 |
| plant_catalog.xml | ours-permissive | 3498.65 | 39.21 | 18612 |
| plant_catalog.xml | stream-validated | 1485.97 | 38.06 | 7673 |
| plant_catalog.xml | stream-permissive | 3066.48 | 39.54 | 16448 |
| plant_catalog.xml | pugixml | 1501.72 | 37.93 | 7728 |
| plant_catalog.xml | rapidxml | 1647.44 | 39.47 | 8821 |
| cd_catalog.xml | ours-validated | 1583.38 | 38.87 | 13261 |
| cd_catalog.xml | ours-permissive | 2956.39 | 39.03 | 24862 |
| cd_catalog.xml | stream-validated | 1271.72 | 39.94 | 10945 |
| cd_catalog.xml | stream-permissive | 2629.61 | 24.83 | 14069 |
| cd_catalog.xml | pugixml | 1231.45 | 41.33 | 10967 |
| cd_catalog.xml | rapidxml | 1519.60 | 38.00 | 12442 |
| hnrss.xml | ours-validated | 5328.87 | 37.39 | 11305 |
| hnrss.xml | ours-permissive | 9446.27 | 40.26 | 21577 |
| hnrss.xml | stream-validated | 4260.97 | 40.36 | 9757 |
| hnrss.xml | stream-permissive | 7787.92 | 42.77 | 18901 |
| hnrss.xml | pugixml | 2824.64 | 38.82 | 6222 |
| hnrss.xml | rapidxml | 2601.58 | 39.76 | 5869 |
| xkcd_rss.xml | ours-validated | 2949.57 | 25.34 | 31795 |
| xkcd_rss.xml | ours-permissive | 4758.08 | 43.18 | 87401 |
| xkcd_rss.xml | stream-validated | 2621.26 | 24.46 | 27271 |
| xkcd_rss.xml | stream-permissive | 8037.94 | 19.72 | 67440 |
| xkcd_rss.xml | pugixml | 2340.50 | 23.08 | 22979 |
| xkcd_rss.xml | rapidxml | 1990.79 | 28.93 | 24499 |
| bbc_world.xml | ours-validated | 3284.26 | 37.95 | 5645 |
| bbc_world.xml | ours-permissive | 5898.02 | 39.47 | 10545 |
| bbc_world.xml | stream-validated | 3055.91 | 40.75 | 5640 |
| bbc_world.xml | stream-permissive | 5290.96 | 40.28 | 9652 |
| bbc_world.xml | pugixml | 2561.72 | 40.15 | 4658 |
| bbc_world.xml | rapidxml | 2483.25 | 39.58 | 4452 |
| arxiv_cs.xml | ours-validated | 4033.72 | 41.43 | 81 |
| arxiv_cs.xml | ours-permissive | 8205.69 | 45.26 | 180 |
| arxiv_cs.xml | stream-validated | 4293.52 | 40.85 | 85 |
| arxiv_cs.xml | stream-permissive | 10243.43 | 36.26 | 180 |
| arxiv_cs.xml | pugixml | 2574.02 | 42.49 | 53 |
| arxiv_cs.xml | rapidxml | 1831.41 | 40.56 | 36 |
| ecb_usd.xml | ours-validated | 3010.40 | 39.62 | 17126 |
| ecb_usd.xml | ours-permissive | 6375.85 | 41.74 | 38214 |
| ecb_usd.xml | stream-validated | 2605.24 | 38.31 | 14333 |
| ecb_usd.xml | stream-permissive | 5603.35 | 40.89 | 32900 |
| ecb_usd.xml | pugixml | 2517.22 | 40.62 | 14683 |
| ecb_usd.xml | rapidxml | 2654.68 | 38.70 | 14753 |
| tree.xml | ours-validated | 1328.39 | 35.93 | 203420 |
| tree.xml | ours-permissive | 2801.74 | 35.40 | 422778 |
| tree.xml | stream-validated | 1277.34 | 38.01 | 206933 |
| tree.xml | stream-permissive | 2877.49 | 38.49 | 472139 |
| tree.xml | pugixml | 1209.28 | 34.75 | 179108 |
| tree.xml | rapidxml | 1955.35 | 38.20 | 318398 |
| character.xml | ours-validated | 1403.29 | 31.40 | 255303 |
| character.xml | ours-permissive | 3298.52 | 29.84 | 570207 |
| character.xml | stream-validated | 1433.36 | 33.17 | 275475 |
| character.xml | stream-permissive | 3140.07 | 38.11 | 693334 |
| character.xml | pugixml | 1145.83 | 31.71 | 210471 |
| character.xml | rapidxml | 2024.72 | 37.97 | 445378 |
| transitions.xml | ours-permissive | 3541.43 | 36.62 | 650733 |
| transitions.xml | stream-permissive | 3289.86 | 35.03 | 578260 |
| transitions.xml | pugixml | 1426.50 | 32.72 | 234193 |
| transitions.xml | rapidxml | 2135.49 | 35.59 | 381330 |
| xgconsole.xml | ours-validated | 1888.62 | 36.63 | 100482 |
| xgconsole.xml | ours-permissive | 5798.87 | 37.29 | 314011 |
| xgconsole.xml | stream-validated | 1268.85 | 36.38 | 67042 |
| xgconsole.xml | stream-permissive | 5840.93 | 36.07 | 305957 |
| xgconsole.xml | pugixml | 1820.12 | 34.35 | 90803 |
| xgconsole.xml | rapidxml | 2364.01 | 39.51 | 135653 |
| weekly_utf8.xml | ours-validated | 1221.94 | 33.91 | 16578 |
| weekly_utf8.xml | ours-permissive | 3691.60 | 35.36 | 52216 |
| weekly_utf8.xml | stream-validated | 658.97 | 39.15 | 10320 |
| weekly_utf8.xml | stream-permissive | 3074.62 | 37.84 | 46544 |
| weekly_utf8.xml | pugixml | 2142.75 | 26.90 | 23063 |
| weekly_utf8.xml | rapidxml | 2325.07 | 36.05 | 33535 |
| pugixml_large.xml | ours-validated | 1370.61 | 40.82 | 838 |
| pugixml_large.xml | ours-permissive | 2415.13 | 40.86 | 1478 |
| pugixml_large.xml | stream-validated | 1549.74 | 26.15 | 607 |
| pugixml_large.xml | stream-permissive | 2028.36 | 40.39 | 1227 |
| pugixml_large.xml | pugixml | 439.38 | 40.57 | 267 |
| pugixml_large.xml | rapidxml | 278.44 | 41.25 | 172 |
| synthetic_flat_attrs.xml | ours-validated | 1223.95 | 49.50 | 280 |
| synthetic_flat_attrs.xml | ours-permissive | 6374.20 | 40.26 | 1186 |
| synthetic_flat_attrs.xml | stream-validated | 1298.43 | 46.66 | 280 |
| synthetic_flat_attrs.xml | stream-permissive | 8414.90 | 38.83 | 1510 |
| synthetic_flat_attrs.xml | pugixml | 443.47 | 40.50 | 83 |
| synthetic_flat_attrs.xml | rapidxml | 340.94 | 40.62 | 64 |
| synthetic_deep_tree.xml | ours-validated | 1051.91 | 43.27 | 26312 |
| synthetic_deep_tree.xml | ours-permissive | 1773.64 | 42.09 | 43157 |
| synthetic_deep_tree.xml | stream-validated | 1001.26 | 43.03 | 24906 |
| synthetic_deep_tree.xml | stream-permissive | 1628.88 | 42.14 | 39679 |
| synthetic_deep_tree.xml | pugixml | 1154.21 | 42.67 | 28471 |
| synthetic_deep_tree.xml | rapidxml | 717.33 | 42.68 | 17696 |
| synthetic_entities.xml | ours-validated | 10428.11 | 40.56 | 675 |
| synthetic_entities.xml | ours-permissive | 10571.02 | 39.42 | 665 |
| synthetic_entities.xml | stream-validated | 41611.67 | 40.57 | 2694 |
| synthetic_entities.xml | stream-permissive | 41964.96 | 40.88 | 2738 |
| synthetic_entities.xml | pugixml | 854.68 | 39.59 | 54 |
| synthetic_entities.xml | rapidxml | 839.22 | 41.06 | 55 |
| synthetic_cdata_mix.xml | ours-validated | 1596.07 | 40.33 | 546 |
| synthetic_cdata_mix.xml | ours-permissive | 2136.64 | 42.10 | 763 |
| synthetic_cdata_mix.xml | stream-validated | 1608.85 | 40.82 | 557 |
| synthetic_cdata_mix.xml | stream-permissive | 2574.32 | 40.99 | 895 |
| synthetic_cdata_mix.xml | pugixml | 624.12 | 45.34 | 240 |
| synthetic_cdata_mix.xml | rapidxml | 482.26 | 58.67 | 240 |
| synthetic_wide_siblings.xml | ours-validated | 1011.26 | 39.24 | 115 |
| synthetic_wide_siblings.xml | ours-permissive | 1440.51 | 62.28 | 260 |
| synthetic_wide_siblings.xml | stream-validated | 1061.09 | 36.42 | 112 |
| synthetic_wide_siblings.xml | stream-permissive | 2056.20 | 43.63 | 260 |
| synthetic_wide_siblings.xml | pugixml | 402.52 | 40.29 | 47 |
| synthetic_wide_siblings.xml | rapidxml | 299.01 | 39.23 | 34 |
| synthetic_namespace_mix.xml | ours-validated | 1337.48 | 40.08 | 95 |
| synthetic_namespace_mix.xml | ours-permissive | 3519.19 | 35.28 | 220 |
| synthetic_namespace_mix.xml | stream-validated | 1318.95 | 41.50 | 97 |
| synthetic_namespace_mix.xml | stream-permissive | 3949.04 | 31.44 | 220 |
| synthetic_namespace_mix.xml | pugixml | 651.98 | 40.68 | 47 |
| synthetic_namespace_mix.xml | rapidxml | 537.77 | 40.93 | 39 |
| synthetic_long_names.xml | ours-validated | 2980.36 | 66.23 | 220 |
| synthetic_long_names.xml | ours-permissive | 6043.50 | 32.66 | 220 |
| synthetic_long_names.xml | stream-validated | 2378.72 | 40.73 | 108 |
| synthetic_long_names.xml | stream-permissive | 5518.16 | 35.77 | 220 |
| synthetic_long_names.xml | pugixml | 1283.02 | 40.56 | 58 |
| synthetic_long_names.xml | rapidxml | 1512.84 | 42.11 | 71 |
| synthetic_self_closing_swarm.xml | ours-validated | 1130.58 | 40.06 | 34 |
| synthetic_self_closing_swarm.xml | ours-permissive | 4309.13 | 68.01 | 220 |
| synthetic_self_closing_swarm.xml | stream-validated | 1216.55 | 40.52 | 37 |
| synthetic_self_closing_swarm.xml | stream-permissive | 4972.03 | 58.95 | 220 |
| synthetic_self_closing_swarm.xml | pugixml | 558.47 | 40.55 | 17 |
| synthetic_self_closing_swarm.xml | rapidxml | 453.81 | 41.10 | 14 |
| synthetic_mixed_content.xml | ours-validated | 1280.35 | 39.85 | 85 |
| synthetic_mixed_content.xml | ours-permissive | 2087.17 | 63.27 | 220 |
| synthetic_mixed_content.xml | stream-validated | 1271.50 | 39.65 | 84 |
| synthetic_mixed_content.xml | stream-permissive | 2863.52 | 46.11 | 220 |
| synthetic_mixed_content.xml | pugixml | 497.66 | 41.01 | 34 |
| synthetic_mixed_content.xml | rapidxml | 376.04 | 41.50 | 26 |
| synthetic_small_records.xml | ours-validated | 1211.99 | 44.04 | 47 |
| synthetic_small_records.xml | ours-permissive | 1702.29 | 43.36 | 65 |
| synthetic_small_records.xml | stream-validated | 1180.37 | 42.33 | 44 |
| synthetic_small_records.xml | stream-permissive | 2349.05 | 44.47 | 92 |
| synthetic_small_records.xml | pugixml | 389.86 | 43.69 | 15 |
| synthetic_small_records.xml | rapidxml | 291.30 | 42.88 | 11 |
| synthetic_tiny_empty.xml | ours-validated | 1636.55 | 40.51 | 79 |
| synthetic_tiny_empty.xml | ours-permissive | 1651.12 | 40.15 | 79 |
| synthetic_tiny_empty.xml | stream-validated | 6749.94 | 44.76 | 360 |
| synthetic_tiny_empty.xml | stream-permissive | 6770.80 | 44.62 | 360 |
| synthetic_tiny_empty.xml | pugixml | 182.92 | 41.29 | 9 |
| synthetic_tiny_empty.xml | rapidxml | 116.60 | 43.19 | 6 |
| synthetic_tiny_text.xml | ours-validated | 1653.13 | 31.57 | 57 |
| synthetic_tiny_text.xml | ours-permissive | 1702.34 | 31.73 | 59 |
| synthetic_tiny_text.xml | stream-validated | 17327.74 | 39.52 | 748 |
| synthetic_tiny_text.xml | stream-permissive | 16961.26 | 39.89 | 739 |
| synthetic_tiny_text.xml | pugixml | 167.13 | 43.82 | 8 |
| synthetic_tiny_text.xml | rapidxml | 119.69 | 38.25 | 5 |
| synthetic_one_attr.xml | ours-validated | 3455.75 | 74.51 | 300 |
| synthetic_one_attr.xml | ours-permissive | 3469.50 | 74.22 | 300 |
| synthetic_one_attr.xml | stream-validated | 14103.14 | 40.05 | 658 |
| synthetic_one_attr.xml | stream-permissive | 14133.84 | 38.44 | 633 |
| synthetic_one_attr.xml | pugixml | 253.16 | 37.29 | 11 |
| synthetic_one_attr.xml | rapidxml | 175.32 | 44.06 | 9 |
| synthetic_two_attr.xml | ours-validated | 5482.92 | 50.65 | 280 |
| synthetic_two_attr.xml | ours-permissive | 5560.88 | 49.94 | 280 |
| synthetic_two_attr.xml | stream-validated | 20324.03 | 40.26 | 825 |
| synthetic_two_attr.xml | stream-permissive | 20242.09 | 40.37 | 824 |
| synthetic_two_attr.xml | pugixml | 286.78 | 41.50 | 12 |
| synthetic_two_attr.xml | rapidxml | 206.42 | 43.24 | 9 |
| synthetic_attrs4.xml | ours-validated | 8886.57 | 27.40 | 240 |
| synthetic_attrs4.xml | ours-permissive | 9006.86 | 27.04 | 240 |
| synthetic_attrs4.xml | stream-validated | 27480.11 | 39.36 | 1066 |
| synthetic_attrs4.xml | stream-permissive | 27617.51 | 40.31 | 1097 |
| synthetic_attrs4.xml | pugixml | 313.52 | 42.08 | 13 |
| synthetic_attrs4.xml | rapidxml | 238.09 | 42.62 | 10 |
| synthetic_attrs8.xml | ours-validated | 13906.16 | 40.74 | 544 |
| synthetic_attrs8.xml | ours-permissive | 13770.39 | 41.67 | 551 |
| synthetic_attrs8.xml | stream-validated | 34419.69 | 41.48 | 1371 |
| synthetic_attrs8.xml | stream-permissive | 34460.84 | 40.53 | 1341 |
| synthetic_attrs8.xml | pugixml | 335.59 | 43.45 | 14 |
| synthetic_attrs8.xml | rapidxml | 249.35 | 41.77 | 10 |
| synthetic_single_quotes.xml | ours-validated | 10301.90 | 22.40 | 240 |
| synthetic_single_quotes.xml | ours-permissive | 10456.10 | 22.07 | 240 |
| synthetic_single_quotes.xml | stream-validated | 29786.20 | 40.21 | 1246 |
| synthetic_single_quotes.xml | stream-permissive | 30381.89 | 41.67 | 1317 |
| synthetic_single_quotes.xml | pugixml | 460.49 | 41.75 | 20 |
| synthetic_single_quotes.xml | rapidxml | 360.11 | 42.71 | 16 |
| synthetic_unicode_names.xml | ours-validated | 8867.61 | 23.85 | 180 |
| synthetic_unicode_names.xml | ours-permissive | 8907.67 | 23.74 | 180 |
| synthetic_unicode_names.xml | stream-validated | 40805.38 | 40.14 | 1394 |
| synthetic_unicode_names.xml | stream-permissive | 41273.02 | 37.55 | 1319 |
| synthetic_unicode_names.xml | pugixml | 598.52 | 41.22 | 21 |
| synthetic_unicode_names.xml | rapidxml | 493.62 | 40.46 | 17 |
| synthetic_pretty_indented.xml | ours-validated | 1257.41 | 38.83 | 54 |
| synthetic_pretty_indented.xml | ours-permissive | 1768.50 | 39.88 | 78 |
| synthetic_pretty_indented.xml | stream-validated | 1275.17 | 39.70 | 56 |
| synthetic_pretty_indented.xml | stream-permissive | 2103.01 | 39.55 | 92 |
| synthetic_pretty_indented.xml | pugixml | 454.61 | 39.77 | 20 |
| synthetic_pretty_indented.xml | rapidxml | 357.08 | 40.51 | 16 |
| synthetic_crlf_pretty.xml | ours-validated | 1158.09 | 40.32 | 60 |
| synthetic_crlf_pretty.xml | ours-permissive | 1938.79 | 80.28 | 200 |
| synthetic_crlf_pretty.xml | stream-validated | 1320.77 | 40.66 | 69 |
| synthetic_crlf_pretty.xml | stream-permissive | 2774.32 | 56.10 | 200 |
| synthetic_crlf_pretty.xml | pugixml | 492.07 | 36.37 | 23 |
| synthetic_crlf_pretty.xml | rapidxml | 412.92 | 39.58 | 21 |
| synthetic_token_whitespace_mix.xml | ours-validated | 9771.83 | 39.62 | 485 |
| synthetic_token_whitespace_mix.xml | ours-permissive | 9736.01 | 40.50 | 494 |
| synthetic_token_whitespace_mix.xml | stream-validated | 28097.93 | 39.60 | 1394 |
| synthetic_token_whitespace_mix.xml | stream-permissive | 28132.67 | 40.77 | 1437 |
| synthetic_token_whitespace_mix.xml | pugixml | 422.24 | 37.81 | 20 |
| synthetic_token_whitespace_mix.xml | rapidxml | 345.14 | 39.32 | 17 |
| synthetic_attr_count_mix.xml | ours-validated | 1359.85 | 41.71 | 14 |
| synthetic_attr_count_mix.xml | ours-permissive | 6382.11 | 39.99 | 63 |
| synthetic_attr_count_mix.xml | stream-validated | 1408.88 | 40.26 | 14 |
| synthetic_attr_count_mix.xml | stream-permissive | 8592.25 | 75.44 | 160 |
| synthetic_attr_count_mix.xml | pugixml | 379.27 | 42.73 | 4 |
| synthetic_attr_count_mix.xml | rapidxml | 295.14 | 41.18 | 3 |

## External Parser Gates

| Fixture | ours-permissive | pugixml | rapidxml | best external | ours/best-ext | Result |
|---|---:|---:|---:|---|---:|---|
| note.xml | 2710.53 | 924.51 | 1670.73 | rapidxml 1670.73 | 1.622 | PASS |
| sitemaps.xml | 3926.92 | 1894.83 | 1945.90 | rapidxml 1945.90 | 2.018 | PASS |
| plant_catalog.xml | 3498.65 | 1501.72 | 1647.44 | rapidxml 1647.44 | 2.124 | PASS |
| cd_catalog.xml | 2956.39 | 1231.45 | 1519.60 | rapidxml 1519.60 | 1.946 | PASS |
| hnrss.xml | 9446.27 | 2824.64 | 2601.58 | pugixml 2824.64 | 3.344 | PASS |
| xkcd_rss.xml | 4758.08 | 2340.50 | 1990.79 | pugixml 2340.50 | 2.033 | PASS |
| bbc_world.xml | 5898.02 | 2561.72 | 2483.25 | pugixml 2561.72 | 2.302 | PASS |
| arxiv_cs.xml | 8205.69 | 2574.02 | 1831.41 | pugixml 2574.02 | 3.188 | PASS |
| ecb_usd.xml | 6375.85 | 2517.22 | 2654.68 | rapidxml 2654.68 | 2.402 | PASS |
| tree.xml | 2801.74 | 1209.28 | 1955.35 | rapidxml 1955.35 | 1.433 | PASS |
| character.xml | 3298.52 | 1145.83 | 2024.72 | rapidxml 2024.72 | 1.629 | PASS |
| transitions.xml | 3541.43 | 1426.50 | 2135.49 | rapidxml 2135.49 | 1.658 | PASS |
| xgconsole.xml | 5798.87 | 1820.12 | 2364.01 | rapidxml 2364.01 | 2.453 | PASS |
| weekly_utf8.xml | 3691.60 | 2142.75 | 2325.07 | rapidxml 2325.07 | 1.588 | PASS |
| pugixml_large.xml | 2415.13 | 439.38 | 278.44 | pugixml 439.38 | 5.497 | PASS |
| synthetic_flat_attrs.xml | 6374.20 | 443.47 | 340.94 | pugixml 443.47 | 14.373 | PASS |
| synthetic_deep_tree.xml | 1773.64 | 1154.21 | 717.33 | pugixml 1154.21 | 1.537 | PASS |
| synthetic_entities.xml | 10571.02 | 854.68 | 839.22 | pugixml 854.68 | 12.368 | PASS |
| synthetic_cdata_mix.xml | 2136.64 | 624.12 | 482.26 | pugixml 624.12 | 3.423 | PASS |
| synthetic_wide_siblings.xml | 1440.51 | 402.52 | 299.01 | pugixml 402.52 | 3.579 | PASS |
| synthetic_namespace_mix.xml | 3519.19 | 651.98 | 537.77 | pugixml 651.98 | 5.398 | PASS |
| synthetic_long_names.xml | 6043.50 | 1283.02 | 1512.84 | rapidxml 1512.84 | 3.995 | PASS |
| synthetic_self_closing_swarm.xml | 4309.13 | 558.47 | 453.81 | pugixml 558.47 | 7.716 | PASS |
| synthetic_mixed_content.xml | 2087.17 | 497.66 | 376.04 | pugixml 497.66 | 4.194 | PASS |
| synthetic_small_records.xml | 1702.29 | 389.86 | 291.30 | pugixml 389.86 | 4.366 | PASS |
| synthetic_tiny_empty.xml | 1651.12 | 182.92 | 116.60 | pugixml 182.92 | 9.027 | PASS |
| synthetic_tiny_text.xml | 1702.34 | 167.13 | 119.69 | pugixml 167.13 | 10.186 | PASS |
| synthetic_one_attr.xml | 3469.50 | 253.16 | 175.32 | pugixml 253.16 | 13.705 | PASS |
| synthetic_two_attr.xml | 5560.88 | 286.78 | 206.42 | pugixml 286.78 | 19.391 | PASS |
| synthetic_attrs4.xml | 9006.86 | 313.52 | 238.09 | pugixml 313.52 | 28.729 | PASS |
| synthetic_attrs8.xml | 13770.39 | 335.59 | 249.35 | pugixml 335.59 | 41.033 | PASS |
| synthetic_single_quotes.xml | 10456.10 | 460.49 | 360.11 | pugixml 460.49 | 22.706 | PASS |
| synthetic_unicode_names.xml | 8907.67 | 598.52 | 493.62 | pugixml 598.52 | 14.883 | PASS |
| synthetic_pretty_indented.xml | 1768.50 | 454.61 | 357.08 | pugixml 454.61 | 3.890 | PASS |
| synthetic_crlf_pretty.xml | 1938.79 | 492.07 | 412.92 | pugixml 492.07 | 3.940 | PASS |
| synthetic_token_whitespace_mix.xml | 9736.01 | 422.24 | 345.14 | pugixml 422.24 | 23.058 | PASS |
| synthetic_attr_count_mix.xml | 6382.11 | 379.27 | 295.14 | pugixml 379.27 | 16.827 | PASS |

## Streaming Comparison (Advisory)

| Fixture | stream-permissive | ours-permissive | stream/ours | stream-validated | ours-validated | stream/ours |
|---|---:|---:|---:|---:|---:|---:|
| note.xml | 3060.98 | 2710.53 | 1.129 | 1344.83 | 1616.38 | 0.832 |
| sitemaps.xml | 3349.58 | 3926.92 | 0.853 | 1680.71 | 1872.14 | 0.898 |
| plant_catalog.xml | 3066.48 | 3498.65 | 0.876 | 1485.97 | 1772.09 | 0.839 |
| cd_catalog.xml | 2629.61 | 2956.39 | 0.889 | 1271.72 | 1583.38 | 0.803 |
| hnrss.xml | 7787.92 | 9446.27 | 0.824 | 4260.97 | 5328.87 | 0.800 |
| xkcd_rss.xml | 8037.94 | 4758.08 | 1.689 | 2621.26 | 2949.57 | 0.889 |
| bbc_world.xml | 5290.96 | 5898.02 | 0.897 | 3055.91 | 3284.26 | 0.930 |
| arxiv_cs.xml | 10243.43 | 8205.69 | 1.248 | 4293.52 | 4033.72 | 1.064 |
| ecb_usd.xml | 5603.35 | 6375.85 | 0.879 | 2605.24 | 3010.40 | 0.865 |
| tree.xml | 2877.49 | 2801.74 | 1.027 | 1277.34 | 1328.39 | 0.962 |
| character.xml | 3140.07 | 3298.52 | 0.952 | 1433.36 | 1403.29 | 1.021 |
| xgconsole.xml | 5840.93 | 5798.87 | 1.007 | 1268.85 | 1888.62 | 0.672 |
| weekly_utf8.xml | 3074.62 | 3691.60 | 0.833 | 658.97 | 1221.94 | 0.539 |
| pugixml_large.xml | 2028.36 | 2415.13 | 0.840 | 1549.74 | 1370.61 | 1.131 |
| synthetic_flat_attrs.xml | 8414.90 | 6374.20 | 1.320 | 1298.43 | 1223.95 | 1.061 |
| synthetic_deep_tree.xml | 1628.88 | 1773.64 | 0.918 | 1001.26 | 1051.91 | 0.952 |
| synthetic_entities.xml | 41964.96 | 10571.02 | 3.970 | 41611.67 | 10428.11 | 3.990 |
| synthetic_cdata_mix.xml | 2574.32 | 2136.64 | 1.205 | 1608.85 | 1596.07 | 1.008 |
| synthetic_wide_siblings.xml | 2056.20 | 1440.51 | 1.427 | 1061.09 | 1011.26 | 1.049 |
| synthetic_namespace_mix.xml | 3949.04 | 3519.19 | 1.122 | 1318.95 | 1337.48 | 0.986 |
| synthetic_long_names.xml | 5518.16 | 6043.50 | 0.913 | 2378.72 | 2980.36 | 0.798 |
| synthetic_self_closing_swarm.xml | 4972.03 | 4309.13 | 1.154 | 1216.55 | 1130.58 | 1.076 |
| synthetic_mixed_content.xml | 2863.52 | 2087.17 | 1.372 | 1271.50 | 1280.35 | 0.993 |
| synthetic_small_records.xml | 2349.05 | 1702.29 | 1.380 | 1180.37 | 1211.99 | 0.974 |
| synthetic_tiny_empty.xml | 6770.80 | 1651.12 | 4.101 | 6749.94 | 1636.55 | 4.124 |
| synthetic_tiny_text.xml | 16961.26 | 1702.34 | 9.963 | 17327.74 | 1653.13 | 10.482 |
| synthetic_one_attr.xml | 14133.84 | 3469.50 | 4.074 | 14103.14 | 3455.75 | 4.081 |
| synthetic_two_attr.xml | 20242.09 | 5560.88 | 3.640 | 20324.03 | 5482.92 | 3.707 |
| synthetic_attrs4.xml | 27617.51 | 9006.86 | 3.066 | 27480.11 | 8886.57 | 3.092 |
| synthetic_attrs8.xml | 34460.84 | 13770.39 | 2.503 | 34419.69 | 13906.16 | 2.475 |
| synthetic_single_quotes.xml | 30381.89 | 10456.10 | 2.906 | 29786.20 | 10301.90 | 2.891 |
| synthetic_unicode_names.xml | 41273.02 | 8907.67 | 4.633 | 40805.38 | 8867.61 | 4.602 |
| synthetic_pretty_indented.xml | 2103.01 | 1768.50 | 1.189 | 1275.17 | 1257.41 | 1.014 |
| synthetic_crlf_pretty.xml | 2774.32 | 1938.79 | 1.431 | 1320.77 | 1158.09 | 1.140 |
| synthetic_token_whitespace_mix.xml | 28132.67 | 9736.01 | 2.890 | 28097.93 | 9771.83 | 2.875 |
| synthetic_attr_count_mix.xml | 8592.25 | 6382.11 | 1.346 | 1408.88 | 1359.85 | 1.036 |

## Validated Pathology Regression Checks

2/2 passed. These fixtures are excluded from headline averages and stable external gates.
Detailed timings remain in `bench/results/latest.json` for regression analysis.
