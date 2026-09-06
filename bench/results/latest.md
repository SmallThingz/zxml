# ZXML Benchmark Results

Generated (unix): 1788699488

Profile: `stable`

Collection: independently guarded fixture windows on CPU6, not one continuous quiet interval. Every retained fixture passed its complete calibration/sample guard.

## Benchmark Environment

| Property | Value |
|---|---|
| OS / kernel | Linux 7.2.2-zen1-1-zen |
| Architecture | x86_64 |
| CPU | 12th Gen Intel(R) Core(TM) i5-12450H |
| CPU frequency scaling | 49% |
| CPU MHz range | 400.0000–4400.0000 |
| Zig | 0.16.0 (`ReleaseFast -Dcpu=native`) |
| C++ driver | c++ (`-O3 -DNDEBUG -march=native`) |

## Parse Throughput

| Fixture | Parser | Throughput (MB/s) | Median Time (ms) | Iterations |
|---|---|---:|---:|---:|
| note.xml | ours-validated | 1269.93 | 14.54 | 112561 |
| note.xml | ours-permissive | 1820.87 | 15.58 | 173008 |
| note.xml | stream-validated | 1332.73 | 7.00 | 56858 |
| note.xml | stream-permissive | 3118.17 | 6.97 | 132438 |
| note.xml | pugixml | 978.17 | 9.84 | 58684 |
| note.xml | rapidxml | 1761.17 | 14.90 | 160060 |
| sitemaps.xml | ours-validated | 1980.62 | 39.91 | 9169 |
| sitemaps.xml | ours-permissive | 3395.95 | 39.64 | 15612 |
| sitemaps.xml | stream-validated | 1758.25 | 37.40 | 7626 |
| sitemaps.xml | stream-permissive | 3483.56 | 39.29 | 15874 |
| sitemaps.xml | pugixml | 2072.76 | 40.10 | 9641 |
| sitemaps.xml | rapidxml | 2112.42 | 38.30 | 9384 |
| plant_catalog.xml | ours-validated | 1748.93 | 40.64 | 9196 |
| plant_catalog.xml | ours-permissive | 2876.22 | 38.52 | 14334 |
| plant_catalog.xml | stream-validated | 1534.82 | 40.50 | 8043 |
| plant_catalog.xml | stream-permissive | 2805.79 | 40.01 | 14523 |
| plant_catalog.xml | pugixml | 1576.05 | 39.03 | 7958 |
| plant_catalog.xml | rapidxml | 1744.48 | 38.20 | 8622 |
| cd_catalog.xml | ours-validated | 1563.04 | 40.82 | 13112 |
| cd_catalog.xml | ours-permissive | 2617.65 | 39.53 | 21263 |
| cd_catalog.xml | stream-validated | 1403.77 | 37.54 | 10829 |
| cd_catalog.xml | stream-permissive | 2491.90 | 37.88 | 19399 |
| cd_catalog.xml | pugixml | 1497.39 | 36.67 | 11283 |
| cd_catalog.xml | rapidxml | 1655.87 | 39.52 | 13447 |
| hnrss.xml | ours-validated | 4636.90 | 36.95 | 9272 |
| hnrss.xml | ours-permissive | 7481.62 | 40.07 | 16220 |
| hnrss.xml | stream-validated | 4236.12 | 38.44 | 8812 |
| hnrss.xml | stream-permissive | 8216.29 | 39.48 | 17552 |
| hnrss.xml | pugixml | 3050.58 | 39.13 | 6459 |
| hnrss.xml | rapidxml | 2754.78 | 39.72 | 5921 |
| xkcd_rss.xml | ours-validated | 3956.60 | 37.77 | 60624 |
| xkcd_rss.xml | ours-permissive | 7129.64 | 38.01 | 109937 |
| xkcd_rss.xml | stream-validated | 3384.85 | 38.92 | 53442 |
| xkcd_rss.xml | stream-permissive | 7946.52 | 39.25 | 126525 |
| xkcd_rss.xml | pugixml | 2605.74 | 35.55 | 37578 |
| xkcd_rss.xml | rapidxml | 2693.07 | 38.79 | 42375 |
| bbc_world.xml | ours-validated | 3088.58 | 38.82 | 5179 |
| bbc_world.xml | ours-permissive | 5091.32 | 37.78 | 8308 |
| bbc_world.xml | stream-validated | 3100.97 | 39.87 | 5340 |
| bbc_world.xml | stream-permissive | 5034.58 | 39.12 | 8507 |
| bbc_world.xml | pugixml | 2708.13 | 38.98 | 4560 |
| bbc_world.xml | rapidxml | 2602.18 | 39.74 | 4467 |
| arxiv_cs.xml | ours-validated | 4149.59 | 40.67 | 78 |
| arxiv_cs.xml | ours-permissive | 7437.63 | 52.36 | 180 |
| arxiv_cs.xml | stream-validated | 4634.33 | 40.62 | 87 |
| arxiv_cs.xml | stream-permissive | 10075.60 | 38.65 | 180 |
| arxiv_cs.xml | pugixml | 2789.99 | 41.88 | 54 |
| arxiv_cs.xml | rapidxml | 1982.26 | 40.39 | 37 |
| ecb_usd.xml | ours-validated | 2978.03 | 36.93 | 15062 |
| ecb_usd.xml | ours-permissive | 5088.04 | 39.15 | 27282 |
| ecb_usd.xml | stream-validated | 2841.47 | 39.31 | 15296 |
| ecb_usd.xml | stream-permissive | 5004.15 | 39.76 | 27250 |
| ecb_usd.xml | pugixml | 2766.60 | 37.61 | 14248 |
| ecb_usd.xml | rapidxml | 2816.33 | 38.92 | 15011 |
| tree.xml | ours-validated | 1132.83 | 33.71 | 155217 |
| tree.xml | ours-permissive | 2207.66 | 32.66 | 293121 |
| tree.xml | stream-validated | 1336.84 | 36.50 | 198360 |
| tree.xml | stream-permissive | 2750.07 | 34.21 | 382440 |
| tree.xml | pugixml | 1299.88 | 33.38 | 176377 |
| tree.xml | rapidxml | 2129.72 | 37.75 | 326776 |
| character.xml | ours-validated | 1089.11 | 32.46 | 195302 |
| character.xml | ours-permissive | 1944.32 | 33.65 | 361488 |
| character.xml | stream-validated | 1298.18 | 36.02 | 258334 |
| character.xml | stream-permissive | 2725.73 | 37.35 | 562436 |
| character.xml | pugixml | 1193.56 | 34.66 | 228557 |
| character.xml | rapidxml | 2143.18 | 37.12 | 439524 |
| transitions.xml | ours-permissive | 1928.89 | 33.42 | 308469 |
| transitions.xml | stream-permissive | 2496.69 | 34.14 | 407892 |
| transitions.xml | pugixml | 1492.32 | 33.57 | 239687 |
| transitions.xml | rapidxml | 2235.63 | 34.09 | 364695 |
| xgconsole.xml | ours-validated | 1564.13 | 36.34 | 78727 |
| xgconsole.xml | ours-permissive | 4411.75 | 34.90 | 213263 |
| xgconsole.xml | stream-validated | 1273.57 | 38.78 | 68408 |
| xgconsole.xml | stream-permissive | 3707.01 | 40.05 | 205646 |
| xgconsole.xml | pugixml | 1936.52 | 37.36 | 100212 |
| xgconsole.xml | rapidxml | 2536.45 | 39.58 | 139034 |
| weekly_utf8.xml | ours-validated | 529.86 | 38.52 | 7787 |
| weekly_utf8.xml | ours-permissive | 3252.47 | 31.32 | 38864 |
| weekly_utf8.xml | stream-validated | 533.09 | 36.10 | 7343 |
| weekly_utf8.xml | stream-permissive | 3075.37 | 38.32 | 44959 |
| weekly_utf8.xml | pugixml | 2282.57 | 33.49 | 29164 |
| weekly_utf8.xml | rapidxml | 2465.93 | 36.99 | 34805 |
| pugixml_large.xml | ours-validated | 1026.80 | 39.07 | 573 |
| pugixml_large.xml | ours-permissive | 1161.49 | 37.43 | 621 |
| pugixml_large.xml | stream-validated | 1701.05 | 37.66 | 915 |
| pugixml_large.xml | stream-permissive | 2026.14 | 40.08 | 1160 |
| pugixml_large.xml | pugixml | 497.83 | 38.11 | 271 |
| pugixml_large.xml | rapidxml | 317.68 | 39.45 | 179 |
| synthetic_flat_attrs.xml | ours-validated | 883.06 | 71.95 | 280 |
| synthetic_flat_attrs.xml | ours-permissive | 3063.87 | 20.74 | 280 |
| synthetic_flat_attrs.xml | stream-validated | 1010.82 | 62.85 | 280 |
| synthetic_flat_attrs.xml | stream-permissive | 2746.43 | 23.13 | 280 |
| synthetic_flat_attrs.xml | pugixml | 478.02 | 40.82 | 86 |
| synthetic_flat_attrs.xml | rapidxml | 371.81 | 41.50 | 68 |
| synthetic_deep_tree.xml | ours-validated | 930.37 | 39.52 | 20271 |
| synthetic_deep_tree.xml | ours-permissive | 1214.39 | 37.31 | 24974 |
| synthetic_deep_tree.xml | stream-validated | 1050.21 | 40.56 | 23483 |
| synthetic_deep_tree.xml | stream-permissive | 1512.08 | 39.53 | 32949 |
| synthetic_deep_tree.xml | pugixml | 1332.92 | 37.08 | 27247 |
| synthetic_deep_tree.xml | rapidxml | 804.49 | 38.62 | 17126 |
| synthetic_entities.xml | ours-validated | 879.48 | 38.10 | 51 |
| synthetic_entities.xml | ours-permissive | 3254.04 | 48.46 | 240 |
| synthetic_entities.xml | stream-validated | 840.03 | 39.11 | 50 |
| synthetic_entities.xml | stream-permissive | 5742.69 | 27.46 | 240 |
| synthetic_entities.xml | pugixml | 922.52 | 41.31 | 58 |
| synthetic_entities.xml | rapidxml | 955.09 | 37.83 | 55 |
| synthetic_cdata_mix.xml | ours-validated | 1572.44 | 38.21 | 486 |
| synthetic_cdata_mix.xml | ours-permissive | 2086.74 | 39.22 | 662 |
| synthetic_cdata_mix.xml | stream-validated | 1778.76 | 38.02 | 547 |
| synthetic_cdata_mix.xml | stream-permissive | 2881.91 | 39.38 | 918 |
| synthetic_cdata_mix.xml | pugixml | 701.81 | 42.28 | 240 |
| synthetic_cdata_mix.xml | rapidxml | 536.23 | 55.33 | 240 |
| synthetic_wide_siblings.xml | ours-validated | 925.89 | 40.64 | 104 |
| synthetic_wide_siblings.xml | ours-permissive | 1063.46 | 39.46 | 116 |
| synthetic_wide_siblings.xml | stream-validated | 1056.44 | 40.41 | 118 |
| synthetic_wide_siblings.xml | stream-permissive | 2356.82 | 39.91 | 260 |
| synthetic_wide_siblings.xml | pugixml | 447.00 | 39.66 | 49 |
| synthetic_wide_siblings.xml | rapidxml | 334.21 | 40.05 | 37 |
| synthetic_namespace_mix.xml | ours-validated | 1414.34 | 40.17 | 96 |
| synthetic_namespace_mix.xml | ours-permissive | 2619.58 | 49.70 | 220 |
| synthetic_namespace_mix.xml | stream-validated | 1458.73 | 38.94 | 96 |
| synthetic_namespace_mix.xml | stream-permissive | 3248.64 | 40.07 | 220 |
| synthetic_namespace_mix.xml | pugixml | 716.02 | 40.50 | 49 |
| synthetic_namespace_mix.xml | rapidxml | 593.17 | 40.90 | 41 |
| synthetic_long_names.xml | ours-validated | 2897.58 | 71.43 | 220 |
| synthetic_long_names.xml | ours-permissive | 5028.88 | 41.15 | 220 |
| synthetic_long_names.xml | stream-validated | 2703.45 | 76.56 | 220 |
| synthetic_long_names.xml | stream-permissive | 4712.40 | 43.92 | 220 |
| synthetic_long_names.xml | pugixml | 1394.19 | 39.81 | 59 |
| synthetic_long_names.xml | rapidxml | 1709.02 | 40.18 | 73 |
| synthetic_self_closing_swarm.xml | ours-validated | 1230.24 | 40.88 | 36 |
| synthetic_self_closing_swarm.xml | ours-permissive | 3295.75 | 39.84 | 94 |
| synthetic_self_closing_swarm.xml | stream-validated | 1380.90 | 40.46 | 40 |
| synthetic_self_closing_swarm.xml | stream-permissive | 3331.63 | 40.25 | 96 |
| synthetic_self_closing_swarm.xml | pugixml | 629.92 | 42.13 | 19 |
| synthetic_self_closing_swarm.xml | rapidxml | 520.59 | 40.25 | 15 |
| synthetic_mixed_content.xml | ours-validated | 1259.27 | 39.98 | 80 |
| synthetic_mixed_content.xml | ours-permissive | 1921.97 | 72.04 | 220 |
| synthetic_mixed_content.xml | stream-validated | 1417.30 | 39.97 | 90 |
| synthetic_mixed_content.xml | stream-permissive | 2903.93 | 47.68 | 220 |
| synthetic_mixed_content.xml | pugixml | 561.72 | 40.34 | 36 |
| synthetic_mixed_content.xml | rapidxml | 423.76 | 41.59 | 28 |
| synthetic_small_records.xml | ours-validated | 1279.28 | 40.95 | 44 |
| synthetic_small_records.xml | ours-permissive | 1530.74 | 41.23 | 53 |
| synthetic_small_records.xml | stream-validated | 1320.36 | 39.68 | 44 |
| synthetic_small_records.xml | stream-permissive | 2305.56 | 40.28 | 78 |
| synthetic_small_records.xml | pugixml | 451.75 | 42.17 | 16 |
| synthetic_small_records.xml | rapidxml | 334.23 | 42.75 | 12 |
| synthetic_tiny_empty.xml | ours-validated | 858.47 | 41.00 | 40 |
| synthetic_tiny_empty.xml | ours-permissive | 1061.67 | 42.27 | 51 |
| synthetic_tiny_empty.xml | stream-validated | 1261.70 | 40.45 | 58 |
| synthetic_tiny_empty.xml | stream-permissive | 1575.63 | 40.21 | 72 |
| synthetic_tiny_empty.xml | pugixml | 205.17 | 42.89 | 10 |
| synthetic_tiny_empty.xml | rapidxml | 124.55 | 42.39 | 6 |
| synthetic_tiny_text.xml | ours-validated | 813.60 | 40.12 | 34 |
| synthetic_tiny_text.xml | ours-permissive | 768.91 | 41.20 | 33 |
| synthetic_tiny_text.xml | stream-validated | 703.72 | 40.93 | 30 |
| synthetic_tiny_text.xml | stream-permissive | 1000.32 | 40.31 | 42 |
| synthetic_tiny_text.xml | pugixml | 183.37 | 41.88 | 8 |
| synthetic_tiny_text.xml | rapidxml | 124.68 | 46.20 | 6 |
| synthetic_one_attr.xml | ours-validated | 712.42 | 40.43 | 32 |
| synthetic_one_attr.xml | ours-permissive | 934.38 | 40.46 | 42 |
| synthetic_one_attr.xml | stream-validated | 983.81 | 41.17 | 45 |
| synthetic_one_attr.xml | stream-permissive | 1829.44 | 39.85 | 81 |
| synthetic_one_attr.xml | pugixml | 287.06 | 40.76 | 13 |
| synthetic_one_attr.xml | rapidxml | 192.73 | 42.03 | 9 |
| synthetic_two_attr.xml | ours-validated | 809.62 | 42.39 | 33 |
| synthetic_two_attr.xml | ours-permissive | 1284.07 | 40.50 | 50 |
| synthetic_two_attr.xml | stream-validated | 1025.48 | 41.58 | 41 |
| synthetic_two_attr.xml | stream-permissive | 1936.90 | 40.81 | 76 |
| synthetic_two_attr.xml | pugixml | 318.41 | 42.46 | 13 |
| synthetic_two_attr.xml | rapidxml | 225.44 | 41.52 | 9 |
| synthetic_attrs4.xml | ours-validated | 807.76 | 40.83 | 31 |
| synthetic_attrs4.xml | ours-permissive | 1746.26 | 40.21 | 66 |
| synthetic_attrs4.xml | stream-validated | 1027.21 | 40.40 | 39 |
| synthetic_attrs4.xml | stream-permissive | 2296.01 | 39.39 | 85 |
| synthetic_attrs4.xml | pugixml | 345.32 | 43.14 | 14 |
| synthetic_attrs4.xml | rapidxml | 257.94 | 41.25 | 10 |
| synthetic_attrs8.xml | ours-validated | 786.73 | 40.25 | 29 |
| synthetic_attrs8.xml | ours-permissive | 2912.58 | 74.99 | 200 |
| synthetic_attrs8.xml | stream-validated | 1052.47 | 40.47 | 39 |
| synthetic_attrs8.xml | stream-permissive | 2553.02 | 39.78 | 93 |
| synthetic_attrs8.xml | pugixml | 370.66 | 41.25 | 14 |
| synthetic_attrs8.xml | rapidxml | 277.28 | 43.32 | 11 |
| synthetic_single_quotes.xml | ours-validated | 1033.68 | 39.98 | 41 |
| synthetic_single_quotes.xml | ours-permissive | 2407.54 | 39.78 | 95 |
| synthetic_single_quotes.xml | stream-validated | 1210.53 | 39.97 | 48 |
| synthetic_single_quotes.xml | stream-permissive | 3003.86 | 39.93 | 119 |
| synthetic_single_quotes.xml | pugixml | 533.85 | 41.54 | 22 |
| synthetic_single_quotes.xml | rapidxml | 420.43 | 40.76 | 17 |
| synthetic_unicode_names.xml | ours-validated | 426.87 | 40.41 | 14 |
| synthetic_unicode_names.xml | ours-permissive | 2090.45 | 40.67 | 69 |
| synthetic_unicode_names.xml | stream-validated | 454.71 | 40.64 | 15 |
| synthetic_unicode_names.xml | stream-permissive | 3265.36 | 67.91 | 180 |
| synthetic_unicode_names.xml | pugixml | 654.08 | 41.44 | 22 |
| synthetic_unicode_names.xml | rapidxml | 554.23 | 40.01 | 18 |
| synthetic_pretty_indented.xml | ours-validated | 1056.70 | 40.37 | 45 |
| synthetic_pretty_indented.xml | ours-permissive | 1305.17 | 40.68 | 56 |
| synthetic_pretty_indented.xml | stream-validated | 1210.50 | 40.72 | 52 |
| synthetic_pretty_indented.xml | stream-permissive | 2271.65 | 40.06 | 96 |
| synthetic_pretty_indented.xml | pugixml | 511.41 | 40.78 | 22 |
| synthetic_pretty_indented.xml | rapidxml | 409.14 | 41.71 | 18 |
| synthetic_crlf_pretty.xml | ours-validated | 1066.04 | 40.57 | 53 |
| synthetic_crlf_pretty.xml | ours-permissive | 1399.68 | 40.81 | 70 |
| synthetic_crlf_pretty.xml | stream-validated | 1308.24 | 40.54 | 65 |
| synthetic_crlf_pretty.xml | stream-permissive | 2908.00 | 56.12 | 200 |
| synthetic_crlf_pretty.xml | pugixml | 537.92 | 40.96 | 27 |
| synthetic_crlf_pretty.xml | rapidxml | 439.15 | 40.88 | 22 |
| synthetic_token_whitespace_mix.xml | ours-validated | 803.06 | 40.65 | 39 |
| synthetic_token_whitespace_mix.xml | ours-permissive | 2047.80 | 40.47 | 99 |
| synthetic_token_whitespace_mix.xml | stream-validated | 1013.56 | 40.47 | 49 |
| synthetic_token_whitespace_mix.xml | stream-permissive | 1470.45 | 40.98 | 72 |
| synthetic_token_whitespace_mix.xml | pugixml | 459.11 | 40.11 | 22 |
| synthetic_token_whitespace_mix.xml | rapidxml | 373.89 | 40.30 | 18 |
| synthetic_attr_count_mix.xml | ours-validated | 985.28 | 43.11 | 10 |
| synthetic_attr_count_mix.xml | ours-permissive | 3156.85 | 40.37 | 30 |
| synthetic_attr_count_mix.xml | stream-validated | 1043.25 | 40.72 | 10 |
| synthetic_attr_count_mix.xml | stream-permissive | 2774.07 | 38.28 | 25 |
| synthetic_attr_count_mix.xml | pugixml | 391.53 | 43.40 | 4 |
| synthetic_attr_count_mix.xml | rapidxml | 307.86 | 41.40 | 3 |

## Stable Gates

| Fixture | ours-permissive | pugixml | rapidxml | best external | ours/best-ext | Result |
|---|---:|---:|---:|---|---:|---|
| note.xml | 1820.87 | 978.17 | 1761.17 | rapidxml 1761.17 | 1.034 | PASS |
| sitemaps.xml | 3395.95 | 2072.76 | 2112.42 | rapidxml 2112.42 | 1.608 | PASS |
| plant_catalog.xml | 2876.22 | 1576.05 | 1744.48 | rapidxml 1744.48 | 1.649 | PASS |
| cd_catalog.xml | 2617.65 | 1497.39 | 1655.87 | rapidxml 1655.87 | 1.581 | PASS |
| hnrss.xml | 7481.62 | 3050.58 | 2754.78 | pugixml 3050.58 | 2.453 | PASS |
| xkcd_rss.xml | 7129.64 | 2605.74 | 2693.07 | rapidxml 2693.07 | 2.647 | PASS |
| bbc_world.xml | 5091.32 | 2708.13 | 2602.18 | pugixml 2708.13 | 1.880 | PASS |
| arxiv_cs.xml | 7437.63 | 2789.99 | 1982.26 | pugixml 2789.99 | 2.666 | PASS |
| ecb_usd.xml | 5088.04 | 2766.60 | 2816.33 | rapidxml 2816.33 | 1.807 | PASS |
| tree.xml | 2207.66 | 1299.88 | 2129.72 | rapidxml 2129.72 | 1.037 | PASS |
| character.xml | 1944.32 | 1193.56 | 2143.18 | rapidxml 2143.18 | 0.907 | FAIL |
| transitions.xml | 1928.89 | 1492.32 | 2235.63 | rapidxml 2235.63 | 0.863 | FAIL |
| xgconsole.xml | 4411.75 | 1936.52 | 2536.45 | rapidxml 2536.45 | 1.739 | PASS |
| weekly_utf8.xml | 3252.47 | 2282.57 | 2465.93 | rapidxml 2465.93 | 1.319 | PASS |
| pugixml_large.xml | 1161.49 | 497.83 | 317.68 | pugixml 497.83 | 2.333 | PASS |
| synthetic_flat_attrs.xml | 3063.87 | 478.02 | 371.81 | pugixml 478.02 | 6.410 | PASS |
| synthetic_deep_tree.xml | 1214.39 | 1332.92 | 804.49 | pugixml 1332.92 | 0.911 | FAIL |
| synthetic_entities.xml | 3254.04 | 922.52 | 955.09 | rapidxml 955.09 | 3.407 | PASS |
| synthetic_cdata_mix.xml | 2086.74 | 701.81 | 536.23 | pugixml 701.81 | 2.973 | PASS |
| synthetic_wide_siblings.xml | 1063.46 | 447.00 | 334.21 | pugixml 447.00 | 2.379 | PASS |
| synthetic_namespace_mix.xml | 2619.58 | 716.02 | 593.17 | pugixml 716.02 | 3.659 | PASS |
| synthetic_long_names.xml | 5028.88 | 1394.19 | 1709.02 | rapidxml 1709.02 | 2.943 | PASS |
| synthetic_self_closing_swarm.xml | 3295.75 | 629.92 | 520.59 | pugixml 629.92 | 5.232 | PASS |
| synthetic_mixed_content.xml | 1921.97 | 561.72 | 423.76 | pugixml 561.72 | 3.422 | PASS |
| synthetic_small_records.xml | 1530.74 | 451.75 | 334.23 | pugixml 451.75 | 3.388 | PASS |
| synthetic_tiny_empty.xml | 1061.67 | 205.17 | 124.55 | pugixml 205.17 | 5.175 | PASS |
| synthetic_tiny_text.xml | 768.91 | 183.37 | 124.68 | pugixml 183.37 | 4.193 | PASS |
| synthetic_one_attr.xml | 934.38 | 287.06 | 192.73 | pugixml 287.06 | 3.255 | PASS |
| synthetic_two_attr.xml | 1284.07 | 318.41 | 225.44 | pugixml 318.41 | 4.033 | PASS |
| synthetic_attrs4.xml | 1746.26 | 345.32 | 257.94 | pugixml 345.32 | 5.057 | PASS |
| synthetic_attrs8.xml | 2912.58 | 370.66 | 277.28 | pugixml 370.66 | 7.858 | PASS |
| synthetic_single_quotes.xml | 2407.54 | 533.85 | 420.43 | pugixml 533.85 | 4.510 | PASS |
| synthetic_unicode_names.xml | 2090.45 | 654.08 | 554.23 | pugixml 654.08 | 3.196 | PASS |
| synthetic_pretty_indented.xml | 1305.17 | 511.41 | 409.14 | pugixml 511.41 | 2.552 | PASS |
| synthetic_crlf_pretty.xml | 1399.68 | 537.92 | 439.15 | pugixml 537.92 | 2.602 | PASS |
| synthetic_token_whitespace_mix.xml | 2047.80 | 459.11 | 373.89 | pugixml 459.11 | 4.460 | PASS |
| synthetic_attr_count_mix.xml | 3156.85 | 391.53 | 307.86 | pugixml 391.53 | 8.063 | PASS |

## Streaming Comparison (Advisory)

| Fixture | stream-permissive | ours-permissive | stream/ours | stream-validated | ours-validated | stream/ours |
|---|---:|---:|---:|---:|---:|---:|
| note.xml | 3118.17 | 1820.87 | 1.712 | 1332.73 | 1269.93 | 1.049 |
| sitemaps.xml | 3483.56 | 3395.95 | 1.026 | 1758.25 | 1980.62 | 0.888 |
| plant_catalog.xml | 2805.79 | 2876.22 | 0.976 | 1534.82 | 1748.93 | 0.878 |
| cd_catalog.xml | 2491.90 | 2617.65 | 0.952 | 1403.77 | 1563.04 | 0.898 |
| hnrss.xml | 8216.29 | 7481.62 | 1.098 | 4236.12 | 4636.90 | 0.914 |
| xkcd_rss.xml | 7946.52 | 7129.64 | 1.115 | 3384.85 | 3956.60 | 0.855 |
| bbc_world.xml | 5034.58 | 5091.32 | 0.989 | 3100.97 | 3088.58 | 1.004 |
| arxiv_cs.xml | 10075.60 | 7437.63 | 1.355 | 4634.33 | 4149.59 | 1.117 |
| ecb_usd.xml | 5004.15 | 5088.04 | 0.984 | 2841.47 | 2978.03 | 0.954 |
| tree.xml | 2750.07 | 2207.66 | 1.246 | 1336.84 | 1132.83 | 1.180 |
| character.xml | 2725.73 | 1944.32 | 1.402 | 1298.18 | 1089.11 | 1.192 |
| xgconsole.xml | 3707.01 | 4411.75 | 0.840 | 1273.57 | 1564.13 | 0.814 |
| weekly_utf8.xml | 3075.37 | 3252.47 | 0.946 | 533.09 | 529.86 | 1.006 |
| pugixml_large.xml | 2026.14 | 1161.49 | 1.744 | 1701.05 | 1026.80 | 1.657 |
| synthetic_flat_attrs.xml | 2746.43 | 3063.87 | 0.896 | 1010.82 | 883.06 | 1.145 |
| synthetic_deep_tree.xml | 1512.08 | 1214.39 | 1.245 | 1050.21 | 930.37 | 1.129 |
| synthetic_entities.xml | 5742.69 | 3254.04 | 1.765 | 840.03 | 879.48 | 0.955 |
| synthetic_cdata_mix.xml | 2881.91 | 2086.74 | 1.381 | 1778.76 | 1572.44 | 1.131 |
| synthetic_wide_siblings.xml | 2356.82 | 1063.46 | 2.216 | 1056.44 | 925.89 | 1.141 |
| synthetic_namespace_mix.xml | 3248.64 | 2619.58 | 1.240 | 1458.73 | 1414.34 | 1.031 |
| synthetic_long_names.xml | 4712.40 | 5028.88 | 0.937 | 2703.45 | 2897.58 | 0.933 |
| synthetic_self_closing_swarm.xml | 3331.63 | 3295.75 | 1.011 | 1380.90 | 1230.24 | 1.122 |
| synthetic_mixed_content.xml | 2903.93 | 1921.97 | 1.511 | 1417.30 | 1259.27 | 1.125 |
| synthetic_small_records.xml | 2305.56 | 1530.74 | 1.506 | 1320.36 | 1279.28 | 1.032 |
| synthetic_tiny_empty.xml | 1575.63 | 1061.67 | 1.484 | 1261.70 | 858.47 | 1.470 |
| synthetic_tiny_text.xml | 1000.32 | 768.91 | 1.301 | 703.72 | 813.60 | 0.865 |
| synthetic_one_attr.xml | 1829.44 | 934.38 | 1.958 | 983.81 | 712.42 | 1.381 |
| synthetic_two_attr.xml | 1936.90 | 1284.07 | 1.508 | 1025.48 | 809.62 | 1.267 |
| synthetic_attrs4.xml | 2296.01 | 1746.26 | 1.315 | 1027.21 | 807.76 | 1.272 |
| synthetic_attrs8.xml | 2553.02 | 2912.58 | 0.877 | 1052.47 | 786.73 | 1.338 |
| synthetic_single_quotes.xml | 3003.86 | 2407.54 | 1.248 | 1210.53 | 1033.68 | 1.171 |
| synthetic_unicode_names.xml | 3265.36 | 2090.45 | 1.562 | 454.71 | 426.87 | 1.065 |
| synthetic_pretty_indented.xml | 2271.65 | 1305.17 | 1.740 | 1210.50 | 1056.70 | 1.146 |
| synthetic_crlf_pretty.xml | 2908.00 | 1399.68 | 2.078 | 1308.24 | 1066.04 | 1.227 |
| synthetic_token_whitespace_mix.xml | 1470.45 | 2047.80 | 0.718 | 1013.56 | 803.06 | 1.262 |
| synthetic_attr_count_mix.xml | 2774.07 | 3156.85 | 0.879 | 1043.25 | 985.28 | 1.059 |

## Validated Pathology Regression Checks

2/2 passed. These fixtures are excluded from headline averages and stable external gates.
Detailed timings remain in `bench/results/latest.json` for regression analysis.
