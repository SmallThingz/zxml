# ZXML Benchmark Results

Generated (unix): 1788492990

Profile: `stable`

## Benchmark Environment

| Property | Value |
|---|---|
| OS / kernel | Linux 7.2.2-zen1-1-zen |
| Architecture | x86_64 |
| CPU | 12th Gen Intel(R) Core(TM) i5-12450H |
| CPU frequency scaling | 50% |
| CPU MHz range | 400.0000–4400.0000 |
| Zig | 0.16.0 (`ReleaseFast -Dcpu=native`) |
| C++ driver | zig c++ (`-O3 -DNDEBUG -march=native`) |

## Parse Throughput

| Fixture | Parser | Throughput (MB/s) | Median Time (ms) | Iterations |
|---|---|---:|---:|---:|
| note.xml | ours-strict | 1463.64 | 16.65 | 148617 |
| note.xml | ours-turbo | 2976.49 | 15.29 | 277451 |
| note.xml | stream-strict | 1339.16 | 20.01 | 163410 |
| note.xml | stream-turbo | 2946.79 | 36.57 | 657103 |
| note.xml | pugixml | 922.59 | 22.67 | 127533 |
| note.xml | rapidxml | 1418.02 | 25.07 | 216807 |
| sitemaps.xml | ours-strict | 1864.88 | 35.09 | 7590 |
| sitemaps.xml | ours-turbo | 3683.65 | 20.95 | 8949 |
| sitemaps.xml | stream-strict | 1700.21 | 33.15 | 6537 |
| sitemaps.xml | stream-turbo | 3699.31 | 21.37 | 9170 |
| sitemaps.xml | pugixml | 2054.27 | 21.58 | 5142 |
| sitemaps.xml | rapidxml | 1779.22 | 21.77 | 4492 |
| plant_catalog.xml | ours-strict | 1400.10 | 25.50 | 4620 |
| plant_catalog.xml | ours-turbo | 3038.54 | 22.26 | 8750 |
| plant_catalog.xml | stream-strict | 1443.57 | 19.40 | 3624 |
| plant_catalog.xml | stream-turbo | 2619.85 | 24.28 | 8230 |
| plant_catalog.xml | pugixml | 1309.14 | 27.39 | 4639 |
| plant_catalog.xml | rapidxml | 1374.32 | 26.03 | 4629 |
| cd_catalog.xml | ours-strict | 1389.74 | 23.32 | 6660 |
| cd_catalog.xml | ours-turbo | 2805.45 | 22.56 | 13005 |
| cd_catalog.xml | stream-strict | 1277.05 | 19.75 | 5184 |
| cd_catalog.xml | stream-turbo | 2549.84 | 25.26 | 13239 |
| cd_catalog.xml | pugixml | 1477.88 | 23.63 | 7176 |
| cd_catalog.xml | rapidxml | 1427.99 | 23.16 | 6797 |
| hnrss.xml | ours-strict | 3752.66 | 26.40 | 5361 |
| hnrss.xml | ours-turbo | 8011.36 | 17.95 | 7780 |
| hnrss.xml | stream-strict | 4109.22 | 40.66 | 9041 |
| hnrss.xml | stream-turbo | 8096.25 | 21.17 | 9273 |
| hnrss.xml | pugixml | 2676.20 | 22.10 | 3200 |
| hnrss.xml | rapidxml | 2473.02 | 40.56 | 5427 |
| xkcd_rss.xml | ours-strict | 4034.20 | 20.14 | 32957 |
| xkcd_rss.xml | ours-turbo | 8394.76 | 19.05 | 64866 |
| xkcd_rss.xml | stream-strict | 3317.30 | 21.67 | 29169 |
| xkcd_rss.xml | stream-turbo | 8422.88 | 21.45 | 73311 |
| xkcd_rss.xml | pugixml | 2464.46 | 26.13 | 26125 |
| xkcd_rss.xml | rapidxml | 2057.80 | 38.90 | 32475 |
| bbc_world.xml | ours-strict | 3070.13 | 21.28 | 2822 |
| bbc_world.xml | ours-turbo | 4938.07 | 19.14 | 4083 |
| bbc_world.xml | stream-strict | 2948.31 | 36.29 | 4622 |
| bbc_world.xml | stream-turbo | 5422.98 | 19.90 | 4662 |
| bbc_world.xml | pugixml | 2693.20 | 23.65 | 2751 |
| bbc_world.xml | rapidxml | 2228.70 | 36.27 | 3492 |
| arxiv_cs.xml | ours-strict | 4111.78 | 43.15 | 82 |
| arxiv_cs.xml | ours-turbo | 9727.18 | 40.04 | 180 |
| arxiv_cs.xml | stream-strict | 4018.66 | 43.07 | 80 |
| arxiv_cs.xml | stream-turbo | 9682.07 | 40.22 | 180 |
| arxiv_cs.xml | pugixml | 2312.68 | 47.71 | 51 |
| arxiv_cs.xml | rapidxml | 1653.52 | 45.80 | 35 |
| ecb_usd.xml | ours-strict | 2993.33 | 18.44 | 7558 |
| ecb_usd.xml | ours-turbo | 5016.33 | 38.40 | 26382 |
| ecb_usd.xml | stream-strict | 2752.48 | 34.18 | 12884 |
| ecb_usd.xml | stream-turbo | 4699.35 | 22.59 | 14536 |
| ecb_usd.xml | pugixml | 2616.72 | 33.25 | 11915 |
| ecb_usd.xml | rapidxml | 2111.76 | 39.67 | 11473 |
| tree.xml | ours-strict | 1209.70 | 16.89 | 83051 |
| tree.xml | ours-turbo | 2326.47 | 17.34 | 163985 |
| tree.xml | stream-strict | 1317.84 | 35.51 | 190254 |
| tree.xml | stream-turbo | 2892.09 | 18.90 | 222182 |
| tree.xml | pugixml | 1136.33 | 23.10 | 106719 |
| tree.xml | rapidxml | 1564.97 | 25.39 | 161500 |
| character.xml | ours-strict | 1321.06 | 16.46 | 120172 |
| character.xml | ours-turbo | 2605.15 | 14.59 | 209978 |
| character.xml | stream-strict | 1311.06 | 39.76 | 288033 |
| character.xml | stream-turbo | 2558.39 | 18.75 | 264982 |
| character.xml | pugixml | 1120.71 | 36.83 | 228041 |
| character.xml | rapidxml | 1700.49 | 24.23 | 227661 |
| transitions.xml | ours-turbo | 2151.95 | 17.99 | 185268 |
| transitions.xml | stream-turbo | 2819.54 | 19.48 | 262746 |
| transitions.xml | pugixml | 1471.84 | 21.13 | 148806 |
| transitions.xml | rapidxml | 1833.42 | 22.99 | 201668 |
| xgconsole.xml | ours-strict | 1649.65 | 18.77 | 42883 |
| xgconsole.xml | ours-turbo | 3035.83 | 18.77 | 78907 |
| xgconsole.xml | stream-strict | 1281.15 | 19.86 | 35232 |
| xgconsole.xml | stream-turbo | 3741.27 | 18.81 | 97491 |
| xgconsole.xml | pugixml | 1723.78 | 25.03 | 59749 |
| xgconsole.xml | rapidxml | 2011.21 | 25.02 | 69707 |
| weekly_utf8.xml | ours-strict | 522.71 | 20.11 | 4010 |
| weekly_utf8.xml | ours-turbo | 3078.29 | 22.62 | 26572 |
| weekly_utf8.xml | stream-strict | 570.60 | 17.40 | 3789 |
| weekly_utf8.xml | stream-turbo | 3635.69 | 20.19 | 28010 |
| weekly_utf8.xml | pugixml | 2129.02 | 23.18 | 18829 |
| weekly_utf8.xml | rapidxml | 2210.43 | 32.63 | 27515 |
| pugixml_large.xml | ours-strict | 1666.46 | 21.01 | 500 |
| pugixml_large.xml | ours-turbo | 2308.05 | 15.44 | 509 |
| pugixml_large.xml | stream-strict | 1695.42 | 38.20 | 925 |
| pugixml_large.xml | stream-turbo | 2453.68 | 21.89 | 767 |
| pugixml_large.xml | pugixml | 489.89 | 32.44 | 227 |
| pugixml_large.xml | rapidxml | 314.74 | 28.70 | 129 |
| synthetic_flat_attrs.xml | ours-strict | 889.50 | 71.42 | 280 |
| synthetic_flat_attrs.xml | ours-turbo | 1479.37 | 42.95 | 280 |
| synthetic_flat_attrs.xml | stream-strict | 939.38 | 67.63 | 280 |
| synthetic_flat_attrs.xml | stream-turbo | 2484.98 | 25.57 | 280 |
| synthetic_flat_attrs.xml | pugixml | 426.65 | 43.08 | 81 |
| synthetic_flat_attrs.xml | rapidxml | 377.10 | 40.92 | 68 |
| synthetic_deep_tree.xml | ours-strict | 946.44 | 21.37 | 11150 |
| synthetic_deep_tree.xml | ours-turbo | 1415.72 | 19.70 | 15376 |
| synthetic_deep_tree.xml | stream-strict | 908.02 | 27.92 | 13978 |
| synthetic_deep_tree.xml | stream-turbo | 1767.55 | 21.70 | 21144 |
| synthetic_deep_tree.xml | pugixml | 1283.53 | 36.91 | 26119 |
| synthetic_deep_tree.xml | rapidxml | 531.37 | 34.42 | 10083 |
| synthetic_entities.xml | ours-strict | 985.40 | 40.67 | 61 |
| synthetic_entities.xml | ours-turbo | 4649.04 | 33.92 | 240 |
| synthetic_entities.xml | stream-strict | 922.18 | 41.32 | 58 |
| synthetic_entities.xml | stream-turbo | 5293.71 | 29.79 | 240 |
| synthetic_entities.xml | pugixml | 918.55 | 39.34 | 55 |
| synthetic_entities.xml | rapidxml | 811.71 | 42.09 | 52 |
| synthetic_cdata_mix.xml | ours-strict | 2072.32 | 30.31 | 508 |
| synthetic_cdata_mix.xml | ours-turbo | 2606.41 | 35.86 | 756 |
| synthetic_cdata_mix.xml | stream-strict | 1720.52 | 39.23 | 546 |
| synthetic_cdata_mix.xml | stream-turbo | 2478.22 | 41.90 | 840 |
| synthetic_cdata_mix.xml | pugixml | 633.04 | 46.87 | 240 |
| synthetic_cdata_mix.xml | rapidxml | 521.01 | 56.95 | 240 |
| synthetic_wide_siblings.xml | ours-strict | 1181.64 | 79.61 | 260 |
| synthetic_wide_siblings.xml | ours-turbo | 2014.12 | 46.70 | 260 |
| synthetic_wide_siblings.xml | stream-strict | 1038.19 | 40.42 | 116 |
| synthetic_wide_siblings.xml | stream-turbo | 2207.37 | 42.61 | 260 |
| synthetic_wide_siblings.xml | pugixml | 420.47 | 41.30 | 48 |
| synthetic_wide_siblings.xml | rapidxml | 318.61 | 40.88 | 36 |
| synthetic_namespace_mix.xml | ours-strict | 1449.29 | 41.65 | 102 |
| synthetic_namespace_mix.xml | ours-turbo | 2911.27 | 44.72 | 220 |
| synthetic_namespace_mix.xml | stream-strict | 1412.58 | 41.89 | 100 |
| synthetic_namespace_mix.xml | stream-turbo | 3428.15 | 37.98 | 220 |
| synthetic_namespace_mix.xml | pugixml | 676.03 | 40.26 | 46 |
| synthetic_namespace_mix.xml | rapidxml | 584.55 | 40.49 | 40 |
| synthetic_long_names.xml | ours-strict | 3332.31 | 62.11 | 220 |
| synthetic_long_names.xml | ours-turbo | 4555.74 | 45.43 | 220 |
| synthetic_long_names.xml | stream-strict | 2773.99 | 74.61 | 220 |
| synthetic_long_names.xml | stream-turbo | 3960.44 | 52.26 | 220 |
| synthetic_long_names.xml | pugixml | 1276.09 | 41.28 | 56 |
| synthetic_long_names.xml | rapidxml | 1654.48 | 41.51 | 73 |
| synthetic_self_closing_swarm.xml | ours-strict | 1197.71 | 44.32 | 38 |
| synthetic_self_closing_swarm.xml | ours-turbo | 2589.90 | 40.45 | 75 |
| synthetic_self_closing_swarm.xml | stream-strict | 1268.99 | 41.83 | 38 |
| synthetic_self_closing_swarm.xml | stream-turbo | 3259.90 | 38.14 | 89 |
| synthetic_self_closing_swarm.xml | pugixml | 523.72 | 37.34 | 14 |
| synthetic_self_closing_swarm.xml | rapidxml | 482.21 | 37.66 | 13 |
| synthetic_mixed_content.xml | ours-strict | 1456.22 | 41.92 | 97 |
| synthetic_mixed_content.xml | ours-turbo | 2445.50 | 56.62 | 220 |
| synthetic_mixed_content.xml | stream-strict | 1344.05 | 39.80 | 85 |
| synthetic_mixed_content.xml | stream-turbo | 2782.06 | 49.77 | 220 |
| synthetic_mixed_content.xml | pugixml | 503.14 | 42.53 | 34 |
| synthetic_mixed_content.xml | rapidxml | 380.64 | 42.99 | 26 |
| synthetic_small_records.xml | ours-strict | 1567.24 | 41.03 | 54 |
| synthetic_small_records.xml | ours-turbo | 2177.09 | 44.85 | 82 |
| synthetic_small_records.xml | stream-strict | 1217.49 | 41.08 | 42 |
| synthetic_small_records.xml | stream-turbo | 2148.54 | 45.44 | 82 |
| synthetic_small_records.xml | pugixml | 426.26 | 39.11 | 14 |
| synthetic_small_records.xml | rapidxml | 297.11 | 44.08 | 11 |
| synthetic_tiny_empty.xml | ours-strict | 836.62 | 42.07 | 40 |
| synthetic_tiny_empty.xml | ours-turbo | 1155.70 | 46.45 | 61 |
| synthetic_tiny_empty.xml | stream-strict | 1281.36 | 40.52 | 59 |
| synthetic_tiny_empty.xml | stream-turbo | 1476.90 | 43.50 | 73 |
| synthetic_tiny_empty.xml | pugixml | 195.88 | 44.93 | 10 |
| synthetic_tiny_empty.xml | rapidxml | 119.54 | 44.17 | 6 |
| synthetic_tiny_text.xml | ours-strict | 815.20 | 43.57 | 37 |
| synthetic_tiny_text.xml | ours-turbo | 926.43 | 42.49 | 41 |
| synthetic_tiny_text.xml | stream-strict | 672.53 | 41.40 | 29 |
| synthetic_tiny_text.xml | stream-turbo | 966.85 | 39.72 | 40 |
| synthetic_tiny_text.xml | pugixml | 184.62 | 41.60 | 8 |
| synthetic_tiny_text.xml | rapidxml | 119.53 | 48.19 | 6 |
| synthetic_one_attr.xml | ours-strict | 1000.16 | 42.29 | 47 |
| synthetic_one_attr.xml | ours-turbo | 1338.76 | 37.65 | 56 |
| synthetic_one_attr.xml | stream-strict | 877.97 | 43.05 | 42 |
| synthetic_one_attr.xml | stream-turbo | 1806.50 | 39.86 | 80 |
| synthetic_one_attr.xml | pugixml | 290.18 | 43.42 | 14 |
| synthetic_one_attr.xml | rapidxml | 197.70 | 45.52 | 10 |
| synthetic_two_attr.xml | ours-strict | 941.82 | 43.07 | 39 |
| synthetic_two_attr.xml | ours-turbo | 1474.26 | 40.21 | 57 |
| synthetic_two_attr.xml | stream-strict | 950.47 | 40.49 | 37 |
| synthetic_two_attr.xml | stream-turbo | 1769.43 | 41.14 | 70 |
| synthetic_two_attr.xml | pugixml | 318.19 | 39.22 | 12 |
| synthetic_two_attr.xml | rapidxml | 213.92 | 48.62 | 10 |
| synthetic_attrs4.xml | ours-strict | 896.23 | 41.55 | 35 |
| synthetic_attrs4.xml | ours-turbo | 1497.73 | 42.62 | 60 |
| synthetic_attrs4.xml | stream-strict | 916.08 | 40.65 | 35 |
| synthetic_attrs4.xml | stream-turbo | 2176.22 | 40.09 | 82 |
| synthetic_attrs4.xml | pugixml | 319.14 | 43.34 | 13 |
| synthetic_attrs4.xml | rapidxml | 264.44 | 44.26 | 11 |
| synthetic_attrs8.xml | ours-strict | 900.78 | 40.01 | 33 |
| synthetic_attrs8.xml | ours-turbo | 1636.02 | 40.72 | 61 |
| synthetic_attrs8.xml | stream-strict | 899.99 | 40.04 | 33 |
| synthetic_attrs8.xml | stream-turbo | 2368.59 | 38.73 | 84 |
| synthetic_attrs8.xml | pugixml | 359.87 | 42.48 | 14 |
| synthetic_attrs8.xml | rapidxml | 272.64 | 44.06 | 11 |
| synthetic_attrs16.xml | ours-strict | 904.66 | 45.84 | 36 |
| synthetic_attrs16.xml | ours-turbo | 1757.30 | 41.96 | 64 |
| synthetic_attrs16.xml | stream-strict | 1043.17 | 44.17 | 40 |
| synthetic_attrs16.xml | stream-turbo | 2925.72 | 59.06 | 150 |
| synthetic_attrs16.xml | pugixml | 441.83 | 41.72 | 16 |
| synthetic_attrs16.xml | rapidxml | 375.13 | 39.92 | 13 |
| synthetic_attrs32.xml | ours-strict | 997.69 | 41.88 | 32 |
| synthetic_attrs32.xml | ours-turbo | 1836.42 | 78.20 | 110 |
| synthetic_attrs32.xml | stream-strict | 628.88 | 41.52 | 20 |
| synthetic_attrs32.xml | stream-turbo | 3023.84 | 47.50 | 110 |
| synthetic_attrs32.xml | pugixml | 450.58 | 43.46 | 15 |
| synthetic_attrs32.xml | rapidxml | 399.51 | 42.48 | 13 |
| synthetic_attrs48.xml | ours-strict | 1035.45 | 39.77 | 30 |
| synthetic_attrs48.xml | ours-turbo | 1901.56 | 64.97 | 90 |
| synthetic_attrs48.xml | stream-strict | 691.67 | 37.71 | 19 |
| synthetic_attrs48.xml | stream-turbo | 3118.34 | 39.62 | 90 |
| synthetic_attrs48.xml | pugixml | 472.64 | 43.57 | 15 |
| synthetic_attrs48.xml | rapidxml | 414.51 | 29.81 | 9 |
| synthetic_attrs64.xml | ours-strict | 1110.67 | 41.60 | 33 |
| synthetic_attrs64.xml | ours-turbo | 2022.83 | 48.45 | 70 |
| synthetic_attrs64.xml | stream-strict | 697.61 | 40.14 | 20 |
| synthetic_attrs64.xml | stream-turbo | 3146.95 | 31.14 | 70 |
| synthetic_attrs64.xml | pugixml | 533.20 | 39.39 | 15 |
| synthetic_attrs64.xml | rapidxml | 454.10 | 40.08 | 13 |
| synthetic_attrs96.xml | ours-strict | 1142.19 | 67.38 | 55 |
| synthetic_attrs96.xml | ours-turbo | 2108.82 | 36.49 | 55 |
| synthetic_attrs96.xml | stream-strict | 528.91 | 42.33 | 16 |
| synthetic_attrs96.xml | stream-turbo | 3261.21 | 23.60 | 55 |
| synthetic_attrs96.xml | pugixml | 546.26 | 40.98 | 16 |
| synthetic_attrs96.xml | rapidxml | 468.23 | 38.85 | 13 |
| synthetic_attrs128.xml | ours-strict | 1123.86 | 59.66 | 45 |
| synthetic_attrs128.xml | ours-turbo | 2176.24 | 30.81 | 45 |
| synthetic_attrs128.xml | stream-strict | 558.02 | 40.05 | 15 |
| synthetic_attrs128.xml | stream-turbo | 3283.83 | 20.42 | 45 |
| synthetic_attrs128.xml | pugixml | 556.15 | 40.19 | 15 |
| synthetic_attrs128.xml | rapidxml | 482.82 | 40.12 | 13 |
| synthetic_long_attr_values.xml | ours-strict | 3515.36 | 61.04 | 180 |
| synthetic_long_attr_values.xml | ours-turbo | 5246.61 | 40.90 | 180 |
| synthetic_long_attr_values.xml | stream-strict | 3357.94 | 63.90 | 180 |
| synthetic_long_attr_values.xml | stream-turbo | 5604.79 | 38.28 | 180 |
| synthetic_long_attr_values.xml | pugixml | 1407.37 | 41.50 | 49 |
| synthetic_long_attr_values.xml | rapidxml | 1393.98 | 41.90 | 49 |
| synthetic_single_quotes.xml | ours-strict | 1132.71 | 38.27 | 43 |
| synthetic_single_quotes.xml | ours-turbo | 2000.94 | 42.32 | 84 |
| synthetic_single_quotes.xml | stream-strict | 1072.67 | 44.17 | 47 |
| synthetic_single_quotes.xml | stream-turbo | 2709.92 | 40.92 | 110 |
| synthetic_single_quotes.xml | pugixml | 493.71 | 42.88 | 21 |
| synthetic_single_quotes.xml | rapidxml | 405.23 | 42.29 | 17 |
| synthetic_unicode_names.xml | ours-strict | 450.28 | 38.31 | 14 |
| synthetic_unicode_names.xml | ours-turbo | 2844.57 | 38.11 | 88 |
| synthetic_unicode_names.xml | stream-strict | 436.53 | 42.33 | 15 |
| synthetic_unicode_names.xml | stream-turbo | 3438.47 | 64.49 | 180 |
| synthetic_unicode_names.xml | pugixml | 625.66 | 39.38 | 20 |
| synthetic_unicode_names.xml | rapidxml | 490.49 | 42.70 | 17 |
| synthetic_pretty_indented.xml | ours-strict | 1367.28 | 40.91 | 59 |
| synthetic_pretty_indented.xml | ours-turbo | 2341.92 | 39.27 | 97 |
| synthetic_pretty_indented.xml | stream-strict | 1132.57 | 42.69 | 51 |
| synthetic_pretty_indented.xml | stream-turbo | 2352.76 | 80.59 | 200 |
| synthetic_pretty_indented.xml | pugixml | 492.00 | 42.39 | 22 |
| synthetic_pretty_indented.xml | rapidxml | 386.29 | 44.17 | 18 |
| synthetic_crlf_pretty.xml | ours-strict | 1220.50 | 40.12 | 60 |
| synthetic_crlf_pretty.xml | ours-turbo | 2124.37 | 38.03 | 99 |
| synthetic_crlf_pretty.xml | stream-strict | 1237.14 | 38.92 | 59 |
| synthetic_crlf_pretty.xml | stream-turbo | 2750.07 | 59.34 | 200 |
| synthetic_crlf_pretty.xml | pugixml | 515.37 | 30.08 | 19 |
| synthetic_crlf_pretty.xml | rapidxml | 391.01 | 41.74 | 20 |
| synthetic_token_whitespace_mix.xml | ours-strict | 889.25 | 39.53 | 42 |
| synthetic_token_whitespace_mix.xml | ours-turbo | 1437.48 | 41.34 | 71 |
| synthetic_token_whitespace_mix.xml | stream-strict | 903.83 | 40.75 | 44 |
| synthetic_token_whitespace_mix.xml | stream-turbo | 1523.55 | 40.65 | 74 |
| synthetic_token_whitespace_mix.xml | pugixml | 441.50 | 43.60 | 23 |
| synthetic_token_whitespace_mix.xml | rapidxml | 367.15 | 43.31 | 19 |
| synthetic_attr_count_mix.xml | ours-strict | 940.04 | 40.67 | 9 |
| synthetic_attr_count_mix.xml | ours-turbo | 1790.51 | 40.33 | 17 |
| synthetic_attr_count_mix.xml | stream-strict | 914.74 | 46.44 | 10 |
| synthetic_attr_count_mix.xml | stream-turbo | 2605.58 | 40.76 | 25 |
| synthetic_attr_count_mix.xml | pugixml | 371.13 | 45.78 | 4 |
| synthetic_attr_count_mix.xml | rapidxml | 313.85 | 40.61 | 3 |

## Stable Gates

| Fixture | ours-turbo | pugixml | rapidxml | best external | ours/best-ext | Result |
|---|---:|---:|---:|---|---:|---|
| note.xml | 2976.49 | 922.59 | 1418.02 | rapidxml 1418.02 | 2.099 | PASS |
| sitemaps.xml | 3683.65 | 2054.27 | 1779.22 | pugixml 2054.27 | 1.793 | PASS |
| plant_catalog.xml | 3038.54 | 1309.14 | 1374.32 | rapidxml 1374.32 | 2.211 | PASS |
| cd_catalog.xml | 2805.45 | 1477.88 | 1427.99 | pugixml 1477.88 | 1.898 | PASS |
| hnrss.xml | 8011.36 | 2676.20 | 2473.02 | pugixml 2676.20 | 2.994 | PASS |
| xkcd_rss.xml | 8394.76 | 2464.46 | 2057.80 | pugixml 2464.46 | 3.406 | PASS |
| bbc_world.xml | 4938.07 | 2693.20 | 2228.70 | pugixml 2693.20 | 1.834 | PASS |
| arxiv_cs.xml | 9727.18 | 2312.68 | 1653.52 | pugixml 2312.68 | 4.206 | PASS |
| ecb_usd.xml | 5016.33 | 2616.72 | 2111.76 | pugixml 2616.72 | 1.917 | PASS |
| tree.xml | 2326.47 | 1136.33 | 1564.97 | rapidxml 1564.97 | 1.487 | PASS |
| character.xml | 2605.15 | 1120.71 | 1700.49 | rapidxml 1700.49 | 1.532 | PASS |
| transitions.xml | 2151.95 | 1471.84 | 1833.42 | rapidxml 1833.42 | 1.174 | PASS |
| xgconsole.xml | 3035.83 | 1723.78 | 2011.21 | rapidxml 2011.21 | 1.509 | PASS |
| weekly_utf8.xml | 3078.29 | 2129.02 | 2210.43 | rapidxml 2210.43 | 1.393 | PASS |
| pugixml_large.xml | 2308.05 | 489.89 | 314.74 | pugixml 489.89 | 4.711 | PASS |
| synthetic_flat_attrs.xml | 1479.37 | 426.65 | 377.10 | pugixml 426.65 | 3.467 | PASS |
| synthetic_deep_tree.xml | 1415.72 | 1283.53 | 531.37 | pugixml 1283.53 | 1.103 | PASS |
| synthetic_entities.xml | 4649.04 | 918.55 | 811.71 | pugixml 918.55 | 5.061 | PASS |
| synthetic_cdata_mix.xml | 2606.41 | 633.04 | 521.01 | pugixml 633.04 | 4.117 | PASS |
| synthetic_wide_siblings.xml | 2014.12 | 420.47 | 318.61 | pugixml 420.47 | 4.790 | PASS |
| synthetic_namespace_mix.xml | 2911.27 | 676.03 | 584.55 | pugixml 676.03 | 4.306 | PASS |
| synthetic_long_names.xml | 4555.74 | 1276.09 | 1654.48 | rapidxml 1654.48 | 2.754 | PASS |
| synthetic_self_closing_swarm.xml | 2589.90 | 523.72 | 482.21 | pugixml 523.72 | 4.945 | PASS |
| synthetic_mixed_content.xml | 2445.50 | 503.14 | 380.64 | pugixml 503.14 | 4.860 | PASS |
| synthetic_small_records.xml | 2177.09 | 426.26 | 297.11 | pugixml 426.26 | 5.107 | PASS |
| synthetic_tiny_empty.xml | 1155.70 | 195.88 | 119.54 | pugixml 195.88 | 5.900 | PASS |
| synthetic_tiny_text.xml | 926.43 | 184.62 | 119.53 | pugixml 184.62 | 5.018 | PASS |
| synthetic_one_attr.xml | 1338.76 | 290.18 | 197.70 | pugixml 290.18 | 4.613 | PASS |
| synthetic_two_attr.xml | 1474.26 | 318.19 | 213.92 | pugixml 318.19 | 4.633 | PASS |
| synthetic_attrs4.xml | 1497.73 | 319.14 | 264.44 | pugixml 319.14 | 4.693 | PASS |
| synthetic_attrs8.xml | 1636.02 | 359.87 | 272.64 | pugixml 359.87 | 4.546 | PASS |
| synthetic_attrs16.xml | 1757.30 | 441.83 | 375.13 | pugixml 441.83 | 3.977 | PASS |
| synthetic_attrs32.xml | 1836.42 | 450.58 | 399.51 | pugixml 450.58 | 4.076 | PASS |
| synthetic_attrs48.xml | 1901.56 | 472.64 | 414.51 | pugixml 472.64 | 4.023 | PASS |
| synthetic_attrs64.xml | 2022.83 | 533.20 | 454.10 | pugixml 533.20 | 3.794 | PASS |
| synthetic_attrs96.xml | 2108.82 | 546.26 | 468.23 | pugixml 546.26 | 3.860 | PASS |
| synthetic_attrs128.xml | 2176.24 | 556.15 | 482.82 | pugixml 556.15 | 3.913 | PASS |
| synthetic_long_attr_values.xml | 5246.61 | 1407.37 | 1393.98 | pugixml 1407.37 | 3.728 | PASS |
| synthetic_single_quotes.xml | 2000.94 | 493.71 | 405.23 | pugixml 493.71 | 4.053 | PASS |
| synthetic_unicode_names.xml | 2844.57 | 625.66 | 490.49 | pugixml 625.66 | 4.547 | PASS |
| synthetic_pretty_indented.xml | 2341.92 | 492.00 | 386.29 | pugixml 492.00 | 4.760 | PASS |
| synthetic_crlf_pretty.xml | 2124.37 | 515.37 | 391.01 | pugixml 515.37 | 4.122 | PASS |
| synthetic_token_whitespace_mix.xml | 1437.48 | 441.50 | 367.15 | pugixml 441.50 | 3.256 | PASS |
| synthetic_attr_count_mix.xml | 1790.51 | 371.13 | 313.85 | pugixml 371.13 | 4.824 | PASS |

## Streaming Comparison (Advisory)

| Fixture | stream-turbo | ours-turbo | stream/ours | stream-strict | ours-strict | stream/ours |
|---|---:|---:|---:|---:|---:|---:|
| note.xml | 2946.79 | 2976.49 | 0.990 | 1339.16 | 1463.64 | 0.915 |
| sitemaps.xml | 3699.31 | 3683.65 | 1.004 | 1700.21 | 1864.88 | 0.912 |
| plant_catalog.xml | 2619.85 | 3038.54 | 0.862 | 1443.57 | 1400.10 | 1.031 |
| cd_catalog.xml | 2549.84 | 2805.45 | 0.909 | 1277.05 | 1389.74 | 0.919 |
| hnrss.xml | 8096.25 | 8011.36 | 1.011 | 4109.22 | 3752.66 | 1.095 |
| xkcd_rss.xml | 8422.88 | 8394.76 | 1.003 | 3317.30 | 4034.20 | 0.822 |
| bbc_world.xml | 5422.98 | 4938.07 | 1.098 | 2948.31 | 3070.13 | 0.960 |
| arxiv_cs.xml | 9682.07 | 9727.18 | 0.995 | 4018.66 | 4111.78 | 0.977 |
| ecb_usd.xml | 4699.35 | 5016.33 | 0.937 | 2752.48 | 2993.33 | 0.920 |
| tree.xml | 2892.09 | 2326.47 | 1.243 | 1317.84 | 1209.70 | 1.089 |
| character.xml | 2558.39 | 2605.15 | 0.982 | 1311.06 | 1321.06 | 0.992 |
| xgconsole.xml | 3741.27 | 3035.83 | 1.232 | 1281.15 | 1649.65 | 0.777 |
| weekly_utf8.xml | 3635.69 | 3078.29 | 1.181 | 570.60 | 522.71 | 1.092 |
| pugixml_large.xml | 2453.68 | 2308.05 | 1.063 | 1695.42 | 1666.46 | 1.017 |
| synthetic_flat_attrs.xml | 2484.98 | 1479.37 | 1.680 | 939.38 | 889.50 | 1.056 |
| synthetic_deep_tree.xml | 1767.55 | 1415.72 | 1.249 | 908.02 | 946.44 | 0.959 |
| synthetic_entities.xml | 5293.71 | 4649.04 | 1.139 | 922.18 | 985.40 | 0.936 |
| synthetic_cdata_mix.xml | 2478.22 | 2606.41 | 0.951 | 1720.52 | 2072.32 | 0.830 |
| synthetic_wide_siblings.xml | 2207.37 | 2014.12 | 1.096 | 1038.19 | 1181.64 | 0.879 |
| synthetic_namespace_mix.xml | 3428.15 | 2911.27 | 1.178 | 1412.58 | 1449.29 | 0.975 |
| synthetic_long_names.xml | 3960.44 | 4555.74 | 0.869 | 2773.99 | 3332.31 | 0.832 |
| synthetic_self_closing_swarm.xml | 3259.90 | 2589.90 | 1.259 | 1268.99 | 1197.71 | 1.060 |
| synthetic_mixed_content.xml | 2782.06 | 2445.50 | 1.138 | 1344.05 | 1456.22 | 0.923 |
| synthetic_small_records.xml | 2148.54 | 2177.09 | 0.987 | 1217.49 | 1567.24 | 0.777 |
| synthetic_tiny_empty.xml | 1476.90 | 1155.70 | 1.278 | 1281.36 | 836.62 | 1.532 |
| synthetic_tiny_text.xml | 966.85 | 926.43 | 1.044 | 672.53 | 815.20 | 0.825 |
| synthetic_one_attr.xml | 1806.50 | 1338.76 | 1.349 | 877.97 | 1000.16 | 0.878 |
| synthetic_two_attr.xml | 1769.43 | 1474.26 | 1.200 | 950.47 | 941.82 | 1.009 |
| synthetic_attrs4.xml | 2176.22 | 1497.73 | 1.453 | 916.08 | 896.23 | 1.022 |
| synthetic_attrs8.xml | 2368.59 | 1636.02 | 1.448 | 899.99 | 900.78 | 0.999 |
| synthetic_attrs16.xml | 2925.72 | 1757.30 | 1.665 | 1043.17 | 904.66 | 1.153 |
| synthetic_attrs32.xml | 3023.84 | 1836.42 | 1.647 | 628.88 | 997.69 | 0.630 |
| synthetic_attrs48.xml | 3118.34 | 1901.56 | 1.640 | 691.67 | 1035.45 | 0.668 |
| synthetic_attrs64.xml | 3146.95 | 2022.83 | 1.556 | 697.61 | 1110.67 | 0.628 |
| synthetic_attrs96.xml | 3261.21 | 2108.82 | 1.546 | 528.91 | 1142.19 | 0.463 |
| synthetic_attrs128.xml | 3283.83 | 2176.24 | 1.509 | 558.02 | 1123.86 | 0.497 |
| synthetic_long_attr_values.xml | 5604.79 | 5246.61 | 1.068 | 3357.94 | 3515.36 | 0.955 |
| synthetic_single_quotes.xml | 2709.92 | 2000.94 | 1.354 | 1072.67 | 1132.71 | 0.947 |
| synthetic_unicode_names.xml | 3438.47 | 2844.57 | 1.209 | 436.53 | 450.28 | 0.969 |
| synthetic_pretty_indented.xml | 2352.76 | 2341.92 | 1.005 | 1132.57 | 1367.28 | 0.828 |
| synthetic_crlf_pretty.xml | 2750.07 | 2124.37 | 1.295 | 1237.14 | 1220.50 | 1.014 |
| synthetic_token_whitespace_mix.xml | 1523.55 | 1437.48 | 1.060 | 903.83 | 889.25 | 1.016 |
| synthetic_attr_count_mix.xml | 2605.58 | 1790.51 | 1.455 | 914.74 | 940.04 | 0.973 |

## Strict Pathology Regression Checks

2/2 passed. These fixtures are excluded from headline averages and stable external gates.
Detailed timings remain in `bench/results/latest.json` for regression analysis.
