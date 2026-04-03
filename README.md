# fastxml

Low-latency in-situ XML DOM parsing for Zig with comptime-specialized parse modes and an in-tree benchmark/conformance harness.

![zig](https://img.shields.io/badge/zig-0.15.2-f7a41d?logo=zig&logoColor=111)
![format](https://img.shields.io/badge/format-xml-0f766e)

## Features

- Single-pass in-situ XML parsing over mutable input.
- DOM layout backed by contiguous node/attribute arrays and span slices into source bytes.
- Comptime parse configuration via `Document.parse(input, .{ ... })`.
- Two parser profiles: `strict` and `turbo`.
- Optional parse-time entity decode and control over pure-whitespace text node creation.
- In-tree conformance suites and external parser benchmark harness.

## Performance

<!-- README_AUTO_SUMMARY:START -->

Source: `bench/results/latest.json` (`stable` profile).

### Parse Throughput (Average Across Fixtures)

```text
ours-turbo  │████████████████████│ 2670.53 MB/s (100.00%)
ours-strict │███████████████████░│ 2476.76 MB/s (92.74%)
pugixml     │██████████░░░░░░░░░░│ 1317.41 MB/s (49.33%)
rapidxml    │██████████░░░░░░░░░░│ 1283.34 MB/s (48.06%)
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
    var src = "<root id='r'><child>text</child></root>".*;

    var doc = Document.init(std.heap.page_allocator);
    defer doc.deinit();

    try doc.parse(&src, .{
        .mode = .strict,
        .validate_closing_tags = true,
    });

    const root = doc.nodeAt(1).?;
    std.debug.print("{s} {s}\n", .{ root.nameSlice(), root.getAttributeValue("id").? });
}
```

## Library API

- `fastxml.ParseOptions`
- `fastxml.ParseMode`
- `fastxml.ParseError`
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

`Document.parse` is comptime-specialized:

```zig
try doc.parse(input, .{
    .mode = .turbo,
    .validate_closing_tags = false,
    .decode_entities_on_parse = false,
    .drop_whitespace_text_nodes = true,
    .include_misc_nodes = true,
});
```

`turbo` keeps DOM construction but drops expensive validation work by default. `strict` enforces stronger well-formedness checks and is the correctness-first profile.

## Build And Validation

```bash
zig build test
zig build conformance
zig build tools -- run-conformance --suite bench/conformance/well_formedness_w3c_core.json
zig build bench-compare
```

Benchmark and conformance details are documented in [`bench/README.md`](./bench/README.md).
