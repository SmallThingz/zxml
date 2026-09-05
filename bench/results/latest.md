# ZXML Benchmark Results

Generated (unix): 1788628222

Profile: `stable`

## Benchmark Environment

| Property | Value |
|---|---|
| OS / kernel | Linux 7.2.2-zen1-1-zen |
| Architecture | x86_64 |
| CPU | 12th Gen Intel(R) Core(TM) i5-12450H |
| CPU frequency scaling | 71% |
| CPU MHz range | 400.0000–4400.0000 |
| Zig | 0.16.0 (`ReleaseFast -Dcpu=native`) |
| C++ driver | c++ (`-O3 -DNDEBUG -march=native`) |

## Parse Throughput

| Fixture | Parser | Throughput (MB/s) | Median Time (ms) | Iterations |
|---|---|---:|---:|---:|
| note.xml | ours-strict | 1243.73 | 23.41 | 177523 |
| note.xml | ours-turbo | 1686.11 | 26.91 | 276626 |
| note.xml | stream-strict | 555.53 | 36.78 | 124601 |
| note.xml | stream-turbo | 1311.73 | 32.01 | 256055 |
| note.xml | pugixml | 494.33 | 40.69 | 122645 |
| note.xml | rapidxml | 1047.10 | 34.23 | 218536 |
| sitemaps.xml | ours-strict | 1200.96 | 41.81 | 5824 |
| sitemaps.xml | ours-turbo | 1838.85 | 42.09 | 8977 |
| sitemaps.xml | stream-strict | 703.19 | 60.08 | 4900 |
| sitemaps.xml | stream-turbo | 1466.80 | 29.69 | 5051 |
| sitemaps.xml | pugixml | 1051.67 | 21.70 | 2647 |
| sitemaps.xml | rapidxml | 934.81 | 66.08 | 7165 |
| plant_catalog.xml | ours-strict | 1102.87 | 41.80 | 5964 |
| plant_catalog.xml | ours-turbo | 1470.19 | 43.14 | 8205 |
| plant_catalog.xml | stream-strict | 693.02 | 40.45 | 3627 |
| plant_catalog.xml | stream-turbo | 1294.66 | 39.36 | 6593 |
| plant_catalog.xml | pugixml | 849.08 | 38.81 | 4264 |
| plant_catalog.xml | rapidxml | 887.11 | 42.49 | 4877 |
| cd_catalog.xml | ours-strict | 1291.05 | 31.47 | 8350 |
| cd_catalog.xml | ours-turbo | 2437.88 | 22.69 | 11370 |
| cd_catalog.xml | stream-strict | 994.94 | 47.21 | 9652 |
| cd_catalog.xml | stream-turbo | 2049.67 | 18.17 | 7652 |
| cd_catalog.xml | pugixml | 1146.65 | 42.14 | 9930 |
| cd_catalog.xml | rapidxml | 1049.53 | 28.75 | 6200 |
| hnrss.xml | ours-strict | 5674.19 | 20.61 | 6327 |
| hnrss.xml | ours-turbo | 6289.14 | 24.43 | 8313 |
| hnrss.xml | stream-strict | 1870.51 | 74.83 | 7574 |
| hnrss.xml | stream-turbo | 5960.54 | 47.57 | 15341 |
| hnrss.xml | pugixml | 2070.08 | 27.22 | 3049 |
| hnrss.xml | rapidxml | 1921.18 | 26.67 | 2772 |
| xkcd_rss.xml | ours-strict | 3561.08 | 30.81 | 44504 |
| xkcd_rss.xml | ours-turbo | 4240.64 | 69.69 | 119898 |
| xkcd_rss.xml | stream-strict | 2541.37 | 41.23 | 42508 |
| xkcd_rss.xml | stream-turbo | 5433.81 | 21.30 | 46943 |
| xkcd_rss.xml | pugixml | 1656.36 | 30.43 | 20445 |
| xkcd_rss.xml | rapidxml | 1822.67 | 46.46 | 34357 |
| bbc_world.xml | ours-strict | 2219.58 | 37.85 | 3629 |
| bbc_world.xml | ours-turbo | 2938.79 | 36.91 | 4685 |
| bbc_world.xml | stream-strict | 1906.21 | 16.40 | 1350 |
| bbc_world.xml | stream-turbo | 2140.71 | 44.79 | 4142 |
| bbc_world.xml | pugixml | 1334.61 | 36.78 | 2120 |
| bbc_world.xml | rapidxml | 1436.93 | 30.77 | 1910 |
| arxiv_cs.xml | ours-strict | 7170.69 | 54.31 | 180 |
| arxiv_cs.xml | ours-turbo | 8732.06 | 44.60 | 180 |
| arxiv_cs.xml | stream-strict | 2801.15 | 53.30 | 69 |
| arxiv_cs.xml | stream-turbo | 8118.85 | 47.97 | 180 |
| arxiv_cs.xml | pugixml | 2350.92 | 36.81 | 40 |
| arxiv_cs.xml | rapidxml | 1473.89 | 46.98 | 32 |
| ecb_usd.xml | ours-strict | 4007.11 | 25.93 | 14227 |
| ecb_usd.xml | ours-turbo | 6121.18 | 23.73 | 19893 |
| ecb_usd.xml | stream-strict | 2588.37 | 18.88 | 6693 |
| ecb_usd.xml | stream-turbo | 4155.32 | 23.25 | 13228 |
| ecb_usd.xml | pugixml | 2610.04 | 23.61 | 8440 |
| ecb_usd.xml | rapidxml | 2589.26 | 25.69 | 9110 |
| tree.xml | ours-strict | 2356.14 | 18.39 | 176144 |
| tree.xml | ours-turbo | 2919.67 | 15.30 | 181633 |
| tree.xml | stream-strict | 1285.06 | 20.42 | 106659 |
| tree.xml | stream-turbo | 2546.84 | 37.28 | 385915 |
| tree.xml | pugixml | 1253.41 | 22.60 | 115154 |
| tree.xml | rapidxml | 1828.42 | 23.65 | 175812 |
| character.xml | ours-strict | 2775.16 | 16.34 | 250543 |
| character.xml | ours-turbo | 3631.57 | 17.25 | 346079 |
| character.xml | stream-strict | 1172.10 | 22.11 | 143188 |
| character.xml | stream-turbo | 2630.01 | 19.55 | 284076 |
| character.xml | pugixml | 1092.17 | 20.23 | 122091 |
| character.xml | rapidxml | 2035.39 | 21.66 | 243537 |
| transitions.xml | ours-turbo | 3484.99 | 17.88 | 298140 |
| transitions.xml | stream-turbo | 2848.85 | 17.77 | 242154 |
| transitions.xml | pugixml | 1242.86 | 23.65 | 140611 |
| transitions.xml | rapidxml | 2144.24 | 37.53 | 385086 |
| xgconsole.xml | ours-strict | 4262.09 | 38.76 | 228813 |
| xgconsole.xml | ours-turbo | 5409.40 | 21.69 | 162499 |
| xgconsole.xml | stream-strict | 1166.76 | 21.35 | 34496 |
| xgconsole.xml | stream-turbo | 3001.26 | 21.90 | 91016 |
| xgconsole.xml | pugixml | 1871.76 | 22.25 | 57683 |
| xgconsole.xml | rapidxml | 2313.24 | 25.57 | 81930 |
| weekly_utf8.xml | ours-strict | 3021.09 | 21.24 | 24478 |
| weekly_utf8.xml | ours-turbo | 4193.75 | 21.40 | 34236 |
| weekly_utf8.xml | stream-strict | 551.90 | 19.14 | 4030 |
| weekly_utf8.xml | stream-turbo | 3067.86 | 39.78 | 46557 |
| weekly_utf8.xml | pugixml | 2051.42 | 38.38 | 30040 |
| weekly_utf8.xml | rapidxml | 2381.51 | 25.33 | 23019 |
| pugixml_large.xml | ours-strict | 1752.98 | 41.14 | 1030 |
| pugixml_large.xml | ours-turbo | 3210.80 | 22.20 | 1018 |
| pugixml_large.xml | stream-strict | 1617.14 | 42.08 | 972 |
| pugixml_large.xml | stream-turbo | 2476.28 | 21.69 | 767 |
| pugixml_large.xml | pugixml | 426.96 | 29.52 | 180 |
| pugixml_large.xml | rapidxml | 313.76 | 31.46 | 141 |
| synthetic_flat_attrs.xml | ours-strict | 4926.59 | 43.62 | 947 |
| synthetic_flat_attrs.xml | ours-turbo | 5643.61 | 29.11 | 724 |
| synthetic_flat_attrs.xml | stream-strict | 993.77 | 63.93 | 280 |
| synthetic_flat_attrs.xml | stream-turbo | 2606.42 | 24.38 | 280 |
| synthetic_flat_attrs.xml | pugixml | 486.24 | 40.60 | 87 |
| synthetic_flat_attrs.xml | rapidxml | 373.81 | 40.06 | 66 |
| synthetic_deep_tree.xml | ours-strict | 1436.70 | 21.81 | 17274 |
| synthetic_deep_tree.xml | ours-turbo | 2078.30 | 24.37 | 27919 |
| synthetic_deep_tree.xml | stream-strict | 927.95 | 20.69 | 10583 |
| synthetic_deep_tree.xml | stream-turbo | 1757.40 | 21.98 | 21290 |
| synthetic_deep_tree.xml | pugixml | 1242.41 | 40.43 | 27694 |
| synthetic_deep_tree.xml | rapidxml | 777.01 | 36.47 | 15620 |
| synthetic_entities.xml | ours-strict | 4494.52 | 35.08 | 240 |
| synthetic_entities.xml | ours-turbo | 4468.79 | 35.29 | 240 |
| synthetic_entities.xml | stream-strict | 781.11 | 40.37 | 48 |
| synthetic_entities.xml | stream-turbo | 4648.55 | 33.92 | 240 |
| synthetic_entities.xml | pugixml | 907.44 | 39.10 | 54 |
| synthetic_entities.xml | rapidxml | 870.97 | 40.73 | 54 |
| synthetic_cdata_mix.xml | ours-strict | 2550.98 | 30.39 | 627 |
| synthetic_cdata_mix.xml | ours-turbo | 2717.29 | 41.81 | 919 |
| synthetic_cdata_mix.xml | stream-strict | 1538.11 | 19.29 | 240 |
| synthetic_cdata_mix.xml | stream-turbo | 2199.95 | 37.76 | 672 |
| synthetic_cdata_mix.xml | pugixml | 677.45 | 43.80 | 240 |
| synthetic_cdata_mix.xml | rapidxml | 513.87 | 57.74 | 240 |
| synthetic_wide_siblings.xml | ours-strict | 2103.69 | 44.71 | 260 |
| synthetic_wide_siblings.xml | ours-turbo | 2739.32 | 34.34 | 260 |
| synthetic_wide_siblings.xml | stream-strict | 983.16 | 41.22 | 112 |
| synthetic_wide_siblings.xml | stream-turbo | 2062.52 | 45.61 | 260 |
| synthetic_wide_siblings.xml | pugixml | 442.36 | 40.08 | 49 |
| synthetic_wide_siblings.xml | rapidxml | 341.92 | 35.98 | 34 |
| synthetic_namespace_mix.xml | ours-strict | 3193.36 | 40.77 | 220 |
| synthetic_namespace_mix.xml | ours-turbo | 3890.10 | 33.47 | 220 |
| synthetic_namespace_mix.xml | stream-strict | 1460.91 | 42.53 | 105 |
| synthetic_namespace_mix.xml | stream-turbo | 3037.16 | 42.86 | 220 |
| synthetic_namespace_mix.xml | pugixml | 649.88 | 28.23 | 31 |
| synthetic_namespace_mix.xml | rapidxml | 573.16 | 29.94 | 29 |
| synthetic_long_names.xml | ours-strict | 5577.67 | 37.11 | 220 |
| synthetic_long_names.xml | ours-turbo | 5679.88 | 36.44 | 220 |
| synthetic_long_names.xml | stream-strict | 2399.59 | 86.25 | 220 |
| synthetic_long_names.xml | stream-turbo | 3631.39 | 56.99 | 220 |
| synthetic_long_names.xml | pugixml | 1271.73 | 45.12 | 61 |
| synthetic_long_names.xml | rapidxml | 1545.93 | 44.42 | 73 |
| synthetic_self_closing_swarm.xml | ours-strict | 2831.61 | 39.96 | 81 |
| synthetic_self_closing_swarm.xml | ours-turbo | 3253.94 | 39.92 | 93 |
| synthetic_self_closing_swarm.xml | stream-strict | 1207.28 | 40.50 | 35 |
| synthetic_self_closing_swarm.xml | stream-turbo | 3001.55 | 42.82 | 92 |
| synthetic_self_closing_swarm.xml | pugixml | 516.23 | 40.59 | 15 |
| synthetic_self_closing_swarm.xml | rapidxml | 404.11 | 48.39 | 14 |
| synthetic_mixed_content.xml | ours-strict | 1627.00 | 85.10 | 220 |
| synthetic_mixed_content.xml | ours-turbo | 1938.63 | 71.42 | 220 |
| synthetic_mixed_content.xml | stream-strict | 1040.67 | 48.38 | 80 |
| synthetic_mixed_content.xml | stream-turbo | 2064.47 | 67.07 | 220 |
| synthetic_mixed_content.xml | pugixml | 301.20 | 68.96 | 33 |
| synthetic_mixed_content.xml | rapidxml | 258.64 | 60.84 | 25 |
| synthetic_small_records.xml | ours-strict | 2101.89 | 34.56 | 61 |
| synthetic_small_records.xml | ours-turbo | 2964.85 | 80.32 | 200 |
| synthetic_small_records.xml | stream-strict | 1000.36 | 46.42 | 39 |
| synthetic_small_records.xml | stream-turbo | 1894.94 | 50.90 | 81 |
| synthetic_small_records.xml | pugixml | 347.92 | 44.49 | 13 |
| synthetic_small_records.xml | rapidxml | 292.87 | 40.66 | 10 |
| synthetic_tiny_empty.xml | ours-strict | 1667.15 | 39.06 | 74 |
| synthetic_tiny_empty.xml | ours-turbo | 1991.25 | 40.66 | 92 |
| synthetic_tiny_empty.xml | stream-strict | 1178.29 | 39.58 | 53 |
| synthetic_tiny_empty.xml | stream-turbo | 1550.31 | 39.73 | 70 |
| synthetic_tiny_empty.xml | pugixml | 197.62 | 40.08 | 9 |
| synthetic_tiny_empty.xml | rapidxml | 120.05 | 43.98 | 6 |
| synthetic_tiny_text.xml | ours-strict | 1144.24 | 45.31 | 54 |
| synthetic_tiny_text.xml | ours-turbo | 1330.79 | 52.66 | 73 |
| synthetic_tiny_text.xml | stream-strict | 531.98 | 50.53 | 28 |
| synthetic_tiny_text.xml | stream-turbo | 1128.06 | 48.51 | 57 |
| synthetic_tiny_text.xml | pugixml | 133.14 | 43.26 | 6 |
| synthetic_tiny_text.xml | rapidxml | 105.95 | 36.24 | 4 |
| synthetic_one_attr.xml | ours-strict | 1925.48 | 33.19 | 71 |
| synthetic_one_attr.xml | ours-turbo | 1971.52 | 52.50 | 115 |
| synthetic_one_attr.xml | stream-strict | 814.04 | 42.01 | 38 |
| synthetic_one_attr.xml | stream-turbo | 1614.90 | 25.64 | 46 |
| synthetic_one_attr.xml | pugixml | 173.23 | 57.15 | 11 |
| synthetic_one_attr.xml | rapidxml | 144.26 | 49.91 | 8 |
| synthetic_two_attr.xml | ours-strict | 1317.61 | 80.51 | 102 |
| synthetic_two_attr.xml | ours-turbo | 2473.70 | 48.35 | 115 |
| synthetic_two_attr.xml | stream-strict | 799.80 | 48.11 | 37 |
| synthetic_two_attr.xml | stream-turbo | 1413.15 | 47.10 | 64 |
| synthetic_two_attr.xml | pugixml | 246.92 | 46.33 | 11 |
| synthetic_two_attr.xml | rapidxml | 117.25 | 70.96 | 8 |
| synthetic_attrs4.xml | ours-strict | 2861.94 | 41.64 | 112 |
| synthetic_attrs4.xml | ours-turbo | 3048.38 | 83.77 | 240 |
| synthetic_attrs4.xml | stream-strict | 674.62 | 52.05 | 33 |
| synthetic_attrs4.xml | stream-turbo | 1773.62 | 41.99 | 70 |
| synthetic_attrs4.xml | pugixml | 225.65 | 51.87 | 11 |
| synthetic_attrs4.xml | rapidxml | 182.75 | 34.93 | 6 |
| synthetic_attrs8.xml | ours-strict | 1868.62 | 116.88 | 200 |
| synthetic_attrs8.xml | ours-turbo | 1906.76 | 114.54 | 200 |
| synthetic_attrs8.xml | stream-strict | 448.43 | 70.62 | 29 |
| synthetic_attrs8.xml | stream-turbo | 1076.50 | 76.08 | 75 |
| synthetic_attrs8.xml | pugixml | 156.49 | 48.85 | 7 |
| synthetic_attrs8.xml | rapidxml | 135.58 | 48.33 | 6 |
| synthetic_single_quotes.xml | ours-strict | 1636.32 | 43.12 | 70 |
| synthetic_single_quotes.xml | ours-turbo | 2231.88 | 37.94 | 84 |
| synthetic_single_quotes.xml | stream-strict | 491.94 | 49.18 | 24 |
| synthetic_single_quotes.xml | stream-turbo | 1295.20 | 44.36 | 57 |
| synthetic_single_quotes.xml | pugixml | 224.86 | 44.83 | 10 |
| synthetic_single_quotes.xml | rapidxml | 180.25 | 44.74 | 8 |
| synthetic_unicode_names.xml | ours-strict | 1250.93 | 46.29 | 47 |
| synthetic_unicode_names.xml | ours-turbo | 1577.46 | 53.11 | 68 |
| synthetic_unicode_names.xml | stream-strict | 204.92 | 42.09 | 7 |
| synthetic_unicode_names.xml | stream-turbo | 1244.94 | 47.50 | 48 |
| synthetic_unicode_names.xml | pugixml | 258.03 | 47.75 | 10 |
| synthetic_unicode_names.xml | rapidxml | 232.70 | 47.65 | 9 |
| synthetic_pretty_indented.xml | ours-strict | 946.82 | 40.05 | 40 |
| synthetic_pretty_indented.xml | ours-turbo | 1255.82 | 50.58 | 67 |
| synthetic_pretty_indented.xml | stream-strict | 518.18 | 45.74 | 25 |
| synthetic_pretty_indented.xml | stream-turbo | 951.78 | 42.83 | 43 |
| synthetic_pretty_indented.xml | pugixml | 211.66 | 44.79 | 10 |
| synthetic_pretty_indented.xml | rapidxml | 192.93 | 44.22 | 9 |
| synthetic_crlf_pretty.xml | ours-strict | 1096.45 | 38.70 | 52 |
| synthetic_crlf_pretty.xml | ours-turbo | 1071.17 | 44.95 | 59 |
| synthetic_crlf_pretty.xml | stream-strict | 558.77 | 40.89 | 28 |
| synthetic_crlf_pretty.xml | stream-turbo | 1218.60 | 35.49 | 53 |
| synthetic_crlf_pretty.xml | pugixml | 228.09 | 42.93 | 12 |
| synthetic_crlf_pretty.xml | rapidxml | 194.51 | 41.95 | 10 |
| synthetic_token_whitespace_mix.xml | ours-strict | 1494.35 | 35.29 | 63 |
| synthetic_token_whitespace_mix.xml | ours-turbo | 1823.80 | 44.06 | 96 |
| synthetic_token_whitespace_mix.xml | stream-strict | 488.62 | 42.83 | 25 |
| synthetic_token_whitespace_mix.xml | stream-turbo | 787.23 | 40.40 | 38 |
| synthetic_token_whitespace_mix.xml | pugixml | 204.52 | 36.83 | 9 |
| synthetic_token_whitespace_mix.xml | rapidxml | 179.51 | 37.30 | 8 |
| synthetic_attr_count_mix.xml | ours-strict | 2715.20 | 29.73 | 19 |
| synthetic_attr_count_mix.xml | ours-turbo | 2963.30 | 38.71 | 27 |
| synthetic_attr_count_mix.xml | stream-strict | 461.32 | 46.04 | 5 |
| synthetic_attr_count_mix.xml | stream-turbo | 1227.28 | 34.61 | 10 |
| synthetic_attr_count_mix.xml | pugixml | 170.13 | 49.94 | 2 |
| synthetic_attr_count_mix.xml | rapidxml | 155.03 | 54.80 | 2 |

## Stable Gates

| Fixture | ours-turbo | pugixml | rapidxml | best external | ours/best-ext | Result |
|---|---:|---:|---:|---|---:|---|
| note.xml | 1686.11 | 494.33 | 1047.10 | rapidxml 1047.10 | 1.610 | PASS |
| sitemaps.xml | 1838.85 | 1051.67 | 934.81 | pugixml 1051.67 | 1.748 | PASS |
| plant_catalog.xml | 1470.19 | 849.08 | 887.11 | rapidxml 887.11 | 1.657 | PASS |
| cd_catalog.xml | 2437.88 | 1146.65 | 1049.53 | pugixml 1146.65 | 2.126 | PASS |
| hnrss.xml | 6289.14 | 2070.08 | 1921.18 | pugixml 2070.08 | 3.038 | PASS |
| xkcd_rss.xml | 4240.64 | 1656.36 | 1822.67 | rapidxml 1822.67 | 2.327 | PASS |
| bbc_world.xml | 2938.79 | 1334.61 | 1436.93 | rapidxml 1436.93 | 2.045 | PASS |
| arxiv_cs.xml | 8732.06 | 2350.92 | 1473.89 | pugixml 2350.92 | 3.714 | PASS |
| ecb_usd.xml | 6121.18 | 2610.04 | 2589.26 | pugixml 2610.04 | 2.345 | PASS |
| tree.xml | 2919.67 | 1253.41 | 1828.42 | rapidxml 1828.42 | 1.597 | PASS |
| character.xml | 3631.57 | 1092.17 | 2035.39 | rapidxml 2035.39 | 1.784 | PASS |
| transitions.xml | 3484.99 | 1242.86 | 2144.24 | rapidxml 2144.24 | 1.625 | PASS |
| xgconsole.xml | 5409.40 | 1871.76 | 2313.24 | rapidxml 2313.24 | 2.338 | PASS |
| weekly_utf8.xml | 4193.75 | 2051.42 | 2381.51 | rapidxml 2381.51 | 1.761 | PASS |
| pugixml_large.xml | 3210.80 | 426.96 | 313.76 | pugixml 426.96 | 7.520 | PASS |
| synthetic_flat_attrs.xml | 5643.61 | 486.24 | 373.81 | pugixml 486.24 | 11.607 | PASS |
| synthetic_deep_tree.xml | 2078.30 | 1242.41 | 777.01 | pugixml 1242.41 | 1.673 | PASS |
| synthetic_entities.xml | 4468.79 | 907.44 | 870.97 | pugixml 907.44 | 4.925 | PASS |
| synthetic_cdata_mix.xml | 2717.29 | 677.45 | 513.87 | pugixml 677.45 | 4.011 | PASS |
| synthetic_wide_siblings.xml | 2739.32 | 442.36 | 341.92 | pugixml 442.36 | 6.193 | PASS |
| synthetic_namespace_mix.xml | 3890.10 | 649.88 | 573.16 | pugixml 649.88 | 5.986 | PASS |
| synthetic_long_names.xml | 5679.88 | 1271.73 | 1545.93 | rapidxml 1545.93 | 3.674 | PASS |
| synthetic_self_closing_swarm.xml | 3253.94 | 516.23 | 404.11 | pugixml 516.23 | 6.303 | PASS |
| synthetic_mixed_content.xml | 1938.63 | 301.20 | 258.64 | pugixml 301.20 | 6.436 | PASS |
| synthetic_small_records.xml | 2964.85 | 347.92 | 292.87 | pugixml 347.92 | 8.522 | PASS |
| synthetic_tiny_empty.xml | 1991.25 | 197.62 | 120.05 | pugixml 197.62 | 10.076 | PASS |
| synthetic_tiny_text.xml | 1330.79 | 133.14 | 105.95 | pugixml 133.14 | 9.995 | PASS |
| synthetic_one_attr.xml | 1971.52 | 173.23 | 144.26 | pugixml 173.23 | 11.381 | PASS |
| synthetic_two_attr.xml | 2473.70 | 246.92 | 117.25 | pugixml 246.92 | 10.018 | PASS |
| synthetic_attrs4.xml | 3048.38 | 225.65 | 182.75 | pugixml 225.65 | 13.510 | PASS |
| synthetic_attrs8.xml | 1906.76 | 156.49 | 135.58 | pugixml 156.49 | 12.184 | PASS |
| synthetic_single_quotes.xml | 2231.88 | 224.86 | 180.25 | pugixml 224.86 | 9.926 | PASS |
| synthetic_unicode_names.xml | 1577.46 | 258.03 | 232.70 | pugixml 258.03 | 6.114 | PASS |
| synthetic_pretty_indented.xml | 1255.82 | 211.66 | 192.93 | pugixml 211.66 | 5.933 | PASS |
| synthetic_crlf_pretty.xml | 1071.17 | 228.09 | 194.51 | pugixml 228.09 | 4.696 | PASS |
| synthetic_token_whitespace_mix.xml | 1823.80 | 204.52 | 179.51 | pugixml 204.52 | 8.917 | PASS |
| synthetic_attr_count_mix.xml | 2963.30 | 170.13 | 155.03 | pugixml 170.13 | 17.418 | PASS |

## Streaming Comparison (Advisory)

| Fixture | stream-turbo | ours-turbo | stream/ours | stream-strict | ours-strict | stream/ours |
|---|---:|---:|---:|---:|---:|---:|
| note.xml | 1311.73 | 1686.11 | 0.778 | 555.53 | 1243.73 | 0.447 |
| sitemaps.xml | 1466.80 | 1838.85 | 0.798 | 703.19 | 1200.96 | 0.586 |
| plant_catalog.xml | 1294.66 | 1470.19 | 0.881 | 693.02 | 1102.87 | 0.628 |
| cd_catalog.xml | 2049.67 | 2437.88 | 0.841 | 994.94 | 1291.05 | 0.771 |
| hnrss.xml | 5960.54 | 6289.14 | 0.948 | 1870.51 | 5674.19 | 0.330 |
| xkcd_rss.xml | 5433.81 | 4240.64 | 1.281 | 2541.37 | 3561.08 | 0.714 |
| bbc_world.xml | 2140.71 | 2938.79 | 0.728 | 1906.21 | 2219.58 | 0.859 |
| arxiv_cs.xml | 8118.85 | 8732.06 | 0.930 | 2801.15 | 7170.69 | 0.391 |
| ecb_usd.xml | 4155.32 | 6121.18 | 0.679 | 2588.37 | 4007.11 | 0.646 |
| tree.xml | 2546.84 | 2919.67 | 0.872 | 1285.06 | 2356.14 | 0.545 |
| character.xml | 2630.01 | 3631.57 | 0.724 | 1172.10 | 2775.16 | 0.422 |
| xgconsole.xml | 3001.26 | 5409.40 | 0.555 | 1166.76 | 4262.09 | 0.274 |
| weekly_utf8.xml | 3067.86 | 4193.75 | 0.732 | 551.90 | 3021.09 | 0.183 |
| pugixml_large.xml | 2476.28 | 3210.80 | 0.771 | 1617.14 | 1752.98 | 0.923 |
| synthetic_flat_attrs.xml | 2606.42 | 5643.61 | 0.462 | 993.77 | 4926.59 | 0.202 |
| synthetic_deep_tree.xml | 1757.40 | 2078.30 | 0.846 | 927.95 | 1436.70 | 0.646 |
| synthetic_entities.xml | 4648.55 | 4468.79 | 1.040 | 781.11 | 4494.52 | 0.174 |
| synthetic_cdata_mix.xml | 2199.95 | 2717.29 | 0.810 | 1538.11 | 2550.98 | 0.603 |
| synthetic_wide_siblings.xml | 2062.52 | 2739.32 | 0.753 | 983.16 | 2103.69 | 0.467 |
| synthetic_namespace_mix.xml | 3037.16 | 3890.10 | 0.781 | 1460.91 | 3193.36 | 0.457 |
| synthetic_long_names.xml | 3631.39 | 5679.88 | 0.639 | 2399.59 | 5577.67 | 0.430 |
| synthetic_self_closing_swarm.xml | 3001.55 | 3253.94 | 0.922 | 1207.28 | 2831.61 | 0.426 |
| synthetic_mixed_content.xml | 2064.47 | 1938.63 | 1.065 | 1040.67 | 1627.00 | 0.640 |
| synthetic_small_records.xml | 1894.94 | 2964.85 | 0.639 | 1000.36 | 2101.89 | 0.476 |
| synthetic_tiny_empty.xml | 1550.31 | 1991.25 | 0.779 | 1178.29 | 1667.15 | 0.707 |
| synthetic_tiny_text.xml | 1128.06 | 1330.79 | 0.848 | 531.98 | 1144.24 | 0.465 |
| synthetic_one_attr.xml | 1614.90 | 1971.52 | 0.819 | 814.04 | 1925.48 | 0.423 |
| synthetic_two_attr.xml | 1413.15 | 2473.70 | 0.571 | 799.80 | 1317.61 | 0.607 |
| synthetic_attrs4.xml | 1773.62 | 3048.38 | 0.582 | 674.62 | 2861.94 | 0.236 |
| synthetic_attrs8.xml | 1076.50 | 1906.76 | 0.565 | 448.43 | 1868.62 | 0.240 |
| synthetic_single_quotes.xml | 1295.20 | 2231.88 | 0.580 | 491.94 | 1636.32 | 0.301 |
| synthetic_unicode_names.xml | 1244.94 | 1577.46 | 0.789 | 204.92 | 1250.93 | 0.164 |
| synthetic_pretty_indented.xml | 951.78 | 1255.82 | 0.758 | 518.18 | 946.82 | 0.547 |
| synthetic_crlf_pretty.xml | 1218.60 | 1071.17 | 1.138 | 558.77 | 1096.45 | 0.510 |
| synthetic_token_whitespace_mix.xml | 787.23 | 1823.80 | 0.432 | 488.62 | 1494.35 | 0.327 |
| synthetic_attr_count_mix.xml | 1227.28 | 2963.30 | 0.414 | 461.32 | 2715.20 | 0.170 |

## Strict Pathology Regression Checks

2/2 passed. These fixtures are excluded from headline averages and stable external gates.
Detailed timings remain in `bench/results/latest.json` for regression analysis.
