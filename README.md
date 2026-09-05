# zxml

Low-latency XML DOM parsing for Zig with comptime-specialized parse modes and an in-tree benchmark/conformance harness.

![zig](https://img.shields.io/badge/zig-0.16.0-f7a41d?logo=zig&logoColor=111)
![format](https://img.shields.io/badge/format-xml-0f766e)

## Features

- Single-pass XML parsing over `[]const u8` input.
- DOM layout backed by a contiguous node array, with element attributes recovered lazily from source-byte spans.
- Comptime parse configuration via `Document.parse(input, .{ ... })`.
- Two parser profiles: `strict` and `turbo`.
- Raw borrowed accessors plus allocator-backed decoded helpers for text and attribute values.
- In-tree conformance suites and external parser benchmark harness.

## Performance

<!-- README_AUTO_SUMMARY:START -->

Source: `bench/results/latest.json` (`stable` profile).

Tested on `Linux 7.2.2-zen1-1-zen` with CPU `12th Gen Intel(R) Core(TM) i5-12450H` using Zig `0.16.0`.

### Parse Throughput (Average Across Fixtures)

```text
ours-turbo    │████████████████████│ 3179.07 MB/s (100.00%)
ours-strict   │████████████████░░░░│ 2566.88 MB/s (80.74%)
stream-turbo  │███████████████░░░░░│ 2451.06 MB/s (77.10%)
stream-strict │███████░░░░░░░░░░░░░│ 1109.75 MB/s (34.91%)
rapidxml      │█████░░░░░░░░░░░░░░░│ 866.81 MB/s (27.27%)
pugixml       │█████░░░░░░░░░░░░░░░│ 831.77 MB/s (26.16%)
```

### Stable Gate Snapshot

| Profile | Passed | Rule |
|---|---:|---|
| `stable` | 37/37 | `ours-turbo >= max(pugixml, rapidxml)` |
<!-- README_AUTO_SUMMARY:END -->

## Quick Start

```bash
zig build test
zig build conformance
zig build docs-check
zig build examples-check
zig build ship-check
zig build bench-compare
```

Minimal parse:

```zig
const std = @import("std");
const zxml = @import("zxml");

pub fn main() !void {
    const src = "<root id='r'><child>text</child></root>";
    const options: zxml.ParseOptions = .{ .mode = .strict, .validate_closing_tags = true };
    var doc = try options.parse(std.heap.page_allocator, src);
    defer doc.deinit();

    const root = doc.nodeAt(1).?;
    std.debug.print("{s} {s}\n", .{ root.nameSlice(), root.getAttributeValueRaw("id").? });
}
```

## Library API

- `zxml.ParseOptions`
- `zxml.ParseMode`
- `zxml.ParseError`
- `zxml.IndexInt`
- `zxml.MaxInputLen`
- `options.parse(allocator, input)`
- `options.Document()`
- `zxml.Types(options).Document` / `.Node` / `.Attribute` / `.StreamingParser`

```zig
const options: zxml.ParseOptions = .{};
const Document = options.Document();
const StreamingParser = zxml.Types(options).StreamingParser;
```

Index width is configurable at build time, following the same config-module pattern as `htmlparser`:

```bash
zig build test -Dintlen=u64
```

Supported widths are `u16`, `u32`, `u64`, and `usize`. The default is `u32`.

`ParseOptions.parse` returns an initialized document; `Document.parse` remains available for document reuse:

```zig
const options: zxml.ParseOptions = .{
    .mode = .turbo,
    .validate_closing_tags = false,
    .expand_dtd_entities = false,
    .max_entity_value_len = 4096,
    .drop_whitespace_text_nodes = true,
    .include_misc_nodes = true,
};
var doc = try options.parse(allocator, input);
```

Parsing is always non-destructive and the original input is always `[]const u8`.

Serialize without reparsing:

```zig
var out: std.Io.Writer.Allocating = .init(allocator);
defer out.deinit();
try doc.write(&out.writer);
```

Incremental streaming keeps parser state and resumes from saved offsets:

```zig
var stream = zxml.Types(options).StreamingParser.init(allocator);
defer stream.deinit();
_ = try stream.parseAvailable(buffer_so_far, &ctx, onNode);
try stream.finish();
```

`parseAvailable` expects a cumulative buffer: each call keeps the same prefix and
adds newly received bytes. It commits only complete tokens, so callbacks for
already-completed markup are not replayed when a later token needs more data. A
`false` return means the final token is incomplete; pass a longer cumulative
buffer and call again. `finish` reports a still-incomplete token and also applies
`require_closed_elements_on_eof`. Callback-based subtree skipping is resumable
across the same chunk boundaries.

Use raw accessors when you want borrowed source slices:

```zig
const attr_raw = root.getAttributeValueRaw("id").?;
const text_raw = root.firstChild().?.valueRawSlice();
```

Elements store their raw attribute region as a half-open byte span into `doc.source`; attributes are iterated lazily and are not kept in a persistent document-wide attribute array. Low-level `RawNode.attributeSpan()` values are source-byte offsets, not attribute indices.

Use allocator-backed helpers when you want decoded values without mutating the source:

```zig
const attr = try root.getAttributeValue(std.heap.page_allocator, "id") orelse return;
defer std.heap.page_allocator.free(attr);

const inner = try root.innerText(std.heap.page_allocator);
defer std.heap.page_allocator.free(inner);
```

DTD/entity expansion is disabled by default. When `expand_dtd_entities = true`, zxml parses internal `<!ENTITY ...>` declarations from the document doctype into a document-owned hash map and uses that map during decoded value access. `max_entity_value_len` caps each stored expanded entity value.

`turbo` keeps DOM construction but drops expensive validation work by default. `strict` enforces stronger well-formedness checks and is the correctness-first profile.

## Build And Validation

```bash
zig build test
zig build conformance
zig build tools -- run-conformance --suite bench/conformance/well_formedness_w3c_core.json
zig build bench-compare
```

Benchmark and conformance details are documented in [`bench/README.md`](./bench/README.md).
