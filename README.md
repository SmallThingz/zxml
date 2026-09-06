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
ours-permissive   │████████████████████│ 3520.30 MB/s (100.00%)
stream-permissive │███████████████████░│ 3336.91 MB/s (94.79%)
ours-validated    │█████████░░░░░░░░░░░│ 1616.20 MB/s (45.91%)
stream-validated  │█████████░░░░░░░░░░░│ 1595.09 MB/s (45.31%)
rapidxml          │██████░░░░░░░░░░░░░░│ 1138.79 MB/s (32.35%)
pugixml           │██████░░░░░░░░░░░░░░│ 1109.99 MB/s (31.53%)
```

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
zig build bench-compare
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
