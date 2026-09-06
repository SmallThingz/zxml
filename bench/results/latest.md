# ZXML Benchmark Results

Generated (unix): 1788707899

Profile: `stable`

Collection: independently guarded fixture windows on CPU6, not one continuous quiet interval. Every retained fixture passed its complete calibration/sample guard.

## Benchmark Environment

| Property | Value |
|---|---|
| OS / kernel | Linux 7.2.2-zen1-1-zen |
| Architecture | x86_64 |
| CPU | 12th Gen Intel(R) Core(TM) i5-12450H |
| CPU frequency scaling | 16% |
| CPU MHz range | 400.0000–4400.0000 |
| Zig | 0.16.0 (`ReleaseFast -Dcpu=native`) |
| C++ driver | c++ (`-O3 -DNDEBUG -march=native`) |

## Parse Throughput

| Fixture | Parser | Throughput (MB/s) | Median Time (ms) | Iterations |
|---|---|---:|---:|---:|
| note.xml | ours-validated | 1556.45 | 20.15 | 191229 |
| note.xml | ours-permissive | 2470.20 | 38.76 | 583772 |
| note.xml | stream-validated | 1360.44 | 34.88 | 289352 |
| note.xml | stream-permissive | 3153.76 | 34.32 | 660030 |
| note.xml | pugixml | 982.67 | 32.86 | 196883 |
| note.xml | rapidxml | 1766.43 | 33.32 | 358874 |
| sitemaps.xml | ours-validated | 2013.66 | 38.59 | 9013 |
| sitemaps.xml | ours-permissive | 3664.46 | 37.97 | 16136 |
| sitemaps.xml | stream-validated | 1762.69 | 39.09 | 7991 |
| sitemaps.xml | stream-permissive | 3455.77 | 39.21 | 15717 |
| sitemaps.xml | pugixml | 2062.04 | 39.07 | 9343 |
| sitemaps.xml | rapidxml | 2126.97 | 39.36 | 9709 |
| plant_catalog.xml | ours-validated | 1783.13 | 40.50 | 9344 |
| plant_catalog.xml | ours-permissive | 3028.51 | 39.94 | 15650 |
| plant_catalog.xml | stream-validated | 1549.65 | 39.28 | 7875 |
| plant_catalog.xml | stream-permissive | 2817.52 | 40.10 | 14619 |
| plant_catalog.xml | pugixml | 1585.27 | 37.45 | 7681 |
| plant_catalog.xml | rapidxml | 1768.17 | 38.73 | 8860 |
| cd_catalog.xml | ours-validated | 1689.79 | 40.67 | 14123 |
| cd_catalog.xml | ours-permissive | 2741.85 | 37.63 | 21201 |
| cd_catalog.xml | stream-validated | 1422.24 | 39.03 | 11409 |
| cd_catalog.xml | stream-permissive | 2506.49 | 39.74 | 20469 |
| cd_catalog.xml | pugixml | 1526.03 | 37.12 | 11641 |
| cd_catalog.xml | rapidxml | 1669.29 | 38.30 | 13140 |
| hnrss.xml | ours-validated | 5083.19 | 37.23 | 10240 |
| hnrss.xml | ours-permissive | 8379.89 | 36.72 | 16648 |
| hnrss.xml | stream-validated | 4330.62 | 39.08 | 9158 |
| hnrss.xml | stream-permissive | 8117.47 | 39.84 | 17501 |
| hnrss.xml | pugixml | 3063.40 | 38.99 | 6463 |
| hnrss.xml | rapidxml | 2765.72 | 38.48 | 5759 |
| xkcd_rss.xml | ours-validated | 4141.70 | 35.75 | 60074 |
| xkcd_rss.xml | ours-permissive | 7699.98 | 40.10 | 125262 |
| xkcd_rss.xml | stream-validated | 3366.42 | 39.12 | 53420 |
| xkcd_rss.xml | stream-permissive | 7918.53 | 38.75 | 124468 |
| xkcd_rss.xml | pugixml | 2612.82 | 37.52 | 39765 |
| xkcd_rss.xml | rapidxml | 2719.91 | 38.55 | 42536 |
| bbc_world.xml | ours-validated | 3305.64 | 38.07 | 5436 |
| bbc_world.xml | ours-permissive | 5588.52 | 38.01 | 9176 |
| bbc_world.xml | stream-validated | 3227.11 | 15.40 | 2146 |
| bbc_world.xml | stream-permissive | 4993.09 | 19.36 | 4175 |
| bbc_world.xml | pugixml | 2701.27 | 18.55 | 2164 |
| bbc_world.xml | rapidxml | 2616.43 | 37.22 | 4207 |
| arxiv_cs.xml | ours-validated | 4167.94 | 40.49 | 78 |
| arxiv_cs.xml | ours-permissive | 7741.99 | 50.30 | 180 |
| arxiv_cs.xml | stream-validated | 4597.24 | 40.00 | 85 |
| arxiv_cs.xml | stream-permissive | 10095.32 | 38.58 | 180 |
| arxiv_cs.xml | pugixml | 2819.77 | 41.43 | 54 |
| arxiv_cs.xml | rapidxml | 1997.28 | 40.08 | 37 |
| ecb_usd.xml | ours-validated | 3109.24 | 38.48 | 16387 |
| ecb_usd.xml | ours-permissive | 5918.46 | 38.59 | 31275 |
| ecb_usd.xml | stream-validated | 2835.14 | 38.86 | 15089 |
| ecb_usd.xml | stream-permissive | 4987.27 | 39.96 | 27293 |
| ecb_usd.xml | pugixml | 2780.86 | 37.42 | 14251 |
| ecb_usd.xml | rapidxml | 2821.72 | 37.46 | 14474 |
| tree.xml | ours-validated | 1485.63 | 32.84 | 198303 |
| tree.xml | ours-permissive | 2690.63 | 36.16 | 395469 |
| tree.xml | stream-validated | 1418.38 | 36.14 | 208397 |
| tree.xml | stream-permissive | 2746.60 | 31.43 | 350865 |
| tree.xml | pugixml | 1294.47 | 24.71 | 130052 |
| tree.xml | rapidxml | 2102.76 | 34.98 | 299019 |
| character.xml | ours-validated | 1423.06 | 37.52 | 294986 |
| character.xml | ours-permissive | 2981.11 | 34.90 | 574840 |
| character.xml | stream-validated | 1529.35 | 34.83 | 294276 |
| character.xml | stream-permissive | 2569.70 | 37.61 | 533964 |
| character.xml | pugixml | 1177.65 | 31.02 | 201797 |
| character.xml | rapidxml | 2127.43 | 38.26 | 449652 |
| transitions.xml | ours-permissive | 3235.15 | 37.61 | 582144 |
| transitions.xml | stream-permissive | 2476.73 | 37.64 | 446008 |
| transitions.xml | pugixml | 1492.72 | 34.04 | 243105 |
| transitions.xml | rapidxml | 2267.66 | 34.82 | 377770 |
| xgconsole.xml | ours-validated | 1898.90 | 33.94 | 89253 |
| xgconsole.xml | ours-permissive | 5452.27 | 37.13 | 280419 |
| xgconsole.xml | stream-validated | 1327.20 | 39.29 | 72225 |
| xgconsole.xml | stream-permissive | 3673.39 | 37.63 | 191440 |
| xgconsole.xml | pugixml | 1901.26 | 37.34 | 98338 |
| xgconsole.xml | rapidxml | 2490.00 | 39.70 | 136919 |
| weekly_utf8.xml | ours-validated | 793.82 | 38.07 | 11531 |
| weekly_utf8.xml | ours-permissive | 3653.82 | 33.80 | 47122 |
| weekly_utf8.xml | stream-validated | 681.17 | 37.99 | 9872 |
| weekly_utf8.xml | stream-permissive | 3026.56 | 37.34 | 43121 |
| weekly_utf8.xml | pugixml | 2212.47 | 37.23 | 31426 |
| weekly_utf8.xml | rapidxml | 2405.81 | 37.14 | 34087 |
| pugixml_large.xml | ours-validated | 999.69 | 40.62 | 580 |
| pugixml_large.xml | ours-permissive | 1268.51 | 41.01 | 743 |
| pugixml_large.xml | stream-validated | 1691.46 | 39.94 | 965 |
| pugixml_large.xml | stream-permissive | 2133.40 | 40.00 | 1219 |
| pugixml_large.xml | pugixml | 486.34 | 40.74 | 283 |
| pugixml_large.xml | rapidxml | 308.95 | 38.75 | 171 |
| synthetic_flat_attrs.xml | ours-validated | 936.66 | 67.83 | 280 |
| synthetic_flat_attrs.xml | ours-permissive | 6164.92 | 39.46 | 1072 |
| synthetic_flat_attrs.xml | stream-validated | 1004.83 | 63.23 | 280 |
| synthetic_flat_attrs.xml | stream-permissive | 2759.63 | 23.02 | 280 |
| synthetic_flat_attrs.xml | pugixml | 480.03 | 40.18 | 85 |
| synthetic_flat_attrs.xml | rapidxml | 380.55 | 39.95 | 67 |
| synthetic_deep_tree.xml | ours-validated | 1001.70 | 39.58 | 21859 |
| synthetic_deep_tree.xml | ours-permissive | 1416.82 | 40.68 | 31773 |
| synthetic_deep_tree.xml | stream-validated | 1045.37 | 38.93 | 22432 |
| synthetic_deep_tree.xml | stream-permissive | 1565.35 | 39.40 | 33995 |
| synthetic_deep_tree.xml | pugixml | 1323.12 | 40.14 | 29275 |
| synthetic_deep_tree.xml | rapidxml | 793.11 | 39.44 | 17245 |
| synthetic_entities.xml | ours-validated | 860.75 | 40.46 | 53 |
| synthetic_entities.xml | ours-permissive | 3832.17 | 41.15 | 240 |
| synthetic_entities.xml | stream-validated | 855.09 | 40.72 | 53 |
| synthetic_entities.xml | stream-permissive | 5755.89 | 27.40 | 240 |
| synthetic_entities.xml | pugixml | 928.03 | 40.35 | 57 |
| synthetic_entities.xml | rapidxml | 941.28 | 39.79 | 57 |
| synthetic_cdata_mix.xml | ours-validated | 1617.19 | 39.14 | 512 |
| synthetic_cdata_mix.xml | ours-permissive | 2125.97 | 40.41 | 695 |
| synthetic_cdata_mix.xml | stream-validated | 1771.31 | 39.71 | 569 |
| synthetic_cdata_mix.xml | stream-permissive | 2912.63 | 40.83 | 962 |
| synthetic_cdata_mix.xml | pugixml | 696.03 | 42.63 | 240 |
| synthetic_cdata_mix.xml | rapidxml | 533.70 | 55.59 | 240 |
| synthetic_wide_siblings.xml | ours-validated | 967.72 | 40.75 | 109 |
| synthetic_wide_siblings.xml | ours-permissive | 1210.55 | 77.71 | 260 |
| synthetic_wide_siblings.xml | stream-validated | 1060.51 | 40.26 | 118 |
| synthetic_wide_siblings.xml | stream-permissive | 2388.65 | 39.38 | 260 |
| synthetic_wide_siblings.xml | pugixml | 444.53 | 40.69 | 50 |
| synthetic_wide_siblings.xml | rapidxml | 330.91 | 40.45 | 37 |
| synthetic_namespace_mix.xml | ours-validated | 1438.08 | 40.74 | 99 |
| synthetic_namespace_mix.xml | ours-permissive | 3146.00 | 41.38 | 220 |
| synthetic_namespace_mix.xml | stream-validated | 1514.40 | 40.64 | 104 |
| synthetic_namespace_mix.xml | stream-permissive | 3252.67 | 40.02 | 220 |
| synthetic_namespace_mix.xml | pugixml | 705.04 | 41.13 | 49 |
| synthetic_namespace_mix.xml | rapidxml | 584.74 | 40.48 | 40 |
| synthetic_long_names.xml | ours-validated | 3191.96 | 64.84 | 220 |
| synthetic_long_names.xml | ours-permissive | 6069.88 | 34.10 | 220 |
| synthetic_long_names.xml | stream-validated | 2503.04 | 40.21 | 107 |
| synthetic_long_names.xml | stream-permissive | 4662.10 | 44.39 | 220 |
| synthetic_long_names.xml | pugixml | 1392.50 | 40.53 | 60 |
| synthetic_long_names.xml | rapidxml | 1677.29 | 40.38 | 72 |
| synthetic_self_closing_swarm.xml | ours-validated | 1248.57 | 40.28 | 36 |
| synthetic_self_closing_swarm.xml | ours-permissive | 4185.02 | 73.43 | 220 |
| synthetic_self_closing_swarm.xml | stream-validated | 1430.16 | 40.05 | 41 |
| synthetic_self_closing_swarm.xml | stream-permissive | 3245.10 | 39.60 | 92 |
| synthetic_self_closing_swarm.xml | pugixml | 606.12 | 41.48 | 18 |
| synthetic_self_closing_swarm.xml | rapidxml | 493.33 | 39.64 | 14 |
| synthetic_mixed_content.xml | ours-validated | 1262.73 | 39.87 | 80 |
| synthetic_mixed_content.xml | ours-permissive | 1921.63 | 72.05 | 220 |
| synthetic_mixed_content.xml | stream-validated | 1341.22 | 39.89 | 85 |
| synthetic_mixed_content.xml | stream-permissive | 2857.17 | 48.46 | 220 |
| synthetic_mixed_content.xml | pugixml | 550.43 | 40.02 | 35 |
| synthetic_mixed_content.xml | rapidxml | 406.54 | 41.80 | 27 |
| synthetic_small_records.xml | ours-validated | 1278.29 | 40.05 | 43 |
| synthetic_small_records.xml | ours-permissive | 1585.47 | 39.80 | 53 |
| synthetic_small_records.xml | stream-validated | 1300.15 | 40.30 | 44 |
| synthetic_small_records.xml | stream-permissive | 2282.02 | 40.70 | 78 |
| synthetic_small_records.xml | pugixml | 440.37 | 40.56 | 15 |
| synthetic_small_records.xml | rapidxml | 315.73 | 41.48 | 11 |
| synthetic_tiny_empty.xml | ours-validated | 833.43 | 42.24 | 40 |
| synthetic_tiny_empty.xml | ours-permissive | 1143.06 | 40.80 | 53 |
| synthetic_tiny_empty.xml | stream-validated | 1291.63 | 40.20 | 59 |
| synthetic_tiny_empty.xml | stream-permissive | 1564.11 | 40.51 | 72 |
| synthetic_tiny_empty.xml | pugixml | 200.70 | 43.85 | 10 |
| synthetic_tiny_empty.xml | rapidxml | 121.62 | 43.41 | 6 |
| synthetic_tiny_text.xml | ours-validated | 820.34 | 40.96 | 35 |
| synthetic_tiny_text.xml | ours-permissive | 781.34 | 40.55 | 33 |
| synthetic_tiny_text.xml | stream-validated | 696.63 | 41.34 | 30 |
| synthetic_tiny_text.xml | stream-permissive | 1003.50 | 40.18 | 42 |
| synthetic_tiny_text.xml | pugixml | 186.71 | 41.13 | 8 |
| synthetic_tiny_text.xml | rapidxml | 126.87 | 45.40 | 6 |
| synthetic_one_attr.xml | ours-validated | 843.21 | 40.56 | 38 |
| synthetic_one_attr.xml | ours-permissive | 1175.24 | 40.59 | 53 |
| synthetic_one_attr.xml | stream-validated | 1083.55 | 40.70 | 49 |
| synthetic_one_attr.xml | stream-permissive | 1812.53 | 35.75 | 72 |
| synthetic_one_attr.xml | pugixml | 291.95 | 40.08 | 13 |
| synthetic_one_attr.xml | rapidxml | 196.48 | 41.23 | 9 |
| synthetic_two_attr.xml | ours-validated | 894.85 | 39.52 | 34 |
| synthetic_two_attr.xml | ours-permissive | 1836.77 | 40.20 | 71 |
| synthetic_two_attr.xml | stream-validated | 1063.26 | 41.08 | 42 |
| synthetic_two_attr.xml | stream-permissive | 1942.02 | 39.63 | 74 |
| synthetic_two_attr.xml | pugixml | 322.46 | 38.70 | 12 |
| synthetic_two_attr.xml | rapidxml | 225.78 | 41.46 | 9 |
| synthetic_attrs4.xml | ours-validated | 881.09 | 41.06 | 34 |
| synthetic_attrs4.xml | ours-permissive | 3253.39 | 78.49 | 240 |
| synthetic_attrs4.xml | stream-validated | 977.34 | 40.28 | 37 |
| synthetic_attrs4.xml | stream-permissive | 2293.85 | 39.89 | 86 |
| synthetic_attrs4.xml | pugixml | 347.32 | 42.89 | 14 |
| synthetic_attrs4.xml | rapidxml | 258.40 | 41.18 | 10 |
| synthetic_attrs8.xml | ours-validated | 823.89 | 41.09 | 31 |
| synthetic_attrs8.xml | ours-permissive | 5168.37 | 42.26 | 200 |
| synthetic_attrs8.xml | stream-validated | 955.51 | 41.14 | 36 |
| synthetic_attrs8.xml | stream-permissive | 2566.50 | 40.00 | 94 |
| synthetic_attrs8.xml | pugixml | 336.71 | 45.40 | 14 |
| synthetic_attrs8.xml | rapidxml | 264.11 | 45.48 | 11 |
| synthetic_single_quotes.xml | ours-validated | 1157.37 | 33.97 | 39 |
| synthetic_single_quotes.xml | ours-permissive | 3922.03 | 61.68 | 240 |
| synthetic_single_quotes.xml | stream-validated | 1265.69 | 39.82 | 50 |
| synthetic_single_quotes.xml | stream-permissive | 3000.92 | 39.97 | 119 |
| synthetic_single_quotes.xml | pugixml | 539.24 | 41.12 | 22 |
| synthetic_single_quotes.xml | rapidxml | 420.03 | 36.00 | 15 |
| synthetic_unicode_names.xml | ours-validated | 540.25 | 41.05 | 18 |
| synthetic_unicode_names.xml | ours-permissive | 2724.35 | 40.25 | 89 |
| synthetic_unicode_names.xml | stream-validated | 554.06 | 42.25 | 19 |
| synthetic_unicode_names.xml | stream-permissive | 3206.28 | 69.16 | 180 |
| synthetic_unicode_names.xml | pugixml | 644.29 | 42.07 | 22 |
| synthetic_unicode_names.xml | rapidxml | 549.13 | 40.38 | 18 |
| synthetic_pretty_indented.xml | ours-validated | 1148.22 | 40.46 | 49 |
| synthetic_pretty_indented.xml | ours-permissive | 1561.51 | 40.68 | 67 |
| synthetic_pretty_indented.xml | stream-validated | 1277.19 | 39.34 | 53 |
| synthetic_pretty_indented.xml | stream-permissive | 2279.58 | 40.34 | 97 |
| synthetic_pretty_indented.xml | pugixml | 519.60 | 40.14 | 22 |
| synthetic_pretty_indented.xml | rapidxml | 409.87 | 41.63 | 18 |
| synthetic_crlf_pretty.xml | ours-validated | 1122.21 | 39.99 | 55 |
| synthetic_crlf_pretty.xml | ours-permissive | 1679.30 | 39.85 | 82 |
| synthetic_crlf_pretty.xml | stream-validated | 1275.70 | 40.94 | 64 |
| synthetic_crlf_pretty.xml | stream-permissive | 2958.47 | 55.16 | 200 |
| synthetic_crlf_pretty.xml | pugixml | 530.52 | 41.53 | 27 |
| synthetic_crlf_pretty.xml | rapidxml | 441.83 | 40.63 | 22 |
| synthetic_token_whitespace_mix.xml | ours-validated | 891.43 | 41.31 | 44 |
| synthetic_token_whitespace_mix.xml | ours-permissive | 3196.61 | 52.37 | 200 |
| synthetic_token_whitespace_mix.xml | stream-validated | 984.94 | 40.79 | 48 |
| synthetic_token_whitespace_mix.xml | stream-permissive | 1673.21 | 40.52 | 81 |
| synthetic_token_whitespace_mix.xml | pugixml | 457.82 | 40.22 | 22 |
| synthetic_token_whitespace_mix.xml | rapidxml | 372.97 | 40.40 | 18 |
| synthetic_attr_count_mix.xml | ours-validated | 971.35 | 39.36 | 9 |
| synthetic_attr_count_mix.xml | ours-permissive | 5635.31 | 41.46 | 55 |
| synthetic_attr_count_mix.xml | stream-validated | 1072.56 | 43.57 | 11 |
| synthetic_attr_count_mix.xml | stream-permissive | 2811.76 | 40.79 | 27 |
| synthetic_attr_count_mix.xml | pugixml | 426.95 | 49.75 | 5 |
| synthetic_attr_count_mix.xml | rapidxml | 336.49 | 50.50 | 4 |

## Stable Gates

| Fixture | ours-permissive | pugixml | rapidxml | best external | ours/best-ext | Result |
|---|---:|---:|---:|---|---:|---|
| note.xml | 2470.20 | 982.67 | 1766.43 | rapidxml 1766.43 | 1.398 | PASS |
| sitemaps.xml | 3664.46 | 2062.04 | 2126.97 | rapidxml 2126.97 | 1.723 | PASS |
| plant_catalog.xml | 3028.51 | 1585.27 | 1768.17 | rapidxml 1768.17 | 1.713 | PASS |
| cd_catalog.xml | 2741.85 | 1526.03 | 1669.29 | rapidxml 1669.29 | 1.643 | PASS |
| hnrss.xml | 8379.89 | 3063.40 | 2765.72 | pugixml 3063.40 | 2.735 | PASS |
| xkcd_rss.xml | 7699.98 | 2612.82 | 2719.91 | rapidxml 2719.91 | 2.831 | PASS |
| bbc_world.xml | 5588.52 | 2701.27 | 2616.43 | pugixml 2701.27 | 2.069 | PASS |
| arxiv_cs.xml | 7741.99 | 2819.77 | 1997.28 | pugixml 2819.77 | 2.746 | PASS |
| ecb_usd.xml | 5918.46 | 2780.86 | 2821.72 | rapidxml 2821.72 | 2.097 | PASS |
| tree.xml | 2690.63 | 1294.47 | 2102.76 | rapidxml 2102.76 | 1.280 | PASS |
| character.xml | 2981.11 | 1177.65 | 2127.43 | rapidxml 2127.43 | 1.401 | PASS |
| transitions.xml | 3235.15 | 1492.72 | 2267.66 | rapidxml 2267.66 | 1.427 | PASS |
| xgconsole.xml | 5452.27 | 1901.26 | 2490.00 | rapidxml 2490.00 | 2.190 | PASS |
| weekly_utf8.xml | 3653.82 | 2212.47 | 2405.81 | rapidxml 2405.81 | 1.519 | PASS |
| pugixml_large.xml | 1268.51 | 486.34 | 308.95 | pugixml 486.34 | 2.608 | PASS |
| synthetic_flat_attrs.xml | 6164.92 | 480.03 | 380.55 | pugixml 480.03 | 12.843 | PASS |
| synthetic_deep_tree.xml | 1416.82 | 1323.12 | 793.11 | pugixml 1323.12 | 1.071 | PASS |
| synthetic_entities.xml | 3832.17 | 928.03 | 941.28 | rapidxml 941.28 | 4.071 | PASS |
| synthetic_cdata_mix.xml | 2125.97 | 696.03 | 533.70 | pugixml 696.03 | 3.054 | PASS |
| synthetic_wide_siblings.xml | 1210.55 | 444.53 | 330.91 | pugixml 444.53 | 2.723 | PASS |
| synthetic_namespace_mix.xml | 3146.00 | 705.04 | 584.74 | pugixml 705.04 | 4.462 | PASS |
| synthetic_long_names.xml | 6069.88 | 1392.50 | 1677.29 | rapidxml 1677.29 | 3.619 | PASS |
| synthetic_self_closing_swarm.xml | 4185.02 | 606.12 | 493.33 | pugixml 606.12 | 6.905 | PASS |
| synthetic_mixed_content.xml | 1921.63 | 550.43 | 406.54 | pugixml 550.43 | 3.491 | PASS |
| synthetic_small_records.xml | 1585.47 | 440.37 | 315.73 | pugixml 440.37 | 3.600 | PASS |
| synthetic_tiny_empty.xml | 1143.06 | 200.70 | 121.62 | pugixml 200.70 | 5.695 | PASS |
| synthetic_tiny_text.xml | 781.34 | 186.71 | 126.87 | pugixml 186.71 | 4.185 | PASS |
| synthetic_one_attr.xml | 1175.24 | 291.95 | 196.48 | pugixml 291.95 | 4.026 | PASS |
| synthetic_two_attr.xml | 1836.77 | 322.46 | 225.78 | pugixml 322.46 | 5.696 | PASS |
| synthetic_attrs4.xml | 3253.39 | 347.32 | 258.40 | pugixml 347.32 | 9.367 | PASS |
| synthetic_attrs8.xml | 5168.37 | 336.71 | 264.11 | pugixml 336.71 | 15.349 | PASS |
| synthetic_single_quotes.xml | 3922.03 | 539.24 | 420.03 | pugixml 539.24 | 7.273 | PASS |
| synthetic_unicode_names.xml | 2724.35 | 644.29 | 549.13 | pugixml 644.29 | 4.228 | PASS |
| synthetic_pretty_indented.xml | 1561.51 | 519.60 | 409.87 | pugixml 519.60 | 3.005 | PASS |
| synthetic_crlf_pretty.xml | 1679.30 | 530.52 | 441.83 | pugixml 530.52 | 3.165 | PASS |
| synthetic_token_whitespace_mix.xml | 3196.61 | 457.82 | 372.97 | pugixml 457.82 | 6.982 | PASS |
| synthetic_attr_count_mix.xml | 5635.31 | 426.95 | 336.49 | pugixml 426.95 | 13.199 | PASS |

## Streaming Comparison (Advisory)

| Fixture | stream-permissive | ours-permissive | stream/ours | stream-validated | ours-validated | stream/ours |
|---|---:|---:|---:|---:|---:|---:|
| note.xml | 3153.76 | 2470.20 | 1.277 | 1360.44 | 1556.45 | 0.874 |
| sitemaps.xml | 3455.77 | 3664.46 | 0.943 | 1762.69 | 2013.66 | 0.875 |
| plant_catalog.xml | 2817.52 | 3028.51 | 0.930 | 1549.65 | 1783.13 | 0.869 |
| cd_catalog.xml | 2506.49 | 2741.85 | 0.914 | 1422.24 | 1689.79 | 0.842 |
| hnrss.xml | 8117.47 | 8379.89 | 0.969 | 4330.62 | 5083.19 | 0.852 |
| xkcd_rss.xml | 7918.53 | 7699.98 | 1.028 | 3366.42 | 4141.70 | 0.813 |
| bbc_world.xml | 4993.09 | 5588.52 | 0.893 | 3227.11 | 3305.64 | 0.976 |
| arxiv_cs.xml | 10095.32 | 7741.99 | 1.304 | 4597.24 | 4167.94 | 1.103 |
| ecb_usd.xml | 4987.27 | 5918.46 | 0.843 | 2835.14 | 3109.24 | 0.912 |
| tree.xml | 2746.60 | 2690.63 | 1.021 | 1418.38 | 1485.63 | 0.955 |
| character.xml | 2569.70 | 2981.11 | 0.862 | 1529.35 | 1423.06 | 1.075 |
| xgconsole.xml | 3673.39 | 5452.27 | 0.674 | 1327.20 | 1898.90 | 0.699 |
| weekly_utf8.xml | 3026.56 | 3653.82 | 0.828 | 681.17 | 793.82 | 0.858 |
| pugixml_large.xml | 2133.40 | 1268.51 | 1.682 | 1691.46 | 999.69 | 1.692 |
| synthetic_flat_attrs.xml | 2759.63 | 6164.92 | 0.448 | 1004.83 | 936.66 | 1.073 |
| synthetic_deep_tree.xml | 1565.35 | 1416.82 | 1.105 | 1045.37 | 1001.70 | 1.044 |
| synthetic_entities.xml | 5755.89 | 3832.17 | 1.502 | 855.09 | 860.75 | 0.993 |
| synthetic_cdata_mix.xml | 2912.63 | 2125.97 | 1.370 | 1771.31 | 1617.19 | 1.095 |
| synthetic_wide_siblings.xml | 2388.65 | 1210.55 | 1.973 | 1060.51 | 967.72 | 1.096 |
| synthetic_namespace_mix.xml | 3252.67 | 3146.00 | 1.034 | 1514.40 | 1438.08 | 1.053 |
| synthetic_long_names.xml | 4662.10 | 6069.88 | 0.768 | 2503.04 | 3191.96 | 0.784 |
| synthetic_self_closing_swarm.xml | 3245.10 | 4185.02 | 0.775 | 1430.16 | 1248.57 | 1.145 |
| synthetic_mixed_content.xml | 2857.17 | 1921.63 | 1.487 | 1341.22 | 1262.73 | 1.062 |
| synthetic_small_records.xml | 2282.02 | 1585.47 | 1.439 | 1300.15 | 1278.29 | 1.017 |
| synthetic_tiny_empty.xml | 1564.11 | 1143.06 | 1.368 | 1291.63 | 833.43 | 1.550 |
| synthetic_tiny_text.xml | 1003.50 | 781.34 | 1.284 | 696.63 | 820.34 | 0.849 |
| synthetic_one_attr.xml | 1812.53 | 1175.24 | 1.542 | 1083.55 | 843.21 | 1.285 |
| synthetic_two_attr.xml | 1942.02 | 1836.77 | 1.057 | 1063.26 | 894.85 | 1.188 |
| synthetic_attrs4.xml | 2293.85 | 3253.39 | 0.705 | 977.34 | 881.09 | 1.109 |
| synthetic_attrs8.xml | 2566.50 | 5168.37 | 0.497 | 955.51 | 823.89 | 1.160 |
| synthetic_single_quotes.xml | 3000.92 | 3922.03 | 0.765 | 1265.69 | 1157.37 | 1.094 |
| synthetic_unicode_names.xml | 3206.28 | 2724.35 | 1.177 | 554.06 | 540.25 | 1.026 |
| synthetic_pretty_indented.xml | 2279.58 | 1561.51 | 1.460 | 1277.19 | 1148.22 | 1.112 |
| synthetic_crlf_pretty.xml | 2958.47 | 1679.30 | 1.762 | 1275.70 | 1122.21 | 1.137 |
| synthetic_token_whitespace_mix.xml | 1673.21 | 3196.61 | 0.523 | 984.94 | 891.43 | 1.105 |
| synthetic_attr_count_mix.xml | 2811.76 | 5635.31 | 0.499 | 1072.56 | 971.35 | 1.104 |

## Validated Pathology Regression Checks

2/2 passed. These fixtures are excluded from headline averages and stable external gates.
Detailed timings remain in `bench/results/latest.json` for regression analysis.
