# fastxml

Low-latency XML DOM parsing for Zig with comptime-specialized parse modes and an in-tree benchmark/conformance harness.

![zig](https://img.shields.io/badge/zig-0.15.2-f7a41d?logo=zig&logoColor=111)
![format](https://img.shields.io/badge/format-xml-0f766e)

## Features

- Single-pass XML parsing over `[]const u8` input.
- DOM layout backed by contiguous node/attribute arrays and span slices into source bytes.
- Comptime parse configuration via `Document.parse(input, .{ ... })`.
- Two parser profiles: `strict` and `turbo`.
- Raw borrowed accessors plus allocator-backed decoded helpers for text and attribute values.
- In-tree conformance suites and external parser benchmark harness.

## Performance

<!-- README_AUTO_SUMMARY:START -->

Source: `bench/results/latest.json` (`stable` profile).

### Parse Throughput (Average Across Fixtures)

```text
ours-turbo  │████████████████████│ 2935.36 MB/s (100.00%)
ours-strict │████████████████████│ 2911.18 MB/s (99.18%)
pugixml     │█████████░░░░░░░░░░░│ 1371.81 MB/s (46.73%)
rapidxml    │█████████░░░░░░░░░░░│ 1364.28 MB/s (46.48%)
```

### Stable Gate Snapshot

| Profile | Passed | Rule |
|---|---:|---|
| `stable` | 25/25 | `ours-turbo >= max(pugixml, rapidxml)` |
<!-- README_AUTO_SUMMARY:END -->

## Quick Start

```bash
zig build test
zig build conformance
zig build bench-compare
```

Minimal parse:

```zig
const std = @import("std");
const fastxml = @import("fastxml");
const options: fastxml.ParseOptions = .{};
const Document = fastxml.Types(options).Document;

pub fn main() !void {
    const src = "<root id='r'><child>text</child></root>";

    var doc = Document.init(std.heap.page_allocator);
    defer doc.deinit();

    try doc.parse(&src, .{
        .mode = .strict,
        .validate_closing_tags = true,
    });

    const root = doc.nodeAt(1).?;
    std.debug.print("{s} {s}\n", .{ root.nameSlice(), root.getAttributeValueRaw("id").? });
}
```

## Library API

- `fastxml.ParseOptions`
- `fastxml.ParseMode`
- `fastxml.ParseError`
- `fastxml.ParseInt`
- `fastxml.MaxParseLen`
- `fastxml.Types(options).Document`
- `fastxml.Types(options).Node`
- `fastxml.Types(options).Attribute`

```zig
const options: fastxml.ParseOptions = .{};
const types = fastxml.Types(options);
const Document = types.Document;
const Node = types.Node;
const Attribute = types.Attribute;
```

Index width is configurable at build time, following the same config-module pattern as `htmlparser`:

```bash
zig build test -Dintlen=u64
```

Supported widths are `u16`, `u32`, `u64`, and `usize`. The default is `u32`.

`Document.parse` is comptime-specialized:

```zig
try doc.parse(input, .{
    .mode = .turbo,
    .validate_closing_tags = false,
    .expand_dtd_entities = false,
    .max_entity_value_len = 4096,
    .drop_whitespace_text_nodes = true,
    .include_misc_nodes = true,
});
```

Parsing is always non-destructive and the original input is always `[]const u8`.

Use raw accessors when you want borrowed source slices:

```zig
const attr_raw = root.getAttributeValueRaw("id").?;
const text_raw = root.firstChild().?.valueRawSlice();
```

Use allocator-backed helpers when you want decoded values without mutating the source:

```zig
const attr = try root.getAttributeValue(std.heap.page_allocator, "id") orelse return;
defer std.heap.page_allocator.free(attr);

const inner = try root.innerText(std.heap.page_allocator);
defer std.heap.page_allocator.free(inner);
```

DTD/entity expansion is disabled by default. When `expand_dtd_entities = true`, fastxml parses internal `<!ENTITY ...>` declarations from the document doctype into a document-owned hash map and uses that map during decoded value access. `max_entity_value_len` caps each stored expanded entity value.

`turbo` keeps DOM construction but drops expensive validation work by default. `strict` enforces stronger well-formedness checks and is the correctness-first profile.

## Build And Validation

```bash
zig build test
zig build conformance
zig build tools -- run-conformance --suite bench/conformance/well_formedness_w3c_core.json
zig build bench-compare
```

Benchmark and conformance details are documented in [`bench/README.md`](./bench/README.md).
