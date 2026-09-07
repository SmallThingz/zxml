# zxml

Fast XML parsing for Zig with comptime-generated DOM and streaming types.

The default parser is destructive and permissive. Attributes and text stay source-backed and are materialized lazily; the DOM does not build an attribute array or a separate open-element stack.

## Quick start

```zig
const std = @import("std");
const zxml = @import("zxml");

pub fn main() !void {
    var source = "<root id='r'><child>text</child></root>".*;
    const options: zxml.ParseOptions = .{};

    var doc = try options.parse(std.heap.page_allocator, &source);
    defer doc.deinit();

    const root = doc.nodeAt(1).?;
    std.debug.print("{s} {s}\n", .{
        root.nameSlice(),
        root.getAttributeValueRaw("id").?,
    });
}
```

For strict XML structure validation:

```zig
const options: zxml.ParseOptions = .{
    .validate_well_formedness = true,
};
```

For immutable input:

```zig
const options: zxml.ParseOptions = .{
    .non_destructive = true,
    .validate_well_formedness = true,
};
```

`ParseOptions` generates the concrete `Document`, `Node`, `Attribute`, and `StreamingParser` types at compile time.

## DOM

With the default `u32` index width, a raw node is 12 bytes: parent index plus one source span. Subtree bounds and navigation are derived from preorder parent links unless optional navigation fields are requested.

Attributes are scanned lazily from the source. Destructive documents may compact decoded values in place; immutable documents use borrowed raw slices or owned decoded results. Optional previous-sibling, last-child, and miscellaneous-node metadata compile out when disabled.

Decoded value helpers return a result that may own memory. Always release it through the result:

```zig
const value = try root.getAttributeValue(allocator, "id") orelse return;
defer value.free(allocator);
use(value.value);
```

## Streaming

```zig
const T = zxml.Types(.{ .validate_well_formedness = true });
var parser = T.StreamingParser.init(allocator);
defer parser.deinit();

_ = try parser.parseAvailable(buffer_so_far, &ctx, onNode);
try parser.finish();
```

`parseAvailable` consumes a cumulative buffer. Save/restore and incomplete-token handling are supported for incremental parsing. Full-buffer `parse` uses additional fast paths but preserves the same event sequence and callback semantics.

## Invalid input

`validate_well_formedness = true` rejects malformed tags, duplicate attributes, document-level grammar errors, and invalid references.

The default permissive DOM favors bounded common-case parsing. It may reject a raw `>` inside a quoted attribute value such as `<r value="a>b"/>`; use `&gt;` or enable well-formedness validation for the complete quoted-value grammar. Malformed permissive input may fail, but must remain bounded and safe.

## Performance

<!-- README_AUTO_SUMMARY:START -->

Source: `bench/results/latest.json` (`stable` profile).

Tested on `Linux 7.2.2-zen1-1-zen` with CPU `12th Gen Intel(R) Core(TM) i5-12450H` using Zig `0.16.0`.

### Parse Throughput (Average Across Fixtures)

```text
stream-permissive │████████████████████│ 10244.76 MiB/s (100.00%)
stream-validated  │█████████████████░░░│ 8495.97 MiB/s (82.93%)
ours-permissive   │██████████░░░░░░░░░░│ 4963.01 MiB/s (48.44%)
ours-validated    │███████░░░░░░░░░░░░░│ 3434.82 MiB/s (33.53%)
rapidxml          │██░░░░░░░░░░░░░░░░░░│ 1044.55 MiB/s (10.20%)
pugixml           │██░░░░░░░░░░░░░░░░░░│ 1020.56 MiB/s (9.96%)
```

### Stable Gate Snapshot

| Profile | Passed | Rule |
|---|---:|---|
| `stable` | 37/37 | `ours-permissive >= max(pugixml, rapidxml)` |
<!-- README_AUTO_SUMMARY:END -->

The full per-fixture table, methodology, and benchmark commands are in [`bench/README.md`](./bench/README.md).

## Conformance

Current in-tree conformance result: **112/112 PASS, 0 FAIL** across 12 suites.

```bash
zig build conformance
```

Direct report-only mode prints pass/fail counts without turning a failed case into a tool error:

```bash
zig build tools -- run-conformance
```

Add `--strict` when a nonzero exit is required.

## Build and test

```bash
zig build test
zig build conformance
zig build docs-check
zig build examples-check
zig build ship-check
zig build bench-compare
```

Index width can be selected at build time with `-Dintlen=u16|u32|u64|usize`; the default is `u32`.
