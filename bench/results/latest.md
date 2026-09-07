# ZXML Benchmark Results

Generated (unix): 1788770692

Profile: `stable`

Collection: independently guarded fixture windows on CPU6, not one continuous quiet interval. Every retained fixture passed its complete calibration/sample guard.

## Benchmark Environment

| Property | Value |
|---|---|
| OS / kernel | Linux 7.2.2-zen1-1-zen |
| Architecture | x86_64 |
| CPU | 12th Gen Intel(R) Core(TM) i5-12450H |
| CPU frequency scaling | 61% |
| CPU MHz range | 400.0000–4400.0000 |
| Zig | 0.16.0 (`ReleaseFast -Dcpu=native`) |
| C++ driver | c++ (`-O3 -DNDEBUG -march=native`) |

## Parse Throughput

| Fixture | Parser | Throughput (MB/s) | Median Time (ms) | Iterations |
|---|---|---:|---:|---:|
| note.xml | ours-validated | 1700.81 | 35.72 | 370485 |
| note.xml | ours-permissive | 2896.59 | 36.56 | 645752 |
| note.xml | stream-validated | 1359.56 | 24.46 | 202761 |
| note.xml | stream-permissive | 3397.09 | 34.89 | 722805 |
| note.xml | pugixml | 1004.39 | 30.24 | 185171 |
| note.xml | rapidxml | 1777.77 | 39.30 | 426046 |
| sitemaps.xml | ours-validated | 2064.18 | 41.26 | 9878 |
| sitemaps.xml | ours-permissive | 4143.51 | 40.67 | 19544 |
| sitemaps.xml | stream-validated | 1718.95 | 39.62 | 7899 |
| sitemaps.xml | stream-permissive | 3585.86 | 40.42 | 16810 |
| sitemaps.xml | pugixml | 2005.55 | 41.71 | 9703 |
| sitemaps.xml | rapidxml | 2016.09 | 41.95 | 9810 |
| plant_catalog.xml | ours-validated | 1864.61 | 39.64 | 9563 |
| plant_catalog.xml | ours-permissive | 3693.96 | 40.23 | 19229 |
| plant_catalog.xml | stream-validated | 1523.58 | 38.96 | 7680 |
| plant_catalog.xml | stream-permissive | 3125.16 | 37.61 | 15209 |
| plant_catalog.xml | pugixml | 1568.34 | 36.56 | 7418 |
| plant_catalog.xml | rapidxml | 1744.29 | 39.64 | 8945 |
| cd_catalog.xml | ours-validated | 1757.73 | 37.38 | 13503 |
| cd_catalog.xml | ours-permissive | 3389.45 | 40.26 | 28040 |
| cd_catalog.xml | stream-validated | 1388.91 | 38.91 | 11106 |
| cd_catalog.xml | stream-permissive | 2801.73 | 37.88 | 21812 |
| cd_catalog.xml | pugixml | 1510.87 | 37.17 | 11540 |
| cd_catalog.xml | rapidxml | 1636.23 | 35.40 | 11905 |
| hnrss.xml | ours-validated | 5541.31 | 33.07 | 9915 |
| hnrss.xml | ours-permissive | 10064.06 | 34.32 | 18690 |
| hnrss.xml | stream-validated | 4309.44 | 38.18 | 8903 |
| hnrss.xml | stream-permissive | 8372.60 | 37.32 | 16906 |
| hnrss.xml | pugixml | 3014.61 | 39.52 | 6447 |
| hnrss.xml | rapidxml | 2706.89 | 39.08 | 5724 |
| xkcd_rss.xml | ours-validated | 4140.86 | 36.10 | 60642 |
| xkcd_rss.xml | ours-permissive | 8720.08 | 41.16 | 145602 |
| xkcd_rss.xml | stream-validated | 3208.49 | 37.91 | 49344 |
| xkcd_rss.xml | stream-permissive | 8617.95 | 37.93 | 132605 |
| xkcd_rss.xml | pugixml | 2519.39 | 39.29 | 40160 |
| xkcd_rss.xml | rapidxml | 2588.01 | 41.23 | 43284 |
| bbc_world.xml | ours-validated | 3470.61 | 39.60 | 5937 |
| bbc_world.xml | ours-permissive | 6130.75 | 30.01 | 7948 |
| bbc_world.xml | stream-validated | 3103.76 | 31.69 | 4249 |
| bbc_world.xml | stream-permissive | 5034.80 | 36.88 | 8020 |
| bbc_world.xml | pugixml | 2654.27 | 39.05 | 4477 |
| bbc_world.xml | rapidxml | 2561.68 | 38.65 | 4277 |
| arxiv_cs.xml | ours-validated | 4160.02 | 39.53 | 76 |
| arxiv_cs.xml | ours-permissive | 8499.86 | 45.82 | 180 |
| arxiv_cs.xml | stream-validated | 4507.49 | 37.92 | 79 |
| arxiv_cs.xml | stream-permissive | 10331.91 | 37.69 | 180 |
| arxiv_cs.xml | pugixml | 2738.87 | 40.29 | 51 |
| arxiv_cs.xml | rapidxml | 1929.20 | 35.89 | 32 |
| ecb_usd.xml | ours-validated | 3253.73 | 35.96 | 16025 |
| ecb_usd.xml | ours-permissive | 6787.37 | 40.43 | 37585 |
| ecb_usd.xml | stream-validated | 2794.58 | 39.61 | 15159 |
| ecb_usd.xml | stream-permissive | 5249.54 | 40.66 | 29233 |
| ecb_usd.xml | pugixml | 2765.87 | 36.72 | 13909 |
| ecb_usd.xml | rapidxml | 2824.94 | 38.36 | 14839 |
| tree.xml | ours-validated | 1476.76 | 36.57 | 219544 |
| tree.xml | ours-permissive | 3169.99 | 36.19 | 466314 |
| tree.xml | stream-validated | 1439.60 | 35.65 | 208651 |
| tree.xml | stream-permissive | 2803.41 | 37.17 | 423617 |
| tree.xml | pugixml | 1304.25 | 33.75 | 178911 |
| tree.xml | rapidxml | 2115.65 | 37.63 | 323658 |
| character.xml | ours-validated | 1387.48 | 32.12 | 246230 |
| character.xml | ours-permissive | 3291.46 | 29.86 | 543081 |
| character.xml | stream-validated | 1427.26 | 36.51 | 287898 |
| character.xml | stream-permissive | 2545.73 | 35.78 | 503267 |
| character.xml | pugixml | 1101.20 | 21.67 | 131853 |
| character.xml | rapidxml | 2021.02 | 35.32 | 394403 |
| transitions.xml | ours-permissive | 3576.53 | 34.49 | 590239 |
| transitions.xml | stream-permissive | 2243.44 | 39.37 | 422593 |
| transitions.xml | pugixml | 1404.53 | 32.72 | 219897 |
| transitions.xml | rapidxml | 2176.05 | 22.95 | 238905 |
| xgconsole.xml | ours-validated | 2027.04 | 34.36 | 96459 |
| xgconsole.xml | ours-permissive | 6079.60 | 39.03 | 328661 |
| xgconsole.xml | stream-validated | 1341.56 | 33.32 | 61904 |
| xgconsole.xml | stream-permissive | 3788.93 | 35.73 | 187489 |
| xgconsole.xml | pugixml | 1913.95 | 30.08 | 79731 |
| xgconsole.xml | rapidxml | 2517.80 | 28.43 | 99130 |
| weekly_utf8.xml | ours-validated | 1291.42 | 38.07 | 18757 |
| weekly_utf8.xml | ours-permissive | 3730.22 | 36.25 | 51592 |
| weekly_utf8.xml | stream-validated | 689.53 | 39.46 | 10380 |
| weekly_utf8.xml | stream-permissive | 3272.71 | 39.03 | 48732 |
| weekly_utf8.xml | pugixml | 2282.23 | 37.39 | 32553 |
| weekly_utf8.xml | rapidxml | 2461.79 | 37.67 | 35382 |
| pugixml_large.xml | ours-validated | 1520.66 | 38.67 | 840 |
| pugixml_large.xml | ours-permissive | 2636.98 | 32.90 | 1239 |
| pugixml_large.xml | stream-validated | 1705.47 | 38.01 | 926 |
| pugixml_large.xml | stream-permissive | 2165.66 | 38.12 | 1179 |
| pugixml_large.xml | pugixml | 495.04 | 38.47 | 272 |
| pugixml_large.xml | rapidxml | 317.60 | 38.36 | 174 |
| synthetic_flat_attrs.xml | ours-validated | 1349.42 | 47.08 | 280 |
| synthetic_flat_attrs.xml | ours-permissive | 6967.31 | 40.22 | 1235 |
| synthetic_flat_attrs.xml | stream-validated | 1013.17 | 62.71 | 280 |
| synthetic_flat_attrs.xml | stream-permissive | 2784.60 | 22.82 | 280 |
| synthetic_flat_attrs.xml | pugixml | 485.24 | 40.68 | 87 |
| synthetic_flat_attrs.xml | rapidxml | 382.07 | 40.38 | 68 |
| synthetic_deep_tree.xml | ours-validated | 1196.36 | 39.33 | 25937 |
| synthetic_deep_tree.xml | ours-permissive | 1949.86 | 39.59 | 42557 |
| synthetic_deep_tree.xml | stream-validated | 1046.97 | 39.25 | 22653 |
| synthetic_deep_tree.xml | stream-permissive | 1525.05 | 39.13 | 32900 |
| synthetic_deep_tree.xml | pugixml | 1335.70 | 37.60 | 27689 |
| synthetic_deep_tree.xml | rapidxml | 803.21 | 38.77 | 17167 |
| synthetic_entities.xml | ours-validated | 10631.20 | 39.86 | 645 |
| synthetic_entities.xml | ours-permissive | 10747.98 | 39.73 | 650 |
| synthetic_entities.xml | stream-validated | 848.00 | 41.84 | 54 |
| synthetic_entities.xml | stream-permissive | 6031.90 | 26.14 | 240 |
| synthetic_entities.xml | pugixml | 952.89 | 40.68 | 59 |
| synthetic_entities.xml | rapidxml | 967.42 | 40.07 | 59 |
| synthetic_cdata_mix.xml | ours-validated | 1826.01 | 37.98 | 561 |
| synthetic_cdata_mix.xml | ours-permissive | 2442.64 | 39.17 | 774 |
| synthetic_cdata_mix.xml | stream-validated | 1783.90 | 39.36 | 568 |
| synthetic_cdata_mix.xml | stream-permissive | 3007.99 | 39.33 | 957 |
| synthetic_cdata_mix.xml | pugixml | 697.09 | 42.56 | 240 |
| synthetic_cdata_mix.xml | rapidxml | 537.14 | 55.24 | 240 |
| synthetic_wide_siblings.xml | ours-validated | 963.56 | 37.92 | 101 |
| synthetic_wide_siblings.xml | ours-permissive | 1236.34 | 76.08 | 260 |
| synthetic_wide_siblings.xml | stream-validated | 976.39 | 42.24 | 114 |
| synthetic_wide_siblings.xml | stream-permissive | 2362.38 | 39.82 | 260 |
| synthetic_wide_siblings.xml | pugixml | 421.00 | 37.81 | 44 |
| synthetic_wide_siblings.xml | rapidxml | 310.13 | 36.16 | 31 |
| synthetic_namespace_mix.xml | ours-validated | 1469.58 | 39.06 | 97 |
| synthetic_namespace_mix.xml | ours-permissive | 3835.42 | 33.94 | 220 |
| synthetic_namespace_mix.xml | stream-validated | 1525.50 | 40.73 | 105 |
| synthetic_namespace_mix.xml | stream-permissive | 3302.78 | 39.42 | 220 |
| synthetic_namespace_mix.xml | pugixml | 719.81 | 41.10 | 50 |
| synthetic_namespace_mix.xml | rapidxml | 593.40 | 40.89 | 41 |
| synthetic_long_names.xml | ours-validated | 3379.33 | 61.24 | 220 |
| synthetic_long_names.xml | ours-permissive | 6786.15 | 30.50 | 220 |
| synthetic_long_names.xml | stream-validated | 2553.45 | 40.16 | 109 |
| synthetic_long_names.xml | stream-permissive | 4827.34 | 42.87 | 220 |
| synthetic_long_names.xml | pugixml | 1388.39 | 40.65 | 60 |
| synthetic_long_names.xml | rapidxml | 1701.42 | 38.70 | 70 |
| synthetic_self_closing_swarm.xml | ours-validated | 1261.78 | 40.96 | 37 |
| synthetic_self_closing_swarm.xml | ours-permissive | 4781.37 | 64.27 | 220 |
| synthetic_self_closing_swarm.xml | stream-validated | 1461.59 | 40.14 | 42 |
| synthetic_self_closing_swarm.xml | stream-permissive | 3411.99 | 40.12 | 98 |
| synthetic_self_closing_swarm.xml | pugixml | 630.78 | 39.86 | 18 |
| synthetic_self_closing_swarm.xml | rapidxml | 524.63 | 39.94 | 15 |
| synthetic_mixed_content.xml | ours-validated | 1383.38 | 40.49 | 89 |
| synthetic_mixed_content.xml | ours-permissive | 2340.58 | 59.16 | 220 |
| synthetic_mixed_content.xml | stream-validated | 1348.66 | 40.60 | 87 |
| synthetic_mixed_content.xml | stream-permissive | 3021.33 | 45.83 | 220 |
| synthetic_mixed_content.xml | pugixml | 545.16 | 41.56 | 36 |
| synthetic_mixed_content.xml | rapidxml | 398.08 | 42.69 | 27 |
| synthetic_small_records.xml | ours-validated | 1299.81 | 41.22 | 45 |
| synthetic_small_records.xml | ours-permissive | 1896.25 | 38.93 | 62 |
| synthetic_small_records.xml | stream-validated | 1260.37 | 40.62 | 43 |
| synthetic_small_records.xml | stream-permissive | 2612.33 | 39.65 | 87 |
| synthetic_small_records.xml | pugixml | 422.98 | 39.41 | 14 |
| synthetic_small_records.xml | rapidxml | 297.44 | 40.03 | 10 |
| synthetic_tiny_empty.xml | ours-validated | 1718.34 | 39.95 | 78 |
| synthetic_tiny_empty.xml | ours-permissive | 1703.60 | 40.81 | 79 |
| synthetic_tiny_empty.xml | stream-validated | 1288.58 | 40.29 | 59 |
| synthetic_tiny_empty.xml | stream-permissive | 1565.09 | 39.92 | 71 |
| synthetic_tiny_empty.xml | pugixml | 191.78 | 41.30 | 9 |
| synthetic_tiny_empty.xml | rapidxml | 118.46 | 44.57 | 6 |
| synthetic_tiny_text.xml | ours-validated | 1764.77 | 40.80 | 75 |
| synthetic_tiny_text.xml | ours-permissive | 1773.60 | 40.05 | 74 |
| synthetic_tiny_text.xml | stream-validated | 697.94 | 41.26 | 30 |
| synthetic_tiny_text.xml | stream-permissive | 1344.36 | 39.99 | 56 |
| synthetic_tiny_text.xml | pugixml | 179.39 | 42.81 | 8 |
| synthetic_tiny_text.xml | rapidxml | 122.31 | 47.09 | 6 |
| synthetic_one_attr.xml | ours-validated | 3699.31 | 72.99 | 300 |
| synthetic_one_attr.xml | ours-permissive | 3727.10 | 72.44 | 300 |
| synthetic_one_attr.xml | stream-validated | 1091.93 | 40.39 | 49 |
| synthetic_one_attr.xml | stream-permissive | 1816.53 | 40.13 | 81 |
| synthetic_one_attr.xml | pugixml | 284.39 | 41.14 | 13 |
| synthetic_one_attr.xml | rapidxml | 189.07 | 42.84 | 9 |
| synthetic_two_attr.xml | ours-validated | 5547.62 | 52.49 | 280 |
| synthetic_two_attr.xml | ours-permissive | 5588.00 | 52.11 | 280 |
| synthetic_two_attr.xml | stream-validated | 1073.86 | 39.71 | 41 |
| synthetic_two_attr.xml | stream-permissive | 2052.47 | 40.03 | 79 |
| synthetic_two_attr.xml | pugixml | 312.37 | 39.95 | 12 |
| synthetic_two_attr.xml | rapidxml | 220.78 | 37.68 | 8 |
| synthetic_attrs4.xml | ours-validated | 8472.63 | 30.14 | 240 |
| synthetic_attrs4.xml | ours-permissive | 8607.36 | 29.67 | 240 |
| synthetic_attrs4.xml | stream-validated | 970.10 | 40.58 | 37 |
| synthetic_attrs4.xml | stream-permissive | 2346.34 | 40.36 | 89 |
| synthetic_attrs4.xml | pugixml | 338.39 | 40.88 | 13 |
| synthetic_attrs4.xml | rapidxml | 248.75 | 42.77 | 10 |
| synthetic_attrs8.xml | ours-validated | 12530.89 | 39.91 | 458 |
| synthetic_attrs8.xml | ours-permissive | 12911.00 | 37.98 | 449 |
| synthetic_attrs8.xml | stream-validated | 947.13 | 40.35 | 35 |
| synthetic_attrs8.xml | stream-permissive | 2468.69 | 41.58 | 94 |
| synthetic_attrs8.xml | pugixml | 335.35 | 42.33 | 13 |
| synthetic_attrs8.xml | rapidxml | 255.90 | 42.67 | 10 |
| synthetic_single_quotes.xml | ours-validated | 9964.43 | 24.28 | 240 |
| synthetic_single_quotes.xml | ours-permissive | 10097.03 | 23.96 | 240 |
| synthetic_single_quotes.xml | stream-validated | 1272.07 | 40.41 | 51 |
| synthetic_single_quotes.xml | stream-permissive | 3058.01 | 79.11 | 240 |
| synthetic_single_quotes.xml | pugixml | 533.26 | 41.59 | 22 |
| synthetic_single_quotes.xml | rapidxml | 425.13 | 40.31 | 17 |
| synthetic_unicode_names.xml | ours-validated | 8476.01 | 26.16 | 180 |
| synthetic_unicode_names.xml | ours-permissive | 8587.17 | 25.82 | 180 |
| synthetic_unicode_names.xml | stream-validated | 568.14 | 41.20 | 19 |
| synthetic_unicode_names.xml | stream-permissive | 3418.14 | 64.88 | 180 |
| synthetic_unicode_names.xml | pugixml | 653.29 | 39.60 | 21 |
| synthetic_unicode_names.xml | rapidxml | 551.73 | 40.19 | 18 |
| synthetic_pretty_indented.xml | ours-validated | 1355.12 | 39.88 | 57 |
| synthetic_pretty_indented.xml | ours-permissive | 1930.66 | 39.77 | 81 |
| synthetic_pretty_indented.xml | stream-validated | 1245.59 | 41.86 | 55 |
| synthetic_pretty_indented.xml | stream-permissive | 2439.05 | 77.74 | 200 |
| synthetic_pretty_indented.xml | pugixml | 523.17 | 39.87 | 22 |
| synthetic_pretty_indented.xml | rapidxml | 414.64 | 41.15 | 18 |
| synthetic_crlf_pretty.xml | ours-validated | 1150.47 | 43.27 | 61 |
| synthetic_crlf_pretty.xml | ours-permissive | 2016.92 | 80.92 | 200 |
| synthetic_crlf_pretty.xml | stream-validated | 1261.10 | 41.41 | 64 |
| synthetic_crlf_pretty.xml | stream-permissive | 2925.20 | 55.79 | 200 |
| synthetic_crlf_pretty.xml | pugixml | 503.59 | 43.75 | 27 |
| synthetic_crlf_pretty.xml | rapidxml | 422.12 | 42.53 | 22 |
| synthetic_token_whitespace_mix.xml | ours-validated | 8987.29 | 40.89 | 439 |
| synthetic_token_whitespace_mix.xml | ours-permissive | 9248.32 | 38.83 | 429 |
| synthetic_token_whitespace_mix.xml | stream-validated | 967.24 | 41.54 | 48 |
| synthetic_token_whitespace_mix.xml | stream-permissive | 1439.68 | 41.86 | 72 |
| synthetic_token_whitespace_mix.xml | pugixml | 406.32 | 45.32 | 22 |
| synthetic_token_whitespace_mix.xml | rapidxml | 368.87 | 43.11 | 19 |
| synthetic_attr_count_mix.xml | ours-validated | 1427.08 | 41.67 | 14 |
| synthetic_attr_count_mix.xml | ours-permissive | 6789.05 | 39.42 | 63 |
| synthetic_attr_count_mix.xml | stream-validated | 1067.51 | 39.79 | 10 |
| synthetic_attr_count_mix.xml | stream-permissive | 2849.51 | 40.25 | 27 |
| synthetic_attr_count_mix.xml | pugixml | 392.92 | 43.25 | 4 |
| synthetic_attr_count_mix.xml | rapidxml | 308.65 | 41.29 | 3 |

## Stable Gates

| Fixture | ours-permissive | pugixml | rapidxml | best external | ours/best-ext | Result |
|---|---:|---:|---:|---|---:|---|
| note.xml | 2896.59 | 1004.39 | 1777.77 | rapidxml 1777.77 | 1.629 | PASS |
| sitemaps.xml | 4143.51 | 2005.55 | 2016.09 | rapidxml 2016.09 | 2.055 | PASS |
| plant_catalog.xml | 3693.96 | 1568.34 | 1744.29 | rapidxml 1744.29 | 2.118 | PASS |
| cd_catalog.xml | 3389.45 | 1510.87 | 1636.23 | rapidxml 1636.23 | 2.072 | PASS |
| hnrss.xml | 10064.06 | 3014.61 | 2706.89 | pugixml 3014.61 | 3.338 | PASS |
| xkcd_rss.xml | 8720.08 | 2519.39 | 2588.01 | rapidxml 2588.01 | 3.369 | PASS |
| bbc_world.xml | 6130.75 | 2654.27 | 2561.68 | pugixml 2654.27 | 2.310 | PASS |
| arxiv_cs.xml | 8499.86 | 2738.87 | 1929.20 | pugixml 2738.87 | 3.103 | PASS |
| ecb_usd.xml | 6787.37 | 2765.87 | 2824.94 | rapidxml 2824.94 | 2.403 | PASS |
| tree.xml | 3169.99 | 1304.25 | 2115.65 | rapidxml 2115.65 | 1.498 | PASS |
| character.xml | 3291.46 | 1101.20 | 2021.02 | rapidxml 2021.02 | 1.629 | PASS |
| transitions.xml | 3576.53 | 1404.53 | 2176.05 | rapidxml 2176.05 | 1.644 | PASS |
| xgconsole.xml | 6079.60 | 1913.95 | 2517.80 | rapidxml 2517.80 | 2.415 | PASS |
| weekly_utf8.xml | 3730.22 | 2282.23 | 2461.79 | rapidxml 2461.79 | 1.515 | PASS |
| pugixml_large.xml | 2636.98 | 495.04 | 317.60 | pugixml 495.04 | 5.327 | PASS |
| synthetic_flat_attrs.xml | 6967.31 | 485.24 | 382.07 | pugixml 485.24 | 14.359 | PASS |
| synthetic_deep_tree.xml | 1949.86 | 1335.70 | 803.21 | pugixml 1335.70 | 1.460 | PASS |
| synthetic_entities.xml | 10747.98 | 952.89 | 967.42 | rapidxml 967.42 | 11.110 | PASS |
| synthetic_cdata_mix.xml | 2442.64 | 697.09 | 537.14 | pugixml 697.09 | 3.504 | PASS |
| synthetic_wide_siblings.xml | 1236.34 | 421.00 | 310.13 | pugixml 421.00 | 2.937 | PASS |
| synthetic_namespace_mix.xml | 3835.42 | 719.81 | 593.40 | pugixml 719.81 | 5.328 | PASS |
| synthetic_long_names.xml | 6786.15 | 1388.39 | 1701.42 | rapidxml 1701.42 | 3.989 | PASS |
| synthetic_self_closing_swarm.xml | 4781.37 | 630.78 | 524.63 | pugixml 630.78 | 7.580 | PASS |
| synthetic_mixed_content.xml | 2340.58 | 545.16 | 398.08 | pugixml 545.16 | 4.293 | PASS |
| synthetic_small_records.xml | 1896.25 | 422.98 | 297.44 | pugixml 422.98 | 4.483 | PASS |
| synthetic_tiny_empty.xml | 1703.60 | 191.78 | 118.46 | pugixml 191.78 | 8.883 | PASS |
| synthetic_tiny_text.xml | 1773.60 | 179.39 | 122.31 | pugixml 179.39 | 9.887 | PASS |
| synthetic_one_attr.xml | 3727.10 | 284.39 | 189.07 | pugixml 284.39 | 13.106 | PASS |
| synthetic_two_attr.xml | 5588.00 | 312.37 | 220.78 | pugixml 312.37 | 17.889 | PASS |
| synthetic_attrs4.xml | 8607.36 | 338.39 | 248.75 | pugixml 338.39 | 25.436 | PASS |
| synthetic_attrs8.xml | 12911.00 | 335.35 | 255.90 | pugixml 335.35 | 38.500 | PASS |
| synthetic_single_quotes.xml | 10097.03 | 533.26 | 425.13 | pugixml 533.26 | 18.935 | PASS |
| synthetic_unicode_names.xml | 8587.17 | 653.29 | 551.73 | pugixml 653.29 | 13.145 | PASS |
| synthetic_pretty_indented.xml | 1930.66 | 523.17 | 414.64 | pugixml 523.17 | 3.690 | PASS |
| synthetic_crlf_pretty.xml | 2016.92 | 503.59 | 422.12 | pugixml 503.59 | 4.005 | PASS |
| synthetic_token_whitespace_mix.xml | 9248.32 | 406.32 | 368.87 | pugixml 406.32 | 22.761 | PASS |
| synthetic_attr_count_mix.xml | 6789.05 | 392.92 | 308.65 | pugixml 392.92 | 17.278 | PASS |

## Streaming Comparison (Advisory)

| Fixture | stream-permissive | ours-permissive | stream/ours | stream-validated | ours-validated | stream/ours |
|---|---:|---:|---:|---:|---:|---:|
| note.xml | 3397.09 | 2896.59 | 1.173 | 1359.56 | 1700.81 | 0.799 |
| sitemaps.xml | 3585.86 | 4143.51 | 0.865 | 1718.95 | 2064.18 | 0.833 |
| plant_catalog.xml | 3125.16 | 3693.96 | 0.846 | 1523.58 | 1864.61 | 0.817 |
| cd_catalog.xml | 2801.73 | 3389.45 | 0.827 | 1388.91 | 1757.73 | 0.790 |
| hnrss.xml | 8372.60 | 10064.06 | 0.832 | 4309.44 | 5541.31 | 0.778 |
| xkcd_rss.xml | 8617.95 | 8720.08 | 0.988 | 3208.49 | 4140.86 | 0.775 |
| bbc_world.xml | 5034.80 | 6130.75 | 0.821 | 3103.76 | 3470.61 | 0.894 |
| arxiv_cs.xml | 10331.91 | 8499.86 | 1.216 | 4507.49 | 4160.02 | 1.084 |
| ecb_usd.xml | 5249.54 | 6787.37 | 0.773 | 2794.58 | 3253.73 | 0.859 |
| tree.xml | 2803.41 | 3169.99 | 0.884 | 1439.60 | 1476.76 | 0.975 |
| character.xml | 2545.73 | 3291.46 | 0.773 | 1427.26 | 1387.48 | 1.029 |
| xgconsole.xml | 3788.93 | 6079.60 | 0.623 | 1341.56 | 2027.04 | 0.662 |
| weekly_utf8.xml | 3272.71 | 3730.22 | 0.877 | 689.53 | 1291.42 | 0.534 |
| pugixml_large.xml | 2165.66 | 2636.98 | 0.821 | 1705.47 | 1520.66 | 1.122 |
| synthetic_flat_attrs.xml | 2784.60 | 6967.31 | 0.400 | 1013.17 | 1349.42 | 0.751 |
| synthetic_deep_tree.xml | 1525.05 | 1949.86 | 0.782 | 1046.97 | 1196.36 | 0.875 |
| synthetic_entities.xml | 6031.90 | 10747.98 | 0.561 | 848.00 | 10631.20 | 0.080 |
| synthetic_cdata_mix.xml | 3007.99 | 2442.64 | 1.231 | 1783.90 | 1826.01 | 0.977 |
| synthetic_wide_siblings.xml | 2362.38 | 1236.34 | 1.911 | 976.39 | 963.56 | 1.013 |
| synthetic_namespace_mix.xml | 3302.78 | 3835.42 | 0.861 | 1525.50 | 1469.58 | 1.038 |
| synthetic_long_names.xml | 4827.34 | 6786.15 | 0.711 | 2553.45 | 3379.33 | 0.756 |
| synthetic_self_closing_swarm.xml | 3411.99 | 4781.37 | 0.714 | 1461.59 | 1261.78 | 1.158 |
| synthetic_mixed_content.xml | 3021.33 | 2340.58 | 1.291 | 1348.66 | 1383.38 | 0.975 |
| synthetic_small_records.xml | 2612.33 | 1896.25 | 1.378 | 1260.37 | 1299.81 | 0.970 |
| synthetic_tiny_empty.xml | 1565.09 | 1703.60 | 0.919 | 1288.58 | 1718.34 | 0.750 |
| synthetic_tiny_text.xml | 1344.36 | 1773.60 | 0.758 | 697.94 | 1764.77 | 0.395 |
| synthetic_one_attr.xml | 1816.53 | 3727.10 | 0.487 | 1091.93 | 3699.31 | 0.295 |
| synthetic_two_attr.xml | 2052.47 | 5588.00 | 0.367 | 1073.86 | 5547.62 | 0.194 |
| synthetic_attrs4.xml | 2346.34 | 8607.36 | 0.273 | 970.10 | 8472.63 | 0.114 |
| synthetic_attrs8.xml | 2468.69 | 12911.00 | 0.191 | 947.13 | 12530.89 | 0.076 |
| synthetic_single_quotes.xml | 3058.01 | 10097.03 | 0.303 | 1272.07 | 9964.43 | 0.128 |
| synthetic_unicode_names.xml | 3418.14 | 8587.17 | 0.398 | 568.14 | 8476.01 | 0.067 |
| synthetic_pretty_indented.xml | 2439.05 | 1930.66 | 1.263 | 1245.59 | 1355.12 | 0.919 |
| synthetic_crlf_pretty.xml | 2925.20 | 2016.92 | 1.450 | 1261.10 | 1150.47 | 1.096 |
| synthetic_token_whitespace_mix.xml | 1439.68 | 9248.32 | 0.156 | 967.24 | 8987.29 | 0.108 |
| synthetic_attr_count_mix.xml | 2849.51 | 6789.05 | 0.420 | 1067.51 | 1427.08 | 0.748 |

## Validated Pathology Regression Checks

2/2 passed. These fixtures are excluded from headline averages and stable external gates.
Detailed timings remain in `bench/results/latest.json` for regression analysis.
