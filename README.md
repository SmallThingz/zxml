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
stream-permissive │████████████████████│ 8884.94 MB/s (100.00%)
stream-validated  │████████████████░░░░│ 6982.08 MB/s (78.58%)
ours-permissive   │████████████░░░░░░░░│ 5128.30 MB/s (57.72%)
ours-validated    │████████░░░░░░░░░░░░│ 3439.70 MB/s (38.71%)
rapidxml          │███░░░░░░░░░░░░░░░░░│ 1118.92 MB/s (12.59%)
pugixml           │██░░░░░░░░░░░░░░░░░░│ 1087.40 MB/s (12.24%)
```

### Full Stable Fixture Numbers (MB/s)

| Fixture | ours-permissive | ours-validated | stream-permissive | stream-validated | pugixml | rapidxml |
|---|---:|---:|---:|---:|---:|---:|
| `note.xml` | 2876.74 | 1671.65 | 3282.15 | 1392.80 | 977.97 | 1773.58 |
| `sitemaps.xml` | 4223.02 | 2128.56 | 3720.77 | 1802.19 | 2067.23 | 2101.88 |
| `plant_catalog.xml` | 3624.58 | 1866.88 | 3215.44 | 1529.97 | 1574.25 | 1680.87 |
| `cd_catalog.xml` | 3255.46 | 1736.88 | 2810.06 | 1407.95 | 1503.05 | 1656.73 |
| `hnrss.xml` | 9970.37 | 5510.29 | 8570.10 | 4432.99 | 2984.76 | 2722.01 |
| `xkcd_rss.xml` | 8670.15 | 4106.10 | 8792.88 | 3439.53 | 2530.09 | 2650.42 |
| `bbc_world.xml` | 5957.65 | 3459.30 | 5433.30 | 3144.30 | 2628.28 | 2561.22 |
| `arxiv_cs.xml` | 8451.59 | 4158.79 | 10686.52 | 4577.96 | 2733.14 | 1897.48 |
| `ecb_usd.xml` | 6813.26 | 3207.87 | 6032.57 | 2859.11 | 2705.87 | 2751.16 |
| `tree.xml` | 2977.17 | 1465.52 | 3109.66 | 1368.22 | 1275.77 | 2105.11 |
| `character.xml` | 3498.75 | 1477.28 | 3293.65 | 1437.93 | 1181.24 | 2132.49 |
| `transitions.xml` | 3726.03 | - | 3408.92 | - | 1472.48 | 2268.62 |
| `xgconsole.xml` | 6011.79 | 2012.75 | 6078.22 | 1334.16 | 1895.04 | 2492.48 |
| `weekly_utf8.xml` | 3828.66 | 1272.68 | 3160.34 | 691.95 | 2248.38 | 2435.64 |
| `pugixml_large.xml` | 2567.86 | 1489.42 | 2113.79 | 1677.26 | 481.54 | 308.00 |
| `synthetic_flat_attrs.xml` | 6787.72 | 1329.41 | 8721.19 | 1235.85 | 467.18 | 351.47 |
| `synthetic_deep_tree.xml` | 1905.42 | 1163.96 | 1768.84 | 1113.43 | 1283.16 | 777.19 |
| `synthetic_entities.xml` | 10451.86 | 10244.35 | 31495.76 | 31127.85 | 919.99 | 930.96 |
| `synthetic_cdata_mix.xml` | 2361.87 | 1783.06 | 2889.12 | 1824.68 | 690.78 | 525.21 |
| `synthetic_wide_siblings.xml` | 1552.51 | 1129.72 | 2251.36 | 1126.05 | 430.08 | 316.79 |
| `synthetic_namespace_mix.xml` | 3785.66 | 1452.84 | 4411.76 | 1484.34 | 700.09 | 577.30 |
| `synthetic_long_names.xml` | 6430.58 | 3271.51 | 6204.73 | 2596.65 | 1392.15 | 1654.52 |
| `synthetic_self_closing_swarm.xml` | 4670.28 | 1157.32 | 5471.68 | 1354.86 | 574.86 | 460.87 |
| `synthetic_mixed_content.xml` | 2306.95 | 1362.48 | 3130.30 | 1392.69 | 524.03 | 396.20 |
| `synthetic_small_records.xml` | 1916.97 | 1378.95 | 2783.71 | 1344.09 | 425.77 | 301.11 |
| `synthetic_tiny_empty.xml` | 1732.05 | 1720.05 | 7416.80 | 7394.28 | 192.12 | 120.16 |
| `synthetic_tiny_text.xml` | 1763.30 | 1749.24 | 15198.86 | 15133.66 | 181.29 | 123.27 |
| `synthetic_one_attr.xml` | 2990.51 | 2960.46 | 10505.99 | 10437.36 | 236.77 | 161.82 |
| `synthetic_two_attr.xml` | 5461.72 | 5449.06 | 16997.02 | 16705.59 | 290.06 | 213.50 |
| `synthetic_attrs4.xml` | 8574.21 | 8540.75 | 21832.56 | 21886.81 | 329.26 | 253.57 |
| `synthetic_attrs8.xml` | 12609.67 | 12372.73 | 25994.73 | 26089.28 | 350.26 | 266.27 |
| `synthetic_single_quotes.xml` | 9786.17 | 9816.82 | 23297.40 | 23385.45 | 489.95 | 375.99 |
| `synthetic_unicode_names.xml` | 8592.19 | 8489.89 | 29237.23 | 29101.26 | 642.70 | 544.00 |
| `synthetic_pretty_indented.xml` | 1932.42 | 1346.93 | 2271.95 | 1346.08 | 497.21 | 400.80 |
| `synthetic_crlf_pretty.xml` | 2031.23 | 1222.65 | 2932.27 | 1415.76 | 524.77 | 437.24 |
| `synthetic_token_whitespace_mix.xml` | 9022.22 | 8904.10 | 21260.64 | 21278.67 | 437.93 | 363.87 |
| `synthetic_attr_count_mix.xml` | 6628.53 | 1419.09 | 8960.68 | 1484.03 | 394.33 | 310.12 |

### Stable Gate Snapshot

| Profile | Passed | Rule |
|---|---:|---|
| `stable` | 37/37 | `ours-permissive >= max(pugixml, rapidxml)` |
<!-- README_AUTO_SUMMARY:END -->

A passing external-parser gate does not establish the original absolute throughput objectives; the validation report tracks both.

Current code-validation and benchmark status: [rewrite validation](bench/VALIDATION.md).

## XML Compliance / Conformance

The repository carries 12 conformance suites covering well-formedness, error handling,
entities/text, cross-mode behavior, W3C-style cases, XML-DSig integrity, HL7/ISO 20022,
XSD-core checks, Schematron-core business rules, and OWASP/NIST security cases.

Current suite result: **112/112 PASS, 0 FAIL**.

| Suite | Pass | Fail |
|---|---:|---:|
| business_rules_schematron_core | 8 | 0 |
| cross_mode_entities_text | 13 | 0 |
| cross_mode_error_matrix | 23 | 0 |
| cross_mode_well_formed | 13 | 0 |
| entities_and_text | 4 | 0 |
| error_handling | 5 | 0 |
| industry_hl7_iso20022_core | 8 | 0 |
| integrity_xml_dsig_core | 6 | 0 |
| schema_validation_xsd_core | 9 | 0 |
| security_owasp_nist_core | 9 | 0 |
| well_formed_core | 3 | 0 |
| well_formedness_w3c_core | 11 | 0 |
| **Total** | **112** | **0** |

`zig build conformance` is strict and fails CI/release checks if any case fails.
`zig build tools -- run-conformance` is report-only: it prints per-suite and aggregate
`PASS`/`FAIL` counts without converting a failed compliance case into a tool error.
Use `--strict` with the direct tool when a nonzero exit is required.

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
