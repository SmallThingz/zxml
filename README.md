# zxml

Low-latency XML parsing for Zig with comptime-generated DOM/streaming types, source-backed lazy materialization, and an in-tree benchmark/conformance harness.

![zig](https://img.shields.io/badge/zig-0.16.0-f7a41d?logo=zig&logoColor=111)
![format](https://img.shields.io/badge/format-xml-0f766e)

## Features

- Comptime-generated `Document`, `RawNode`, `Node`, attribute, and streaming parser types.
- Destructive `[]u8` parsing by default; immutable `[]const u8` parsing with `non_destructive = true`.
- Compact default DOM nodes: `parent + subtree_end + name_or_text` (16 bytes with the default `u32` index width).
- Node-only DOM construction: no separate open-element stack and no attribute-record array.
- Small documents stage nodes inline and allocate only the finished node slice; larger documents retain density-based reservation and safe growth.
- Optional last-child / previous-sibling / misc-node metadata physically disappears when disabled.
- Attributes are discovered lazily from source and compacted once in destructive documents.
- Text entity decoding is materialized lazily in source when it fits; immutable or expanding cases fall back to owned results.
- Explicit `validate_well_formedness` policy instead of runtime parser modes.
- Bounded permissive recovery for malformed structure; validated documents reject XML well-formedness errors.
- In-tree conformance suites and external parser benchmark harness.

## Performance

<!-- README_AUTO_SUMMARY:START -->

Source: `bench/results/latest.json` (`stable` profile).

Tested on `Linux 7.2.2-zen1-1-zen` with CPU `12th Gen Intel(R) Core(TM) i5-12450H` using Zig `0.16.0`.

### Parse Throughput (Average Across Fixtures)

```text
ours-permissive   │████████████████████│ 5210.11 MB/s (100.00%)
ours-validated    │█████████████░░░░░░░│ 3486.43 MB/s (66.92%)
stream-permissive │█████████████░░░░░░░│ 3458.04 MB/s (66.37%)
stream-validated  │██████░░░░░░░░░░░░░░│ 1577.43 MB/s (30.28%)
rapidxml          │████░░░░░░░░░░░░░░░░│ 1123.15 MB/s (21.56%)
pugixml           │████░░░░░░░░░░░░░░░░│ 1095.58 MB/s (21.03%)
```

### Full Stable Fixture Numbers (MB/s)

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

### Stable Gate Snapshot

| Profile | Passed | Rule |
|---|---:|---|
| `stable` | 37/37 | `ours-permissive >= max(pugixml, rapidxml)` |
<!-- README_AUTO_SUMMARY:END -->

A passing external-parser gate does not establish the original absolute throughput objectives; the validation report tracks both.

Current code-validation and benchmark status: [rewrite validation](bench/VALIDATION.md).

## Quick Start

```bash
zig build test
zig build conformance
zig build docs-check
zig build examples-check
zig build ship-check
zig build bench-compare # all 37 fixtures, fast developer sampling
```

Fastest/default parse (source may be lazily materialized by later queries):

```zig
const std = @import("std");
const zxml = @import("zxml");

pub fn main() !void {
    var src = "<root id='r'><child>text</child></root>".*;
    const options: zxml.ParseOptions = .{};
    var doc = try options.parse(std.heap.page_allocator, &src);
    defer doc.deinit();

    const root = doc.nodeAt(1).?;
    std.debug.print("{s} {s}\n", .{ root.nameSlice(), root.getAttributeValueRaw("id").? });
}
```

Immutable input is a different generated document type:

```zig
const options: zxml.ParseOptions = .{
    .non_destructive = true,
    .validate_well_formedness = true,
};
var doc = try options.parse(allocator, "<root/>");
defer doc.deinit();
```

## Generated API

The public configuration surface is `zxml.ParseOptions`. Options are compile-time inputs to the generated parser and document types.

```zig
const options: zxml.ParseOptions = .{
    .non_destructive = false,
    .validate_well_formedness = false,
    .store_last_child = false,
    .store_prev_sibling = false,
    .validate_xml_characters = true,
    .expand_dtd_entities = false,
    .max_entity_value_len = 4096,
    .drop_whitespace_text_nodes = true,
    .include_misc_nodes = false,
};

const Types = zxml.Types(options);
const Document = Types.Document;
const StreamingParser = Types.StreamingParser;
```

Useful root declarations include:

- `zxml.ParseOptions`
- `zxml.ParseError`
- `zxml.ParseDiagnostic`
- `zxml.NodeType`
- `zxml.MaxInputLen`
- `zxml.InvalidIndex`
- `zxml.Types(options)`
- `options.Document()`
- `options.parse(allocator, input)`

Parsing is a construction operation. Parser-owned growable storage and scratch are released after parsing; the returned document owns only its finished node slice and document-owned entity data:

```zig
var src = "<a/>".*;
const options: zxml.ParseOptions = .{};
var doc = try options.parse(allocator, &src);
defer doc.deinit();
```

`options.parseDiagnostic(allocator, input)` runs the same generated parser while returning a `ParseDiagnostic` on failure. `Document.init()`/`clear()` remain useful for empty document/query state, but documents are not reusable parser workspaces.

Index width is configurable at build time:

```bash
zig build test -Dintlen=u64
```

Supported widths are `u16`, `u32`, `u64`, and `usize`; the default is `u32`.

## DOM Layout And Navigation

The default raw node stores only:

```text
parent | subtree_end | name_or_text.start | name_or_text.end
```

With `u32` indexes this is 16 bytes. Element nodes store their tag-name span. Text nodes store their source span. Direct `subtree_end` makes subtree skipping and next-sibling traversal cheap without a parallel navigation sidecar.

`store_last_child` and `store_prev_sibling` add those indexes to the generated node layout only when requested. `include_misc_nodes` similarly adds the rich node-kind / misc-value fields only to document types that need comments, CDATA, declarations, processing instructions, or doctypes as DOM nodes.

## Destructive And Immutable Source Modes

Destructive mode is the default throughput path. Parsing itself records source spans; expensive value work remains lazy.

On first attribute traversal, zxml compacts the element's attribute syntax in place. Repeated traversal then consumes the compact representation instead of reparsing quoted XML syntax. Text entity decoding similarly caches a shrinking decoded value in source when possible.

`non_destructive = true` changes the generated input type to `[]const u8`. It never writes into the source and uses bounded raw traversal / owned decoding fallbacks instead.

Serialization understands materialized source state and emits XML syntax rather than the internal compact markers:

```zig
var out: std.Io.Writer.Allocating = .init(allocator);
defer out.deinit();
try doc.write(&out.writer);
```

## Value Ownership

Raw accessors return borrowed source slices:

```zig
const attr_raw = root.getAttributeValueRaw("id").?;
const text_raw = root.firstChild().?.valueRawSlice();
```

Decoded helpers return `SliceResult { value, owned }`. The result may borrow materialized source or own an allocation:

```zig
const attr = try root.getAttributeValue(allocator, "id") orelse return;
defer attr.free(allocator);
use(attr.value);

const inner = try root.innerText(allocator);
defer inner.free(allocator);
use(inner.value);
```

Call `free()` on the result rather than assuming decoding always allocates.

DTD/entity expansion is disabled by default. With `expand_dtd_entities = true`, internal parsed entity declarations are retained in a document-owned map for value materialization. `max_entity_value_len` bounds stored expanded values.

## Invalid XML Policy

The default generated parser is permissive but bounded. The DOM follows existing node parent links rather than building a separate open-element stack. Ordinary closing tags compare directly with the current parent. Mismatches use the parent chain to recover a matching ancestor; unmatched closes are ignored and remaining elements close implicitly at EOF.

The permissive DOM may reject a raw `>` inside a quoted attribute value, for example `<r value="a>b"/>`. Use `&gt;` in that value or select `validate_well_formedness = true` for the complete quoted-value grammar. This restriction is explicit; accepted fast-path tags keep the correct boundaries. No claim is made that the restricted syntax occurs in any particular percentage of XML documents.

`validate_well_formedness = true` generates the validating path: malformed tag structure, invalid attribute grammar, duplicate attributes, document-level grammar violations, and invalid entity/reference forms are reported as parse errors. `validate_xml_characters = false` may be used with validation when the caller has already established whole-buffer XML character validity.

Rare malformed input is allowed to fail in permissive mode; it must remain bounded and must not crash, hang, read out of bounds, or grow memory without limit.

## Streaming

Streaming uses the same generated validation policy and keeps its own ephemeral named open-element stack. `parseAvailable` expects a cumulative buffer: each call retains the same prefix and appends newly received bytes. Complete callbacks are not replayed when a later token is incomplete.

```zig
var stream = zxml.Types(options).StreamingParser.init(allocator);
defer stream.deinit();
_ = try stream.parseAvailable(buffer_so_far, &ctx, onNode);
try stream.finish();
```

Validated streaming rejects malformed/unclosed structure. Permissive streaming applies the same named-close recovery policy as the DOM and tolerates unfinished structure at final EOF where safe.

## Build And Validation

```bash
zig build test
zig build conformance
zig build tools -- run-conformance --suite bench/conformance/well_formedness_w3c_core.json
zig build bench-compare
```

Benchmark and conformance details are documented in [`bench/README.md`](./bench/README.md).
