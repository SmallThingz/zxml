const std = @import("std");
const builtin = @import("builtin");
const common = @import("common.zig");
const attrs_mod = @import("attr.zig");
const parser = @import("parser.zig");
const scanner = @import("scanner.zig");
const entities = @import("entities.zig");
const tables = @import("tables.zig");

pub const IndexInt = common.IndexInt;
pub const InvalidIndex: IndexInt = common.InvalidIndex;
pub const Span = common.Span;
pub const RawAttribute = attrs_mod.RawAttribute;

const cold_text_section = switch (builtin.os.tag) {
    .macos, .ios, .tvos, .watchos, .visionos => "__TEXT,__text",
    else => ".text.unlikely.zxml",
};

const xml_scan_vector_len: comptime_int = switch (builtin.cpu.arch) {
    .x86, .x86_64 => if (std.Target.x86.featureSetHas(builtin.cpu.features, .avx2)) 32 else 16,
    else => 16,
};

pub const ParseOptions = struct {
    /// Destructive parsing is the throughput-oriented default. It permits lazy
    /// query-time materialization to cache decoded/compacted data in source.
    non_destructive: bool = false,
    /// Enables expensive XML well-formedness validation. Fast mode is bounded
    /// and permissive; malformed structure is recovered without crashing.
    validate_well_formedness: bool = false,
    /// Persist direct last-child indexes. Disabled fields are zero-sized.
    store_last_child: bool = false,
    /// Persist previous-sibling indexes. Disabled fields are zero-sized.
    store_prev_sibling: bool = false,
    /// With `validate_well_formedness`, validates XML character ranges and UTF-8
    /// before full-buffer validated parsing. Incremental streaming still validates
    /// UTF-8 boundaries required for safe chunking.
    validate_xml_characters: bool = true,
    expand_dtd_entities: bool = false,
    max_entity_value_len: usize = 4096,
    drop_whitespace_text_nodes: bool = true,
    include_misc_nodes: bool = false,

    /// Accepted source type for this generated parser/document.
    pub fn Input(comptime options: @This()) type {
        return if (options.non_destructive) []const u8 else []u8;
    }

    /// Parses `input` and returns an owned document for this option set.
    pub fn parse(comptime options: @This(), allocator: std.mem.Allocator, input: options.Input()) ParseError!options.Document() {
        return parser.parse(options, allocator, input);
    }

    /// Parses only to obtain a diagnostic. Successful parses are immediately
    /// released; failures report the parser cursor without storing it in Document.
    pub fn parseDiagnostic(comptime options: @This(), allocator: std.mem.Allocator, input: options.Input()) ?ParseDiagnostic {
        return parser.parseDiagnostic(options, allocator, input);
    }

    /// Returns the document type for this option set.
    pub fn Document(comptime options: @This()) type {
        return Types(options).Document;
    }
};

pub fn Types(comptime options: ParseOptions) type {
    const Self = @This();
    return struct {
        pub const IndexInt = Self.IndexInt;
        pub const Span = Self.Span;
        pub const RawAttribute = Self.RawAttribute;
        pub const RawAttributeIterator = attrs_mod.RawIterator(options.validate_well_formedness);
        pub const RawNode = GetRawNode(options);
        pub const Attribute = GetAttribute(options);
        pub const AttributeIterator = GetAttributeIterator(options);
        pub const Node = GetNode(options);
        pub const Document = GetDocument(options);
    };
}

pub const ParseError = error{
    OutOfMemory,
    InputTooLarge,
    UnexpectedEndOfData,
    ExpectedLt,
    ExpectedGt,
    ExpectedElementName,
    ExpectedAttributeName,
    DuplicateAttribute,
    ExpectedEq,
    ExpectedQuote,
    InvalidAttributeValue,
    InvalidComment,
    InvalidCharacterData,
    InvalidXmlCharacter,
    ExpectedDocumentElement,
    MultipleDocumentElements,
    InvalidDocumentContent,
    InvalidDoctype,
    InvalidDeclaration,
    ExpectedPiTarget,
    InvalidClosingTagName,
    InvalidNumericCharacterEntity,
    UnterminatedEntity,
    EntityValueTooLarge,
    RecursiveEntity,
};

pub fn validateXmlReferences(
    value: []const u8,
    allow_trailing_partial: bool,
    doctype_value: ?[]const u8,
    require_declared_entities: bool,
) ParseError!void {
    return validateXmlReferencesInContext(value, allow_trailing_partial, doctype_value, require_declared_entities, .content);
}

pub fn validateXmlAttributeReferences(
    value: []const u8,
    doctype_value: ?[]const u8,
    require_declared_entities: bool,
) ParseError!void {
    return validateXmlReferencesInContext(value, false, doctype_value, require_declared_entities, .attribute);
}

pub fn validateXmlReferencesAlloc(
    allocator: std.mem.Allocator,
    value: []const u8,
    allow_trailing_partial: bool,
    doctype_value: ?[]const u8,
    require_declared_entities: bool,
) linksection(cold_text_section) ParseError!void {
    return validateXmlReferencesInContextAlloc(allocator, value, allow_trailing_partial, doctype_value, require_declared_entities, .content, null);
}

pub fn validateXmlAttributeReferencesAlloc(
    allocator: std.mem.Allocator,
    value: []const u8,
    doctype_value: ?[]const u8,
    require_declared_entities: bool,
    previous_validated_value: ?[]const u8,
) ParseError!void {
    return validateXmlReferencesInContextAlloc(allocator, value, false, doctype_value, require_declared_entities, .attribute, previous_validated_value);
}

const XmlReferenceContext = enum { content, attribute };
const GeneralEntityKind = enum { internal, external_parsed, unparsed };
const ParameterEntityKind = enum { internal, external };

const ParameterEntityDecl = struct {
    kind: ParameterEntityKind,
    replacement: ?[]u8 = null,
};

const ParameterEntityCatalog = struct {
    allocator: std.mem.Allocator,
    map: std.StringHashMap(ParameterEntityDecl),

    fn init(allocator: std.mem.Allocator) ParameterEntityCatalog {
        return .{ .allocator = allocator, .map = std.StringHashMap(ParameterEntityDecl).init(allocator) };
    }

    fn deinit(self: *ParameterEntityCatalog) void {
        var it = self.map.iterator();
        while (it.next()) |entry| {
            if (entry.value_ptr.replacement) |replacement| self.allocator.free(replacement);
        }
        self.map.deinit();
    }
};

const GeneralEntityDecl = struct {
    kind: GeneralEntityKind,
    replacement: ?[]u8 = null,
};

const GeneralEntityCatalog = struct {
    allocator: std.mem.Allocator,
    map: std.StringHashMap(GeneralEntityDecl),

    fn init(allocator: std.mem.Allocator) GeneralEntityCatalog {
        return .{ .allocator = allocator, .map = std.StringHashMap(GeneralEntityDecl).init(allocator) };
    }

    fn deinit(self: *GeneralEntityCatalog) void {
        var it = self.map.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            if (entry.value_ptr.replacement) |replacement| self.allocator.free(replacement);
        }
        self.map.deinit();
    }
};

const EntityValidationState = enum { visiting, done };
const EntityValidationFrame = struct {
    name: []const u8,
    replacement: []const u8,
    offset: usize = 0,
};

fn validateXmlReferencesInContext(
    value: []const u8,
    allow_trailing_partial: bool,
    doctype_value: ?[]const u8,
    require_declared_entities: bool,
    context: XmlReferenceContext,
) ParseError!void {
    var search_from: usize = 0;
    while (std.mem.indexOfScalarPos(u8, value, search_from, '&')) |amp| {
        const semi = std.mem.indexOfScalarPos(u8, value, amp + 1, ';') orelse {
            if (allow_trailing_partial) return error.UnexpectedEndOfData;
            return error.UnterminatedEntity;
        };
        const body = value[amp + 1 .. semi];
        if (!isValidXmlReferenceBody(body)) return error.InvalidNumericCharacterEntity;
        if (body[0] != '#' and !isPredefinedEntityName(body)) {
            const kind = if (doctype_value) |doctype| try doctypeGeneralEntityKind(doctype, body) else null;
            if (kind) |entity_kind| switch (entity_kind) {
                .internal => {},
                .external_parsed => if (context == .attribute) return error.InvalidAttributeValue,
                .unparsed => return error.InvalidNumericCharacterEntity,
            } else if (require_declared_entities) {
                return error.InvalidNumericCharacterEntity;
            }
        }
        search_from = semi + 1;
    }
}

fn validateXmlReferencesInContextAlloc(
    allocator: std.mem.Allocator,
    value: []const u8,
    allow_trailing_partial: bool,
    doctype_value: ?[]const u8,
    require_declared_entities: bool,
    context: XmlReferenceContext,
    previous_validated_value: ?[]const u8,
) ParseError!void {
    // Without a DTD, the syntax-only scan is the whole common path for
    // predefined and numeric references. Keep it compact and allocation-free.
    if (doctype_value == null) {
        if (!try validateXmlReferenceSyntax(value, allow_trailing_partial)) return;
        if (require_declared_entities) return error.InvalidNumericCharacterEntity;
        return;
    }

    return validateXmlReferencesWithDoctypeAlloc(
        allocator,
        value,
        allow_trailing_partial,
        doctype_value.?,
        require_declared_entities,
        context,
        previous_validated_value,
    );
}

/// DTD-aware reference validation is intentionally out of line. Most validated XML
/// never declares custom entities, so keeping this larger path separate avoids
/// perturbing the common predefined/numeric reference scanner.
noinline fn validateXmlReferencesWithDoctypeAlloc(
    allocator: std.mem.Allocator,
    value: []const u8,
    allow_trailing_partial: bool,
    doctype_value: []const u8,
    require_declared_entities: bool,
    context: XmlReferenceContext,
    previous_validated_value: ?[]const u8,
) ParseError!void {
    if (previous_validated_value) |previous| {
        if (previous.len == value.len and std.mem.eql(u8, previous, value)) return;
    }
    // Parse reference syntax and validate custom entities in one pass. The old
    // path first scanned every reference for syntax, then rescanned the whole
    // value to validate custom names. Build the DTD catalog lazily on the first
    // custom reference so DTDs that use only predefined/numeric references do
    // not pay catalog construction cost.
    var catalog = GeneralEntityCatalog.init(allocator);
    defer catalog.deinit();
    var catalog_ready = false;

    var states = std.StringHashMap(EntityValidationState).init(allocator);
    defer states.deinit();
    var frames = std.ArrayList(EntityValidationFrame).empty;
    defer frames.deinit(allocator);

    var last_custom_name: ?[]const u8 = null;
    var search_from: usize = 0;
    while (search_from < value.len) {
        // Dense entity text often has only one or two ordinary bytes between
        // references. Peel those cases before calling the general byte search,
        // whose setup cost dominates at such short distances.
        const amp = if (value[search_from] == '&')
            search_from
        else if (search_from + 1 < value.len and value[search_from + 1] == '&')
            search_from + 1
        else if (search_from + 2 < value.len)
            std.mem.indexOfScalarPos(u8, value, search_from + 2, '&') orelse break
        else
            break;
        // Once a custom name has been fully validated against the immutable DTD,
        // identical following references need no delimiter search, name check,
        // or hash-table lookup.
        if (last_custom_name) |last_name| {
            const semi = amp + 1 + last_name.len;
            if (semi < value.len and value[semi] == ';') {
                const same_name = if (last_name.len == 1)
                    value[amp + 1] == last_name[0]
                else
                    std.mem.eql(u8, value[amp + 1 .. semi], last_name);
                if (same_name) {
                    search_from = semi + 1;
                    continue;
                }
            }
        }

        const semi = std.mem.indexOfScalarPos(u8, value, amp + 1, ';') orelse {
            if (allow_trailing_partial) return error.UnexpectedEndOfData;
            return error.UnterminatedEntity;
        };
        const body = value[amp + 1 .. semi];
        if (body.len == 0) return error.InvalidNumericCharacterEntity;
        if (body[0] == '#') {
            if (xmlNumericReferenceValue(body) == null) return error.InvalidNumericCharacterEntity;
        } else if (!isPredefinedEntityName(body)) {
            if (!isValidXmlName(body)) return error.InvalidNumericCharacterEntity;
            if (!catalog_ready) {
                try buildGeneralEntityCatalog(&catalog, doctype_value);
                catalog_ready = true;
            }
            try validateGeneralEntityUse(&catalog, &states, &frames, body, require_declared_entities, context);
            last_custom_name = body;
        }
        search_from = semi + 1;
    }
}

inline fn predefinedReferenceEnd(value: []const u8, amp: usize) ?usize {
    const remaining = value.len - amp;
    if (remaining >= 4) {
        const key4 = std.mem.readInt(u32, value[amp..][0..4], .little);
        if (key4 == 0x3b746c26 or key4 == 0x3b746726) return amp + 4; // &lt; &gt;
    }
    if (remaining >= 5 and std.mem.readInt(u40, value[amp..][0..5], .little) == 0x3b706d6126) return amp + 5; // &amp;
    if (remaining >= 6) {
        const key6 = std.mem.readInt(u48, value[amp..][0..6], .little);
        if (key6 == 0x3b736f706126 or key6 == 0x3b746f757126) return amp + 6; // &apos; &quot;
    }
    return null;
}

fn validateXmlReferenceSyntax(value: []const u8, allow_trailing_partial: bool) ParseError!bool {
    var has_custom_reference = false;
    var search_from: usize = 0;
    while (std.mem.indexOfScalarPos(u8, value, search_from, '&')) |amp| {
        if (predefinedReferenceEnd(value, amp)) |end| {
            search_from = end;
            continue;
        }
        if (amp + 1 < value.len and value[amp + 1] == '#') {
            var i = amp + 2;
            var base: u32 = 10;
            if (i < value.len and value[i] == 'x') {
                base = 16;
                i += 1;
            }
            if (i >= value.len) {
                if (allow_trailing_partial) return error.UnexpectedEndOfData;
                return error.UnterminatedEntity;
            }
            var numeric: u32 = 0;
            var digits: usize = 0;
            while (i < value.len and value[i] != ';') : (i += 1) {
                const c = value[i];
                const digit: u8 = if (c >= '0' and c <= '9')
                    c - '0'
                else if (base == 16 and c >= 'a' and c <= 'f')
                    c - 'a' + 10
                else if (base == 16 and c >= 'A' and c <= 'F')
                    c - 'A' + 10
                else
                    return error.InvalidNumericCharacterEntity;
                if (base == 16) {
                    if (numeric > 0x10fff) return error.InvalidNumericCharacterEntity;
                } else if (numeric > (0x10FFFF - @as(u32, digit)) / 10) {
                    return error.InvalidNumericCharacterEntity;
                }
                numeric = numeric * base + @as(u32, digit);
                digits += 1;
            }
            if (i == value.len) {
                if (allow_trailing_partial) return error.UnexpectedEndOfData;
                return error.UnterminatedEntity;
            }
            if (digits == 0 or numeric > 0x10FFFF or !isXmlCharacter(@intCast(numeric))) return error.InvalidNumericCharacterEntity;
            search_from = i + 1;
            continue;
        }
        const semi = std.mem.indexOfScalarPos(u8, value, amp + 1, ';') orelse {
            if (allow_trailing_partial) return error.UnexpectedEndOfData;
            return error.UnterminatedEntity;
        };
        const body = value[amp + 1 .. semi];
        if (body.len == 0 or !isValidXmlName(body)) return error.InvalidNumericCharacterEntity;
        has_custom_reference = true;
        search_from = semi + 1;
    }
    return has_custom_reference;
}

fn validateCustomXmlReferencesUsingCatalog(
    allocator: std.mem.Allocator,
    value: []const u8,
    catalog: *const GeneralEntityCatalog,
    require_declared_entities: bool,
    context: XmlReferenceContext,
) ParseError!void {
    var states = std.StringHashMap(EntityValidationState).init(allocator);
    defer states.deinit();
    var frames = std.ArrayList(EntityValidationFrame).empty;
    defer frames.deinit(allocator);

    var search_from: usize = 0;
    while (std.mem.indexOfScalarPos(u8, value, search_from, '&')) |amp| {
        const semi = std.mem.indexOfScalarPos(u8, value, amp + 1, ';').?;
        const body = value[amp + 1 .. semi];
        if (body[0] != '#' and !isPredefinedEntityName(body)) {
            if (frames.capacity == 0 or !std.mem.eql(u8, frames.items.ptr[0].name, body)) {
                try validateGeneralEntityUse(catalog, &states, &frames, body, require_declared_entities, context);
            }
        }
        search_from = semi + 1;
    }
}

fn buildGeneralEntityCatalog(catalog: *GeneralEntityCatalog, doctype_value: []const u8) ParseError!void {
    const subset_range = try findInternalSubset(doctype_value) orelse return;
    const subset = doctype_value[subset_range.start..subset_range.end];

    var iterator = try ExpandedDtdIterator.init(catalog.allocator, subset, false);
    defer iterator.deinit();
    while (try iterator.next()) |decl| {
        if (decl.kind == .entity) try addGeneralEntityDeclarationBody(catalog, decl.body);
    }
}

fn addGeneralEntityDeclarationBody(catalog: *GeneralEntityCatalog, body: []const u8) ParseError!void {
    var i: usize = 0;
    if (!skipRequiredXmlWhitespace(body, &i)) return error.InvalidDoctype;
    if (i < body.len and body[i] == '%') return;

    const name_start = i;
    try consumeDtdName(body, &i);
    const name = body[name_start..i];
    if (!skipRequiredXmlWhitespace(body, &i)) return error.InvalidDoctype;
    if (catalog.map.contains(name)) return; // XML binds the first declaration.
    const owned_name = try catalog.allocator.dupe(u8, name);
    errdefer catalog.allocator.free(owned_name);

    if (i < body.len and (body[i] == '\'' or body[i] == '"')) {
        const quote = body[i];
        const value_start = i + 1;
        const value_end = std.mem.indexOfScalarPos(u8, body, value_start, quote) orelse return error.InvalidDoctype;
        const replacement = try normalizeEntityValueAlloc(catalog.allocator, body[value_start..value_end]);
        errdefer catalog.allocator.free(replacement);
        try catalog.map.put(owned_name, .{ .kind = .internal, .replacement = replacement });
        return;
    }

    try consumeExternalId(body, &i);
    const kind: GeneralEntityKind = if (skipRequiredXmlWhitespace(body, &i) and std.mem.startsWith(u8, body[i..], "NDATA"))
        .unparsed
    else
        .external_parsed;
    try catalog.map.put(owned_name, .{ .kind = kind });
}

fn normalizeEntityValueAlloc(allocator: std.mem.Allocator, raw: []const u8) ParseError![]u8 {
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);
    var i: usize = 0;
    while (std.mem.indexOf(u8, raw[i..], "&#")) |rel_amp| {
        const amp = i + rel_amp;
        try out.appendSlice(allocator, raw[i..amp]);
        const semi = std.mem.indexOfScalarPos(u8, raw, amp + 2, ';') orelse return error.InvalidDoctype;
        const body = raw[amp + 1 .. semi];
        const cp = xmlNumericReferenceValue(body) orelse return error.InvalidDoctype;
        var buf: [4]u8 = undefined;
        const len = std.unicode.utf8Encode(cp, &buf) catch return error.InvalidDoctype;
        try out.appendSlice(allocator, buf[0..len]);
        i = semi + 1;
    }
    try out.appendSlice(allocator, raw[i..]);
    return out.toOwnedSlice(allocator);
}

fn validateGeneralEntityUse(
    catalog: *const GeneralEntityCatalog,
    states: *std.StringHashMap(EntityValidationState),
    frames: *std.ArrayList(EntityValidationFrame),
    root_name: []const u8,
    require_declared_entities: bool,
    context: XmlReferenceContext,
) ParseError!void {
    try pushGeneralEntity(catalog, states, frames, root_name, require_declared_entities, context);
    while (frames.items.len != 0) {
        const frame_index = frames.items.len - 1;
        const frame = &frames.items[frame_index];
        const amp = std.mem.indexOfScalarPos(u8, frame.replacement, frame.offset, '&');
        if (context == .attribute) {
            if (std.mem.indexOfScalarPos(u8, frame.replacement, frame.offset, '<')) |lt| {
                if (amp == null or lt < amp.?) return error.InvalidAttributeValue;
            }
        }
        const amp_pos = amp orelse {
            states.getPtr(frame.name).?.* = .done;
            frames.items.len -= 1;
            continue;
        };
        const semi = std.mem.indexOfScalarPos(u8, frame.replacement, amp_pos + 1, ';') orelse return error.UnterminatedEntity;
        const body = frame.replacement[amp_pos + 1 .. semi];
        if (!isValidXmlReferenceBody(body)) return error.InvalidNumericCharacterEntity;
        frame.offset = semi + 1;
        if (body[0] == '#' or isPredefinedEntityName(body)) continue;
        try pushGeneralEntity(catalog, states, frames, body, require_declared_entities, context);
    }
}

fn pushGeneralEntity(
    catalog: *const GeneralEntityCatalog,
    states: *std.StringHashMap(EntityValidationState),
    frames: *std.ArrayList(EntityValidationFrame),
    name: []const u8,
    require_declared_entities: bool,
    context: XmlReferenceContext,
) ParseError!void {
    if (states.get(name)) |state| switch (state) {
        .visiting => return error.RecursiveEntity,
        .done => return,
    };

    const entry = catalog.map.getEntry(name) orelse {
        if (require_declared_entities) return error.InvalidNumericCharacterEntity;
        return;
    };
    const canonical_name = entry.key_ptr.*;
    const decl = entry.value_ptr.*;
    switch (decl.kind) {
        .unparsed => return error.InvalidNumericCharacterEntity,
        .external_parsed => {
            if (context == .attribute) return error.InvalidAttributeValue;
            return;
        },
        .internal => {},
    }

    try states.put(canonical_name, .visiting);
    try frames.append(catalog.allocator, .{
        .name = canonical_name,
        .replacement = decl.replacement.?,
    });
}

inline fn isPredefinedEntityName(name: []const u8) bool {
    return switch (name.len) {
        2 => blk: {
            const key = std.mem.readInt(u16, name[0..2], .little);
            break :blk key == 0x746c or key == 0x7467; // lt, gt
        },
        3 => std.mem.readInt(u24, name[0..3], .little) == 0x706d61, // amp
        4 => blk: {
            const key = std.mem.readInt(u32, name[0..4], .little);
            break :blk key == 0x736f7061 or key == 0x746f7571; // apos, quot
        },
        else => false,
    };
}

fn doctypeGeneralEntityKind(doctype_value: []const u8, target: []const u8) ParseError!?GeneralEntityKind {
    const subset_range = try findInternalSubset(doctype_value) orelse return null;
    const subset = doctype_value[subset_range.start..subset_range.end];
    var i: usize = 0;
    while (i < subset.len) {
        if (tables.isWhitespace(subset[i])) {
            _ = skipXmlWhitespace(subset, &i);
            continue;
        }
        if (subset[i] == '%') {
            try consumePeReference(subset, &i);
            continue;
        }
        if (std.mem.startsWith(u8, subset[i..], "<!--")) {
            const end = std.mem.indexOfPos(u8, subset, i + 4, "-->") orelse return error.InvalidDoctype;
            i = end + 3;
            continue;
        }
        if (std.mem.startsWith(u8, subset[i..], "<?")) {
            const end = std.mem.indexOfPos(u8, subset, i + 2, "?>") orelse return error.InvalidDoctype;
            i = end + 2;
            continue;
        }
        if (subset[i] != '<') return error.InvalidDoctype;

        const entity_decl = std.mem.startsWith(u8, subset[i..], "<!ENTITY");
        const keyword_len: usize = if (entity_decl)
            "<!ENTITY".len
        else if (std.mem.startsWith(u8, subset[i..], "<!ELEMENT"))
            "<!ELEMENT".len
        else if (std.mem.startsWith(u8, subset[i..], "<!ATTLIST"))
            "<!ATTLIST".len
        else if (std.mem.startsWith(u8, subset[i..], "<!NOTATION"))
            "<!NOTATION".len
        else
            return error.InvalidDoctype;
        const decl_end = findMarkupDeclEnd(subset, i + keyword_len) orelse return error.InvalidDoctype;
        if (entity_decl) {
            const body = subset[i + keyword_len .. decl_end];
            var j: usize = 0;
            if (!skipRequiredXmlWhitespace(body, &j)) return error.InvalidDoctype;
            if (j < body.len and body[j] == '%') {
                i = decl_end + 1;
                continue;
            }
            const name_start = j;
            try consumeDtdName(body, &j);
            if (std.mem.eql(u8, body[name_start..j], target)) {
                if (!skipRequiredXmlWhitespace(body, &j)) return error.InvalidDoctype;
                if (j < body.len and (body[j] == '\'' or body[j] == '"')) return .internal;
                try consumeExternalId(body, &j);
                if (skipRequiredXmlWhitespace(body, &j) and std.mem.startsWith(u8, body[j..], "NDATA")) return .unparsed;
                return .external_parsed;
            }
        }
        i = decl_end + 1;
    }
    return null;
}

fn isValidXmlReferenceBody(body: []const u8) bool {
    if (body.len == 0) return false;
    if (body[0] != '#') return isValidXmlName(body);
    return xmlNumericReferenceValue(body) != null;
}

fn xmlNumericReferenceValue(body: []const u8) ?u21 {
    if (body.len < 2 or body[0] != '#') return null;
    var i: usize = 1;
    var base: u32 = 10;
    if (i < body.len and body[i] == 'x') {
        base = 16;
        i += 1;
    }
    if (i == body.len) return null;

    var value: u32 = 0;
    while (i < body.len) : (i += 1) {
        const c = body[i];
        const digit: u8 = if (c >= '0' and c <= '9')
            c - '0'
        else if (base == 16 and c >= 'a' and c <= 'f')
            c - 'a' + 10
        else if (base == 16 and c >= 'A' and c <= 'F')
            c - 'A' + 10
        else
            return null;
        if (value > (0x10FFFF - @as(u32, digit)) / base) return null;
        value = value * base + @as(u32, digit);
    }
    if (value > 0x10FFFF or !isXmlCharacter(@intCast(value))) return null;
    return @intCast(value);
}

noinline fn xmlAsciiPrefixLenWide(input: []const u8) usize {
    const Vec = @Vector(64, u8);
    const high_bit: Vec = @splat(0x80);
    const control_limit: Vec = @splat(0x20);
    const tab: Vec = @splat('\t');
    const newline: Vec = @splat('\n');
    const carriage_return: Vec = @splat('\r');

    var i: usize = 0;
    while (i + @sizeOf(Vec) <= input.len) : (i += @sizeOf(Vec)) {
        const bytes: Vec = input[i..][0..@sizeOf(Vec)].*;
        const invalid_control = (bytes < control_limit) &
            (bytes != tab) & (bytes != newline) & (bytes != carriage_return);
        if (@reduce(.Or, (bytes >= high_bit) | invalid_control)) break;
    }
    return i;
}

fn xmlValidPrefixLenImpl(input: []const u8, comptime use_wide_ascii_prefix: bool) ParseError!usize {
    const Vec = @Vector(xml_scan_vector_len, u8);
    const high_bit: Vec = @splat(0x80);
    const control_limit: Vec = @splat(0x20);
    const tab: Vec = @splat('\t');
    const newline: Vec = @splat('\n');
    const carriage_return: Vec = @splat('\r');

    var i: usize = if (comptime use_wide_ascii_prefix and (builtin.cpu.arch == .x86 or builtin.cpu.arch == .x86_64) and
        (std.Target.x86.featureSetHas(builtin.cpu.features, .avx2) or std.Target.x86.featureSetHas(builtin.cpu.features, .avx512bw)))
        xmlAsciiPrefixLenWide(input)
    else if (comptime (builtin.cpu.arch == .x86 or builtin.cpu.arch == .x86_64) and
        std.Target.x86.featureSetHas(builtin.cpu.features, .avx512bw))
        xmlAsciiPrefixLenWide(input)
    else
        0;
    var ascii_fast = true;
    while (i < input.len) {
        // XML is overwhelmingly ASCII. Compact ASCII runs need only the two
        // broad range checks. Once a non-ASCII byte appears, stay on the exact
        // classifier so Unicode-heavy documents do not repeatedly pay both.
        if (ascii_fast) {
            while (i + @sizeOf(Vec) <= input.len) {
                const bytes: Vec = input[i..][0..@sizeOf(Vec)].*;
                const non_ascii = bytes >= high_bit;
                const exceptional = (bytes < control_limit) | non_ascii;
                if (!@reduce(.Or, exceptional)) {
                    i += @sizeOf(Vec);
                    continue;
                }
                if (@reduce(.Or, non_ascii)) {
                    ascii_fast = false;
                    break;
                }
                const invalid_control = (bytes < control_limit) &
                    (bytes != tab) & (bytes != newline) & (bytes != carriage_return);
                if (@reduce(.Or, invalid_control)) break;
                i += @sizeOf(Vec);
            }
        } else {
            while (i + @sizeOf(Vec) <= input.len) {
                const bytes: Vec = input[i..][0..@sizeOf(Vec)].*;
                const invalid_control = (bytes < control_limit) &
                    (bytes != tab) & (bytes != newline) & (bytes != carriage_return);
                if (@reduce(.Or, (bytes >= high_bit) | invalid_control)) break;
                i += @sizeOf(Vec);
            }
        }
        if (i == input.len) break;

        const first = input[i];
        if (first < 0x80) {
            if (first != '\t' and first != '\n' and first != '\r' and first < 0x20) return error.InvalidXmlCharacter;
            i += 1;
            continue;
        }

        const sequence_len: usize = if (first >= 0xC2 and first <= 0xDF)
            2
        else if (first >= 0xE0 and first <= 0xEF)
            3
        else if (first >= 0xF0 and first <= 0xF4)
            4
        else
            return error.InvalidXmlCharacter;

        const available = @min(sequence_len, input.len - i);
        var j: usize = 1;
        while (j < available) : (j += 1) {
            const continuation = input[i + j];
            if (continuation < 0x80 or continuation > 0xBF) return error.InvalidXmlCharacter;
            if (j == 1) {
                if (first == 0xE0 and continuation < 0xA0) return error.InvalidXmlCharacter;
                if (first == 0xED and continuation > 0x9F) return error.InvalidXmlCharacter;
                if (first == 0xF0 and continuation < 0x90) return error.InvalidXmlCharacter;
                if (first == 0xF4 and continuation > 0x8F) return error.InvalidXmlCharacter;
            }
        }
        if (available < sequence_len) return i;

        // The UTF-8 shape/range checks above reject overlong encodings, surrogates,
        // and values above U+10FFFF. Of the remaining non-ASCII scalar values XML
        // only excludes U+FFFE and U+FFFF, whose encodings differ in the last byte.
        if (first == 0xEF and input[i + 1] == 0xBF and input[i + 2] >= 0xBE) {
            return error.InvalidXmlCharacter;
        }
        i += sequence_len;
    }
    return input.len;
}

pub fn xmlValidPrefixLen(input: []const u8) ParseError!usize {
    return xmlValidPrefixLenImpl(input, false);
}

pub fn xmlValidPrefixLenStreaming(input: []const u8) ParseError!usize {
    return xmlValidPrefixLenImpl(input, true);
}

pub fn validateXmlCharacters(input: []const u8) ParseError!void {
    if (try xmlValidPrefixLenImpl(input, false) != input.len) return error.InvalidXmlCharacter;
}

pub fn validateXmlCharactersStreaming(input: []const u8) ParseError!void {
    if (try xmlValidPrefixLenImpl(input, true) != input.len) return error.InvalidXmlCharacter;
}

/// Validates XML Name codepoint ranges when UTF-8 shape has already been
/// validated by the validated parser's whole-input XML character pass.
pub fn isValidXmlNameAssumeValidUtf8(name: []const u8) bool {
    if (name.len == 0) return false;

    var i: usize = 0;
    if (name[0] < 0x80) {
        if (!tables.isNameStart(name[0])) return false;
        i = 1;
    } else if ((nextValidUtf8XmlNameClass(name, &i) & xml_name_start_bit) == 0) {
        return false;
    }

    while (i < name.len) {
        const c = name[i];
        if (c < 0x80) {
            if (!tables.isNameChar(c)) return false;
            i += 1;
            continue;
        }
        if ((nextValidUtf8XmlNameClass(name, &i) & xml_name_char_bit) == 0) return false;
    }
    return true;
}

const xml_name_char_bit: u2 = 0b01;
const xml_name_start_bit: u2 = 0b10;
const xml_name_start_class: u2 = xml_name_char_bit | xml_name_start_bit;

inline fn nextValidUtf8XmlNameClass(input: []const u8, i: *usize) u2 {
    const first = input[i.*];
    if (first < 0xE0) {
        const second = input[i.* + 1];
        i.* += 2;
        if (first == 0xC2) return @intFromBool(second == 0xB7);
        if (first == 0xC3) {
            return if (second == 0x97 or second == 0xB7) 0 else xml_name_start_class;
        }
        if (first <= 0xCB) return xml_name_start_class;
        if (first == 0xCC) return xml_name_char_bit;
        if (first == 0xCD) {
            if (second == 0xBE) return 0;
            return if (second < 0xB0) xml_name_char_bit else xml_name_start_class;
        }
        return xml_name_start_class;
    }

    const second = input[i.* + 1];
    const third = input[i.* + 2];
    if (first < 0xF0) {
        i.* += 3;
        if (first <= 0xE1) return xml_name_start_class;
        if (first == 0xE2) {
            if (second == 0x80) {
                if (third == 0x8C or third == 0x8D) return xml_name_start_class;
                return @intFromBool(third == 0xBF);
            }
            if (second == 0x81) {
                if (third == 0x80) return xml_name_char_bit;
                return if (third >= 0xB0) xml_name_start_class else 0;
            }
            if (second >= 0x82 and second <= 0x85) return xml_name_start_class;
            if (second == 0x86) return if (third <= 0x8F) xml_name_start_class else 0;
            if (second >= 0xB0 and second < 0xBF) return xml_name_start_class;
            return if (second == 0xBF and third <= 0xAF) xml_name_start_class else 0;
        }
        if (first == 0xE3) {
            return if (second == 0x80 and third == 0x80) 0 else xml_name_start_class;
        }
        if (first <= 0xED) return xml_name_start_class;
        if (first == 0xEE) return 0;
        if (second < 0xA4) return 0;
        if (second < 0xB7) return xml_name_start_class;
        if (second == 0xB7) {
            return if (third <= 0x8F or third >= 0xB0) xml_name_start_class else 0;
        }
        if (second < 0xBF) return xml_name_start_class;
        return if (third <= 0xBD) xml_name_start_class else 0;
    }

    i.* += 4;
    if (first < 0xF3) return xml_name_start_class;
    return if (first == 0xF3 and second <= 0xAF) xml_name_start_class else 0;
}

pub fn isValidXmlName(name: []const u8) bool {
    if (name.len == 0) return false;

    var i: usize = 0;
    if (name[0] < 0x80) {
        if (!tables.isNameStart(name[0])) return false;
        i = 1;
    } else {
        const first = nextUtf8Codepoint(name, &i) orelse return false;
        if (!isXmlNonAsciiNameStart(first)) return false;
    }

    while (i < name.len) {
        const c = name[i];
        if (c < 0x80) {
            if (!tables.isNameChar(c)) return false;
            i += 1;
            continue;
        }
        const codepoint = nextUtf8Codepoint(name, &i) orelse return false;
        if (!isXmlNonAsciiNameChar(codepoint)) return false;
    }
    return true;
}

inline fn nextUtf8Codepoint(input: []const u8, i: *usize) ?u21 {
    const first = input[i.*];
    const sequence_len: usize = if (first >= 0xC2 and first <= 0xDF)
        2
    else if (first >= 0xE0 and first <= 0xEF)
        3
    else if (first >= 0xF0 and first <= 0xF4)
        4
    else
        return null;
    if (sequence_len > input.len - i.*) return null;
    const end = i.* + sequence_len;
    const codepoint = std.unicode.utf8Decode(input[i.*..end]) catch return null;
    i.* = end;
    return codepoint;
}

inline fn isXmlCharacter(codepoint: u21) bool {
    return codepoint == 0x9 or codepoint == 0xA or codepoint == 0xD or
        (codepoint >= 0x20 and codepoint <= 0xD7FF) or
        (codepoint >= 0xE000 and codepoint <= 0xFFFD) or
        (codepoint >= 0x10000 and codepoint <= 0x10FFFF);
}

inline fn isXmlNonAsciiNameStart(codepoint: u21) bool {
    return (codepoint >= 0xC0 and codepoint <= 0xD6) or
        (codepoint >= 0xD8 and codepoint <= 0xF6) or
        (codepoint >= 0xF8 and codepoint <= 0x2FF) or
        (codepoint >= 0x370 and codepoint <= 0x37D) or
        (codepoint >= 0x37F and codepoint <= 0x1FFF) or
        (codepoint >= 0x200C and codepoint <= 0x200D) or
        (codepoint >= 0x2070 and codepoint <= 0x218F) or
        (codepoint >= 0x2C00 and codepoint <= 0x2FEF) or
        (codepoint >= 0x3001 and codepoint <= 0xD7FF) or
        (codepoint >= 0xF900 and codepoint <= 0xFDCF) or
        (codepoint >= 0xFDF0 and codepoint <= 0xFFFD) or
        (codepoint >= 0x10000 and codepoint <= 0xEFFFF);
}

inline fn isXmlNonAsciiNameChar(codepoint: u21) bool {
    return isXmlNonAsciiNameStart(codepoint) or codepoint == 0xB7 or
        (codepoint >= 0x0300 and codepoint <= 0x036F) or
        (codepoint >= 0x203F and codepoint <= 0x2040);
}

inline fn isXmlNameStart(codepoint: u21) bool {
    return codepoint == ':' or codepoint == '_' or
        (codepoint >= 'A' and codepoint <= 'Z') or
        (codepoint >= 'a' and codepoint <= 'z') or
        (codepoint >= 0xC0 and codepoint <= 0xD6) or
        (codepoint >= 0xD8 and codepoint <= 0xF6) or
        (codepoint >= 0xF8 and codepoint <= 0x2FF) or
        (codepoint >= 0x370 and codepoint <= 0x37D) or
        (codepoint >= 0x37F and codepoint <= 0x1FFF) or
        (codepoint >= 0x200C and codepoint <= 0x200D) or
        (codepoint >= 0x2070 and codepoint <= 0x218F) or
        (codepoint >= 0x2C00 and codepoint <= 0x2FEF) or
        (codepoint >= 0x3001 and codepoint <= 0xD7FF) or
        (codepoint >= 0xF900 and codepoint <= 0xFDCF) or
        (codepoint >= 0xFDF0 and codepoint <= 0xFFFD) or
        (codepoint >= 0x10000 and codepoint <= 0xEFFFF);
}

inline fn isXmlNameChar(codepoint: u21) bool {
    return isXmlNameStart(codepoint) or codepoint == '-' or codepoint == '.' or
        (codepoint >= '0' and codepoint <= '9') or codepoint == 0xB7 or
        (codepoint >= 0x0300 and codepoint <= 0x036F) or
        (codepoint >= 0x203F and codepoint <= 0x2040);
}

pub const ParseDiagnostic = struct {
    err: ParseError,
    offset: usize,
    source: []const u8,

    pub const Location = struct {
        line: usize,
        column: usize,
    };

    pub fn location(self: @This()) Location {
        var line: usize = 1;
        var column: usize = 1;
        var i: usize = 0;
        const end = @min(self.offset, self.source.len);
        while (i < end) : (i += 1) {
            if (self.source[i] == '\r') {
                line += 1;
                column = 1;
                if (i + 1 < end and self.source[i + 1] == '\n') i += 1;
            } else if (self.source[i] == '\n') {
                line += 1;
                column = 1;
            } else {
                column += 1;
            }
        }
        return .{ .line = line, .column = column };
    }

    pub fn context(self: @This(), radius: usize) []const u8 {
        const center = @min(self.offset, self.source.len);
        const start = center - @min(center, radius);
        const end = center + @min(self.source.len - center, radius);
        return self.source[start..end];
    }
};

pub const XmlDeclarationInfo = struct {
    standalone_yes: bool = false,
};

pub fn validateXmlDeclaration(body: []const u8) ParseError!XmlDeclarationInfo {
    var info: XmlDeclarationInfo = .{};
    var i: usize = 0;
    _ = try expectDeclarationPseudoAttribute(body, &i, "version", .version);

    var had_separator = skipDeclarationWhitespace(body, &i);
    if (i < body.len and std.mem.startsWith(u8, body[i..], "encoding")) {
        if (!had_separator) return error.InvalidDeclaration;
        _ = try expectDeclarationPseudoAttribute(body, &i, "encoding", .encoding);
        had_separator = skipDeclarationWhitespace(body, &i);
    }
    if (i < body.len and std.mem.startsWith(u8, body[i..], "standalone")) {
        if (!had_separator) return error.InvalidDeclaration;
        const standalone = try expectDeclarationPseudoAttribute(body, &i, "standalone", .standalone);
        info.standalone_yes = std.mem.eql(u8, standalone, "yes");
        _ = skipDeclarationWhitespace(body, &i);
    }
    if (i != body.len) return error.InvalidDeclaration;
    return info;
}

pub const DoctypeInfo = struct {
    name_start: usize,
    name_end: usize,
    has_external_id: bool = false,
    has_parameter_entity_references: bool = false,
};

/// Validates XML 1.0 doctypedecl syntax, including the complete internal-subset
/// grammar required for well-formed non-validating parsing. Validity constraints
/// such as declaration uniqueness are intentionally not enforced.
pub fn validateDoctype(value: []const u8) ParseError!DoctypeInfo {
    return validateDoctypeAlloc(std.heap.page_allocator, value);
}

/// Enforces entity-reference well-formedness constraints whose meaning depends
/// on declaration order. `validateDoctypeAlloc` must have accepted the grammar
/// first, so this pass can stay small and sequential.
pub const DtdAttributeValidation = struct {
    input: []const u8,
    attributes: Span,
};

pub fn validateDoctypeEntityConstraintsAlloc(
    allocator: std.mem.Allocator,
    value: []const u8,
    require_declared_entities: bool,
    attribute_validation: ?*const DtdAttributeValidation,
) ParseError!void {
    const subset_range = try findInternalSubset(value) orelse {
        if (attribute_validation) |validation| {
            var attrs = attrs_mod.RawIterator(true).init(validation.input, validation.attributes);
            while (attrs.next()) |attr| {
                const raw = attr.value.slice(validation.input);
                if (try validateXmlReferenceSyntax(raw, false) and require_declared_entities) {
                    return error.InvalidNumericCharacterEntity;
                }
            }
        }
        return;
    };
    const subset = value[subset_range.start..subset_range.end];

    var catalog = GeneralEntityCatalog.init(allocator);
    defer catalog.deinit();

    if (attribute_validation) |validation| {
        var catalog_iterator = try ExpandedDtdIterator.init(allocator, subset, false);
        defer catalog_iterator.deinit();
        while (try catalog_iterator.next()) |decl| {
            if (decl.kind == .entity) try addGeneralEntityDeclarationBody(&catalog, decl.body);
        }

        var frames = std.ArrayList(EntityValidationFrame).empty;
        defer frames.deinit(allocator);
        const input = validation.input;
        var attrs = attrs_mod.RawIterator(true).init(input, validation.attributes);
        while (attrs.next()) |attr| {
            const raw = attr.value.slice(input);
            if (!try validateXmlReferenceSyntax(raw, false)) continue;
            var search_from: usize = 0;
            while (std.mem.indexOfScalarPos(u8, raw, search_from, '&')) |amp| {
                const semi = std.mem.indexOfScalarPos(u8, raw, amp + 1, ';').?;
                const body = raw[amp + 1 .. semi];
                if (body[0] != '#' and !isPredefinedEntityName(body)) {
                    try validateGeneralEntityUse(&catalog, &catalog_iterator.states, &frames, body, require_declared_entities, .attribute);
                }
                search_from = semi + 1;
            }
        }
        return;
    }

    var iterator = try ExpandedDtdIterator.init(allocator, subset, require_declared_entities);
    defer iterator.deinit();
    while (try iterator.next()) |decl| switch (decl.kind) {
        .entity => try addGeneralEntityDeclarationBody(&catalog, decl.body),
        .attlist => try validateAttlistEntityConstraints(allocator, &catalog, decl.body, require_declared_entities),
        else => {},
    };
}

fn validateAttlistEntityConstraints(
    allocator: std.mem.Allocator,
    catalog: *const GeneralEntityCatalog,
    body: []const u8,
    require_declared_entities: bool,
) ParseError!void {
    var i: usize = 0;
    if (!skipRequiredXmlWhitespace(body, &i)) return error.InvalidDoctype;
    try consumeDtdName(body, &i); // element name

    while (true) {
        const had_space = skipXmlWhitespace(body, &i);
        if (i == body.len) return;
        if (!had_space) return error.InvalidDoctype;

        try consumeDtdName(body, &i); // attribute name
        if (!skipRequiredXmlWhitespace(body, &i)) return error.InvalidDoctype;
        try consumeAttributeType(body, &i);
        if (!skipRequiredXmlWhitespace(body, &i)) return error.InvalidDoctype;

        if (std.mem.startsWith(u8, body[i..], "#REQUIRED")) {
            i += "#REQUIRED".len;
            continue;
        }
        if (std.mem.startsWith(u8, body[i..], "#IMPLIED")) {
            i += "#IMPLIED".len;
            continue;
        }
        if (std.mem.startsWith(u8, body[i..], "#FIXED")) {
            i += "#FIXED".len;
            if (!skipRequiredXmlWhitespace(body, &i)) return error.InvalidDoctype;
        }

        if (i >= body.len or (body[i] != '\'' and body[i] != '"')) return error.InvalidDoctype;
        const value_start = i + 1;
        try consumeAttValue(body, &i);
        const value = body[value_start .. i - 1];
        if (!try validateXmlReferenceSyntax(value, false)) continue;
        try validateCustomXmlReferencesUsingCatalog(allocator, value, catalog, require_declared_entities, .attribute);
    }
}

pub fn validateDoctypeAlloc(allocator: std.mem.Allocator, value: []const u8) ParseError!DoctypeInfo {
    var i: usize = 0;
    if (!skipRequiredXmlWhitespace(value, &i)) return error.InvalidDoctype;
    if (i >= value.len or !tables.isNameStart(value[i])) return error.InvalidDoctype;

    const name_start = i;
    i += 1;
    while (i < value.len and tables.isNameChar(value[i])) : (i += 1) {}
    const name_end = i;
    if (!isValidXmlName(value[name_start..name_end])) return error.InvalidDoctype;

    var has_external_id = false;
    var has_parameter_entity_references = false;
    const had_space_after_name = skipXmlWhitespace(value, &i);
    if (i < value.len and std.mem.startsWith(u8, value[i..], "SYSTEM")) {
        has_external_id = true;
        if (!had_space_after_name) return error.InvalidDoctype;
        i += "SYSTEM".len;
        if (!skipRequiredXmlWhitespace(value, &i)) return error.InvalidDoctype;
        try consumeSystemLiteral(value, &i);
        _ = skipXmlWhitespace(value, &i);
    } else if (i < value.len and std.mem.startsWith(u8, value[i..], "PUBLIC")) {
        has_external_id = true;
        if (!had_space_after_name) return error.InvalidDoctype;
        i += "PUBLIC".len;
        if (!skipRequiredXmlWhitespace(value, &i)) return error.InvalidDoctype;
        try consumePubidLiteral(value, &i);
        if (!skipRequiredXmlWhitespace(value, &i)) return error.InvalidDoctype;
        try consumeSystemLiteral(value, &i);
        _ = skipXmlWhitespace(value, &i);
    }

    if (i < value.len and value[i] == '[') {
        const subset_range = findInternalSubset(value[i..]) catch return error.InvalidDoctype;
        const subset = subset_range orelse return error.InvalidDoctype;
        if (subset.start != 1) return error.InvalidDoctype;
        has_parameter_entity_references = try validateInternalSubset(allocator, value[i + subset.start .. i + subset.end]);
        i += subset.end + 1;
        _ = skipXmlWhitespace(value, &i);
    }
    if (i != value.len) return error.InvalidDoctype;

    return .{
        .name_start = name_start,
        .name_end = name_end,
        .has_external_id = has_external_id,
        .has_parameter_entity_references = has_parameter_entity_references,
    };
}

inline fn skipXmlWhitespace(input: []const u8, i: *usize) bool {
    const start = i.*;
    while (i.* < input.len and tables.isWhitespace(input[i.*])) : (i.* += 1) {}
    return i.* != start;
}

inline fn skipRequiredXmlWhitespace(input: []const u8, i: *usize) bool {
    return skipXmlWhitespace(input, i);
}

fn consumeSystemLiteral(input: []const u8, i: *usize) ParseError!void {
    if (i.* >= input.len) return error.InvalidDoctype;
    const quote = input[i.*];
    if (quote != '\'' and quote != '"') return error.InvalidDoctype;
    i.* += 1;
    while (i.* < input.len and input[i.*] != quote) : (i.* += 1) {}
    if (i.* >= input.len) return error.InvalidDoctype;
    i.* += 1;
}

fn consumePubidLiteral(input: []const u8, i: *usize) ParseError!void {
    if (i.* >= input.len) return error.InvalidDoctype;
    const quote = input[i.*];
    if (quote != '\'' and quote != '"') return error.InvalidDoctype;
    i.* += 1;
    while (i.* < input.len and input[i.*] != quote) : (i.* += 1) {
        if (!isPubidChar(input[i.*])) return error.InvalidDoctype;
    }
    if (i.* >= input.len) return error.InvalidDoctype;
    i.* += 1;
}

inline fn isPubidChar(c: u8) bool {
    return c == ' ' or c == '\r' or c == '\n' or
        (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or (c >= '0' and c <= '9') or
        switch (c) {
            '-', '\'', '(', ')', '+', ',', '.', '/', ':', '=', '?', ';', '!', '*', '#', '@', '$', '_', '%' => true,
            else => false,
        };
}

const DtdDeclarationKind = enum { element, attlist, entity, notation };

/// Checks the physical internal subset grammar required of non-validating XML
/// processors. Validity constraints such as unique declarations are deliberately
/// left out, but the complete syntax and internal-subset PE revalidatedion are
/// enforced.
const DtdSequenceFrame = struct {
    input: []const u8,
    offset: usize = 0,
    entity_name: ?[]const u8 = null,
};

const ExpandedDtdDeclaration = struct {
    kind: DtdDeclarationKind,
    body: []const u8,
};

const ExpandedDtdIterator = struct {
    allocator: std.mem.Allocator,
    parameter_entities: ParameterEntityCatalog,
    states: std.StringHashMap(EntityValidationState),
    frames: std.ArrayList(DtdSequenceFrame),
    require_declared_parameter_entities: bool,
    has_parameter_entity_references: bool = false,

    fn init(allocator: std.mem.Allocator, subset: []const u8, require_declared_parameter_entities: bool) ParseError!ExpandedDtdIterator {
        var self: ExpandedDtdIterator = .{
            .allocator = allocator,
            .parameter_entities = ParameterEntityCatalog.init(allocator),
            .states = std.StringHashMap(EntityValidationState).init(allocator),
            .frames = .empty,
            .require_declared_parameter_entities = require_declared_parameter_entities,
        };
        errdefer self.deinit();
        try self.frames.append(allocator, .{ .input = subset });
        return self;
    }

    fn deinit(self: *ExpandedDtdIterator) void {
        self.frames.deinit(self.allocator);
        self.states.deinit();
        self.parameter_entities.deinit();
    }

    fn next(self: *ExpandedDtdIterator) ParseError!?ExpandedDtdDeclaration {
        while (self.frames.items.len != 0) {
            const frame_index = self.frames.items.len - 1;
            var frame = &self.frames.items[frame_index];
            if (frame.offset == frame.input.len) {
                if (frame.entity_name) |name| _ = self.states.remove(name);
                self.frames.items.len -= 1;
                continue;
            }

            const input = frame.input;
            var i = frame.offset;
            if (tables.isWhitespace(input[i])) {
                _ = skipXmlWhitespace(input, &i);
                frame.offset = i;
                continue;
            }
            if (input[i] == '%') {
                self.has_parameter_entity_references = true;
                const name_start = i + 1;
                try consumePeReference(input, &i);
                const name = input[name_start .. i - 1];
                frame.offset = i;

                const entry = self.parameter_entities.map.getEntry(name) orelse {
                    if (self.require_declared_parameter_entities) return error.InvalidDoctype;
                    continue;
                };
                const canonical_name = entry.key_ptr.*;
                const decl = entry.value_ptr.*;
                if (decl.kind == .external) continue; // Non-validating parsers need not read external PEs.
                if (self.states.contains(canonical_name)) return error.RecursiveEntity;
                try self.states.put(canonical_name, .visiting);
                try self.frames.append(self.allocator, .{ .input = decl.replacement.?, .entity_name = canonical_name });
                continue;
            }
            if (std.mem.startsWith(u8, input[i..], "<!--")) {
                const comment_end = std.mem.indexOfPos(u8, input, i + 4, "-->") orelse return error.InvalidDoctype;
                const body = input[i + 4 .. comment_end];
                if (std.mem.indexOf(u8, body, "--") != null or (body.len != 0 and body[body.len - 1] == '-')) {
                    return error.InvalidDoctype;
                }
                frame.offset = comment_end + 3;
                continue;
            }
            if (std.mem.startsWith(u8, input[i..], "<?")) {
                frame.offset = try validateDtdProcessingInstruction(input, i);
                continue;
            }

            const kind: DtdDeclarationKind, const keyword: []const u8 = if (std.mem.startsWith(u8, input[i..], "<!ELEMENT"))
                .{ .element, "<!ELEMENT" }
            else if (std.mem.startsWith(u8, input[i..], "<!ATTLIST"))
                .{ .attlist, "<!ATTLIST" }
            else if (std.mem.startsWith(u8, input[i..], "<!ENTITY"))
                .{ .entity, "<!ENTITY" }
            else if (std.mem.startsWith(u8, input[i..], "<!NOTATION"))
                .{ .notation, "<!NOTATION" }
            else
                return error.InvalidDoctype;

            const decl_end = findMarkupDeclEnd(input, i + keyword.len) orelse return error.InvalidDoctype;
            const body = input[i + keyword.len .. decl_end];
            if (kind == .entity) try addParameterEntityDeclarationBody(&self.parameter_entities, body);
            frame = &self.frames.items[frame_index];
            frame.offset = decl_end + 1;
            return .{ .kind = kind, .body = body };
        }
        return null;
    }
};

/// Checks the physical internal subset grammar required of non-validating XML
/// processors. Validity constraints such as unique declarations are deliberately
/// left out, but the complete syntax and internal-subset PE revalidatedion are
/// enforced.
fn validateInternalSubset(allocator: std.mem.Allocator, subset: []const u8) ParseError!bool {
    var iterator = try ExpandedDtdIterator.init(allocator, subset, false);
    defer iterator.deinit();
    while (try iterator.next()) |decl| try validateDtdDeclarationBody(allocator, decl.body, decl.kind);
    return iterator.has_parameter_entity_references;
}

fn addParameterEntityDeclarationBody(catalog: *ParameterEntityCatalog, body: []const u8) ParseError!void {
    var i: usize = 0;
    if (!skipRequiredXmlWhitespace(body, &i)) return error.InvalidDoctype;
    if (i >= body.len or body[i] != '%') return;
    i += 1;
    if (!skipRequiredXmlWhitespace(body, &i)) return error.InvalidDoctype;

    const name_start = i;
    try consumeDtdName(body, &i);
    const name = body[name_start..i];
    if (!skipRequiredXmlWhitespace(body, &i)) return error.InvalidDoctype;
    if (catalog.map.contains(name)) return;

    if (i < body.len and (body[i] == '\'' or body[i] == '"')) {
        const quote = body[i];
        const value_start = i + 1;
        const value_end = std.mem.indexOfScalarPos(u8, body, value_start, quote) orelse return error.InvalidDoctype;
        const replacement = try normalizeEntityValueAlloc(catalog.allocator, body[value_start..value_end]);
        errdefer catalog.allocator.free(replacement);
        try catalog.map.put(name, .{ .kind = .internal, .replacement = replacement });
        return;
    }

    try consumeExternalId(body, &i);
    try catalog.map.put(name, .{ .kind = .external });
}

fn validateDtdProcessingInstruction(input: []const u8, start: usize) ParseError!usize {
    var i = start + 2;
    try consumeDtdName(input, &i);
    const target = input[start + 2 .. i];
    if (std.ascii.eqlIgnoreCase(target, "xml")) return error.InvalidDoctype;

    if (i + 1 < input.len and input[i] == '?' and input[i + 1] == '>') return i + 2;
    if (!skipRequiredXmlWhitespace(input, &i)) return error.InvalidDoctype;
    const pi_end = std.mem.indexOfPos(u8, input, i, "?>") orelse return error.InvalidDoctype;
    return pi_end + 2;
}

fn validateDtdDeclarationBody(allocator: std.mem.Allocator, body: []const u8, kind: DtdDeclarationKind) ParseError!void {
    var i: usize = 0;
    if (!skipRequiredXmlWhitespace(body, &i)) return error.InvalidDoctype;

    switch (kind) {
        .element => {
            try consumeDtdName(body, &i);
            if (!skipRequiredXmlWhitespace(body, &i)) return error.InvalidDoctype;
            try validateElementContentSpec(allocator, body, &i);
            _ = skipXmlWhitespace(body, &i);
            if (i != body.len) return error.InvalidDoctype;
        },
        .attlist => {
            try consumeDtdName(body, &i);
            while (true) {
                const had_space = skipXmlWhitespace(body, &i);
                if (i == body.len) return;
                if (!had_space) return error.InvalidDoctype;
                try consumeDtdName(body, &i);
                if (!skipRequiredXmlWhitespace(body, &i)) return error.InvalidDoctype;
                try consumeAttributeType(body, &i);
                if (!skipRequiredXmlWhitespace(body, &i)) return error.InvalidDoctype;
                try consumeDefaultDecl(body, &i);
            }
        },
        .entity => {
            var parameter = false;
            if (i < body.len and body[i] == '%') {
                parameter = true;
                i += 1;
                if (!skipRequiredXmlWhitespace(body, &i)) return error.InvalidDoctype;
            }
            try consumeDtdName(body, &i);
            if (!skipRequiredXmlWhitespace(body, &i)) return error.InvalidDoctype;
            try consumeEntityDefinition(body, &i, parameter);
            _ = skipXmlWhitespace(body, &i);
            if (i != body.len) return error.InvalidDoctype;
        },
        .notation => {
            try consumeDtdName(body, &i);
            if (!skipRequiredXmlWhitespace(body, &i)) return error.InvalidDoctype;
            try consumeNotationDefinition(body, &i);
            _ = skipXmlWhitespace(body, &i);
            if (i != body.len) return error.InvalidDoctype;
        },
    }
}

fn consumeDtdName(input: []const u8, i: *usize) ParseError!void {
    if (i.* >= input.len or !tables.isNameStart(input[i.*])) return error.InvalidDoctype;
    const start = i.*;
    i.* += 1;
    while (i.* < input.len and tables.isNameChar(input[i.*])) : (i.* += 1) {}
    if (!isValidXmlName(input[start..i.*])) return error.InvalidDoctype;
}

fn consumeDtdNmtoken(input: []const u8, i: *usize) ParseError!void {
    const start = i.*;
    if (i.* >= input.len or !tables.isNameChar(input[i.*])) return error.InvalidDoctype;
    while (i.* < input.len and tables.isNameChar(input[i.*])) : (i.* += 1) {}

    var j = start;
    while (j < i.*) {
        const c = input[j];
        if (c < 0x80) {
            if (!tables.isNameChar(c)) return error.InvalidDoctype;
            j += 1;
        } else {
            const cp = nextUtf8Codepoint(input[0..i.*], &j) orelse return error.InvalidDoctype;
            if (!isXmlNameChar(cp)) return error.InvalidDoctype;
        }
    }
}

fn consumePeReference(input: []const u8, i: *usize) ParseError!void {
    std.debug.assert(i.* < input.len and input[i.*] == '%');
    i.* += 1;
    try consumeDtdName(input, i);
    if (i.* >= input.len or input[i.*] != ';') return error.InvalidDoctype;
    i.* += 1;
}

const ContentSeparator = enum { unset, choice, sequence };
const ContentFrame = struct {
    separator: ContentSeparator = .unset,
    expect_cp: bool = true,
};

fn consumeOccurrence(input: []const u8, i: *usize) void {
    if (i.* < input.len and (input[i.*] == '?' or input[i.*] == '*' or input[i.*] == '+')) i.* += 1;
}

fn validateElementContentSpec(allocator: std.mem.Allocator, input: []const u8, i: *usize) ParseError!void {
    if (std.mem.startsWith(u8, input[i.*..], "EMPTY")) {
        i.* += "EMPTY".len;
        return;
    }
    if (std.mem.startsWith(u8, input[i.*..], "ANY")) {
        i.* += "ANY".len;
        return;
    }
    if (i.* >= input.len or input[i.*] != '(') return error.InvalidDoctype;

    var probe = i.* + 1;
    _ = skipXmlWhitespace(input, &probe);
    if (std.mem.startsWith(u8, input[probe..], "#PCDATA")) {
        try consumeMixedContent(input, i);
        return;
    }
    try consumeChildrenContent(allocator, input, i);
}

fn consumeMixedContent(input: []const u8, i: *usize) ParseError!void {
    std.debug.assert(input[i.*] == '(');
    i.* += 1;
    _ = skipXmlWhitespace(input, i);
    if (!std.mem.startsWith(u8, input[i.*..], "#PCDATA")) return error.InvalidDoctype;
    i.* += "#PCDATA".len;

    var has_names = false;
    while (true) {
        _ = skipXmlWhitespace(input, i);
        if (i.* >= input.len) return error.InvalidDoctype;
        if (input[i.*] == '|') {
            has_names = true;
            i.* += 1;
            _ = skipXmlWhitespace(input, i);
            try consumeDtdName(input, i);
            continue;
        }
        if (input[i.*] != ')') return error.InvalidDoctype;
        i.* += 1;
        if (i.* < input.len and input[i.*] == '*') {
            i.* += 1;
            return;
        }
        if (has_names) return error.InvalidDoctype;
        return;
    }
}

fn consumeChildrenContent(allocator: std.mem.Allocator, input: []const u8, i: *usize) ParseError!void {
    std.debug.assert(input[i.*] == '(');
    var stack_fallback = std.heap.stackFallback(512, allocator);
    const temp_allocator = stack_fallback.get();
    var stack: std.ArrayList(ContentFrame) = .empty;
    defer stack.deinit(temp_allocator);

    i.* += 1;
    try stack.append(temp_allocator, .{});
    while (stack.items.len != 0) {
        const frame_index = stack.items.len - 1;
        if (stack.items[frame_index].expect_cp) {
            _ = skipXmlWhitespace(input, i);
            if (i.* >= input.len) return error.InvalidDoctype;
            if (input[i.*] == '(') {
                i.* += 1;
                try stack.append(temp_allocator, .{});
                continue;
            }
            try consumeDtdName(input, i);
            consumeOccurrence(input, i);
            stack.items[frame_index].expect_cp = false;
            continue;
        }

        _ = skipXmlWhitespace(input, i);
        if (i.* >= input.len) return error.InvalidDoctype;
        const c = input[i.*];
        if (c == '|' or c == ',') {
            const separator: ContentSeparator = if (c == '|') .choice else .sequence;
            if (stack.items[frame_index].separator == .unset) {
                stack.items[frame_index].separator = separator;
            } else if (stack.items[frame_index].separator != separator) {
                return error.InvalidDoctype;
            }
            stack.items[frame_index].expect_cp = true;
            i.* += 1;
            continue;
        }
        if (c != ')') return error.InvalidDoctype;

        i.* += 1;
        stack.items.len -= 1;
        consumeOccurrence(input, i);
        if (stack.items.len != 0) stack.items[stack.items.len - 1].expect_cp = false;
    }
}

fn consumeAttributeType(input: []const u8, i: *usize) ParseError!void {
    const keywords = [_][]const u8{ "CDATA", "IDREFS", "IDREF", "ID", "ENTITIES", "ENTITY", "NMTOKENS", "NMTOKEN" };
    inline for (keywords) |keyword| {
        if (std.mem.startsWith(u8, input[i.*..], keyword)) {
            i.* += keyword.len;
            return;
        }
    }
    if (std.mem.startsWith(u8, input[i.*..], "NOTATION")) {
        i.* += "NOTATION".len;
        if (!skipRequiredXmlWhitespace(input, i)) return error.InvalidDoctype;
        try consumeNameEnumeration(input, i);
        return;
    }
    try consumeNmtokenEnumeration(input, i);
}

fn consumeNameEnumeration(input: []const u8, i: *usize) ParseError!void {
    if (i.* >= input.len or input[i.*] != '(') return error.InvalidDoctype;
    i.* += 1;
    _ = skipXmlWhitespace(input, i);
    try consumeDtdName(input, i);
    while (true) {
        _ = skipXmlWhitespace(input, i);
        if (i.* >= input.len) return error.InvalidDoctype;
        if (input[i.*] == ')') {
            i.* += 1;
            return;
        }
        if (input[i.*] != '|') return error.InvalidDoctype;
        i.* += 1;
        _ = skipXmlWhitespace(input, i);
        try consumeDtdName(input, i);
    }
}

fn consumeNmtokenEnumeration(input: []const u8, i: *usize) ParseError!void {
    if (i.* >= input.len or input[i.*] != '(') return error.InvalidDoctype;
    i.* += 1;
    _ = skipXmlWhitespace(input, i);
    try consumeDtdNmtoken(input, i);
    while (true) {
        _ = skipXmlWhitespace(input, i);
        if (i.* >= input.len) return error.InvalidDoctype;
        if (input[i.*] == ')') {
            i.* += 1;
            return;
        }
        if (input[i.*] != '|') return error.InvalidDoctype;
        i.* += 1;
        _ = skipXmlWhitespace(input, i);
        try consumeDtdNmtoken(input, i);
    }
}

fn consumeDefaultDecl(input: []const u8, i: *usize) ParseError!void {
    if (std.mem.startsWith(u8, input[i.*..], "#REQUIRED")) {
        i.* += "#REQUIRED".len;
        return;
    }
    if (std.mem.startsWith(u8, input[i.*..], "#IMPLIED")) {
        i.* += "#IMPLIED".len;
        return;
    }
    if (std.mem.startsWith(u8, input[i.*..], "#FIXED")) {
        i.* += "#FIXED".len;
        if (!skipRequiredXmlWhitespace(input, i)) return error.InvalidDoctype;
    }
    try consumeAttValue(input, i);
}

fn consumeAttValue(input: []const u8, i: *usize) ParseError!void {
    if (i.* >= input.len or (input[i.*] != '\'' and input[i.*] != '"')) return error.InvalidDoctype;
    const quote = input[i.*];
    i.* += 1;
    while (i.* < input.len and input[i.*] != quote) {
        if (input[i.*] == '<') return error.InvalidDoctype;
        if (input[i.*] == '&') {
            try consumeDtdReference(input, i);
            continue;
        }
        i.* += 1;
    }
    if (i.* >= input.len) return error.InvalidDoctype;
    i.* += 1;
}

fn consumeEntityDefinition(input: []const u8, i: *usize, parameter: bool) ParseError!void {
    if (i.* >= input.len) return error.InvalidDoctype;
    if (input[i.*] == '\'' or input[i.*] == '"') {
        try consumeEntityValue(input, i);
        return;
    }

    try consumeExternalId(input, i);
    if (parameter) return;

    const saved = i.*;
    if (!skipRequiredXmlWhitespace(input, i)) return;
    if (!std.mem.startsWith(u8, input[i.*..], "NDATA")) {
        i.* = saved;
        return;
    }
    i.* += "NDATA".len;
    if (!skipRequiredXmlWhitespace(input, i)) return error.InvalidDoctype;
    try consumeDtdName(input, i);
}

fn consumeEntityValue(input: []const u8, i: *usize) ParseError!void {
    const quote = input[i.*];
    i.* += 1;
    while (i.* < input.len and input[i.*] != quote) {
        // PE references are syntactically recognized in entity values, but the
        // XML internal-subset well-formedness constraint forbids them here.
        if (input[i.*] == '%') return error.InvalidDoctype;
        if (input[i.*] == '&') {
            try consumeDtdReference(input, i);
            continue;
        }
        i.* += 1;
    }
    if (i.* >= input.len) return error.InvalidDoctype;
    i.* += 1;
}

fn consumeDtdReference(input: []const u8, i: *usize) ParseError!void {
    std.debug.assert(i.* < input.len and input[i.*] == '&');
    i.* += 1;
    if (i.* < input.len and input[i.*] == '#') {
        i.* += 1;
        var base: u8 = 10;
        if (i.* < input.len and input[i.*] == 'x') {
            base = 16;
            i.* += 1;
        }
        const digits_start = i.*;
        var value: u32 = 0;
        while (i.* < input.len) : (i.* += 1) {
            const c = input[i.*];
            const digit: ?u8 = if (c >= '0' and c <= '9')
                c - '0'
            else if (base == 16 and c >= 'a' and c <= 'f')
                c - 'a' + 10
            else if (base == 16 and c >= 'A' and c <= 'F')
                c - 'A' + 10
            else
                null;
            const d = digit orelse break;
            if (value > (0x10FFFF - @as(u32, d)) / @as(u32, base)) return error.InvalidDoctype;
            value = value * @as(u32, base) + @as(u32, d);
        }
        if (i.* == digits_start or value > 0x10FFFF or !isXmlCharacter(@intCast(value))) return error.InvalidDoctype;
    } else {
        try consumeDtdName(input, i);
    }
    if (i.* >= input.len or input[i.*] != ';') return error.InvalidDoctype;
    i.* += 1;
}

fn consumeExternalId(input: []const u8, i: *usize) ParseError!void {
    if (std.mem.startsWith(u8, input[i.*..], "SYSTEM")) {
        i.* += "SYSTEM".len;
        if (!skipRequiredXmlWhitespace(input, i)) return error.InvalidDoctype;
        try consumeSystemLiteral(input, i);
        return;
    }
    if (!std.mem.startsWith(u8, input[i.*..], "PUBLIC")) return error.InvalidDoctype;
    i.* += "PUBLIC".len;
    if (!skipRequiredXmlWhitespace(input, i)) return error.InvalidDoctype;
    try consumePubidLiteral(input, i);
    if (!skipRequiredXmlWhitespace(input, i)) return error.InvalidDoctype;
    try consumeSystemLiteral(input, i);
}

fn consumeNotationDefinition(input: []const u8, i: *usize) ParseError!void {
    if (std.mem.startsWith(u8, input[i.*..], "SYSTEM")) {
        i.* += "SYSTEM".len;
        if (!skipRequiredXmlWhitespace(input, i)) return error.InvalidDoctype;
        try consumeSystemLiteral(input, i);
        return;
    }
    if (!std.mem.startsWith(u8, input[i.*..], "PUBLIC")) return error.InvalidDoctype;
    i.* += "PUBLIC".len;
    if (!skipRequiredXmlWhitespace(input, i)) return error.InvalidDoctype;
    try consumePubidLiteral(input, i);

    const after_pubid = i.*;
    if (!skipRequiredXmlWhitespace(input, i)) return;
    if (i.* < input.len and (input[i.*] == '\'' or input[i.*] == '"')) {
        try consumeSystemLiteral(input, i);
    } else {
        i.* = after_pubid;
    }
}

const DeclarationValueKind = enum { version, encoding, standalone };

fn expectDeclarationPseudoAttribute(body: []const u8, i: *usize, comptime name: []const u8, comptime kind: DeclarationValueKind) ParseError![]const u8 {
    if (!std.mem.startsWith(u8, body[i.*..], name)) return error.InvalidDeclaration;
    i.* += name.len;
    _ = skipDeclarationWhitespace(body, i);
    if (i.* >= body.len or body[i.*] != '=') return error.InvalidDeclaration;
    i.* += 1;
    _ = skipDeclarationWhitespace(body, i);
    if (i.* >= body.len or (body[i.*] != '\'' and body[i.*] != '"')) return error.InvalidDeclaration;
    const quote = body[i.*];
    i.* += 1;
    const value_start = i.*;
    while (i.* < body.len and body[i.*] != quote) : (i.* += 1) {}
    if (i.* >= body.len) return error.InvalidDeclaration;
    const value = body[value_start..i.*];
    i.* += 1;

    const valid = switch (kind) {
        .version => blk: {
            if (value.len < 3 or value[0] != '1' or value[1] != '.') break :blk false;
            for (value[2..]) |c| if (c < '0' or c > '9') break :blk false;
            break :blk true;
        },
        .encoding => blk: {
            if (value.len == 0 or !std.ascii.isAlphabetic(value[0])) break :blk false;
            for (value[1..]) |c| {
                if (!std.ascii.isAlphanumeric(c) and c != '.' and c != '_' and c != '-') break :blk false;
            }
            break :blk true;
        },
        .standalone => std.mem.eql(u8, value, "yes") or std.mem.eql(u8, value, "no"),
    };
    if (!valid) return error.InvalidDeclaration;
    return value;
}

fn skipDeclarationWhitespace(body: []const u8, i: *usize) bool {
    const start = i.*;
    while (i.* < body.len and tables.isWhitespace(body[i.*])) : (i.* += 1) {}
    return i.* != start;
}

pub const NodeType = enum(u4) {
    document,
    element,
    text,
    comment,
    cdata,
    pi,
    declaration,
    doctype,
};

fn OptionalIndex(comptime enabled: bool) type {
    return if (enabled) IndexInt else void;
}

fn OptionalNodeType(comptime enabled: bool) type {
    return if (enabled) NodeType else void;
}

fn OptionalSpan(comptime enabled: bool) type {
    return if (enabled) Span else void;
}

fn emptyInput(comptime options: ParseOptions) options.Input() {
    const empty: []const u8 = &[_]u8{};
    return if (options.non_destructive) empty else @constCast(empty);
}

/// Generated persistent node layout. The fastest/default XML document is exactly
/// parent + subtree_end + one source span. Optional navigation and misc metadata
/// physically disappear from document types that do not request them.
pub fn GetRawNode(comptime options: ParseOptions) type {
    return struct {
        parent: IndexInt = InvalidIndex,
        /// Inclusive subtree tail for elements/document. Zero identifies text in
        /// the compact no-misc layout because real elements start at index >= 1.
        subtree_end: IndexInt = 0,
        /// Element tag-name span or text/misc primary source span.
        name_or_text: Span = .{},
        last_child: OptionalIndex(options.store_last_child) = if (options.store_last_child) InvalidIndex else {},
        prev_sibling: OptionalIndex(options.store_prev_sibling) = if (options.store_prev_sibling) InvalidIndex else {},
        /// Rich node kind exists only when callers request XML misc nodes.
        kind: OptionalNodeType(options.include_misc_nodes) = if (options.include_misc_nodes) .text else {},
        /// PI/declaration secondary payload exists only in the rich misc layout.
        misc_value: OptionalSpan(options.include_misc_nodes) = if (options.include_misc_nodes) .{} else {},

        pub inline fn initDocument() @This() {
            return .{
                .parent = InvalidIndex,
                .subtree_end = 0,
                .name_or_text = .{},
                .last_child = if (options.store_last_child) InvalidIndex else {},
                .prev_sibling = if (options.store_prev_sibling) InvalidIndex else {},
                .kind = if (options.include_misc_nodes) .document else {},
                .misc_value = if (options.include_misc_nodes) .{} else {},
            };
        }

        pub inline fn initElement(idx: IndexInt, parent: IndexInt, name: Span, prev: IndexInt) @This() {
            return .{
                .parent = parent,
                .subtree_end = idx,
                .name_or_text = name,
                .last_child = if (options.store_last_child) InvalidIndex else {},
                .prev_sibling = if (options.store_prev_sibling) prev else {},
                .kind = if (options.include_misc_nodes) .element else {},
                .misc_value = if (options.include_misc_nodes) .{} else {},
            };
        }

        pub inline fn initText(parent: IndexInt, text: Span, prev: IndexInt) @This() {
            return .{
                .parent = parent,
                .subtree_end = 0,
                .name_or_text = text,
                .last_child = if (options.store_last_child) InvalidIndex else {},
                .prev_sibling = if (options.store_prev_sibling) prev else {},
                .kind = if (options.include_misc_nodes) .text else {},
                .misc_value = if (options.include_misc_nodes) .{} else {},
            };
        }

        pub inline fn initMisc(parent: IndexInt, node_kind: NodeType, primary: Span, value: Span, prev: IndexInt) @This() {
            comptime std.debug.assert(options.include_misc_nodes);
            return .{
                .parent = parent,
                .subtree_end = 0,
                .name_or_text = primary,
                .last_child = if (options.store_last_child) InvalidIndex else {},
                .prev_sibling = if (options.store_prev_sibling) prev else {},
                .kind = node_kind,
                .misc_value = value,
            };
        }

        pub inline fn nodeKind(self: *const @This(), idx: IndexInt) NodeType {
            if (idx == 0) return .document;
            if (comptime options.include_misc_nodes) return self.kind;
            return if (self.subtree_end == 0) .text else .element;
        }

        pub inline fn isDocument(_: *const @This(), idx: IndexInt) bool {
            return idx == 0;
        }

        pub inline fn isText(self: *const @This(), idx: IndexInt) bool {
            return self.nodeKind(idx) == .text;
        }

        pub inline fn isElement(self: *const @This(), idx: IndexInt) bool {
            return self.nodeKind(idx) == .element;
        }

        pub inline fn valueSpan(self: *const @This(), idx: IndexInt) Span {
            if (comptime options.include_misc_nodes) {
                return switch (self.nodeKind(idx)) {
                    .pi, .declaration => self.misc_value,
                    else => self.name_or_text,
                };
            }
            return self.name_or_text;
        }
    };
}

const ValueError = std.mem.Allocator.Error || entities.DecodeError;

const TextMaterializationState = enum(u8) {
    decode_failed = 1,
    decoded = 2,
    raw = 0xff,
};

fn GetAttribute(comptime options: ParseOptions) type {
    return struct {
        const Self = @This();
        const DocumentType = GetDocument(options);
        doc: *DocumentType,
        raw_attr: RawAttribute,

        pub fn nameSlice(self: Self) []const u8 {
            return self.raw_attr.name.slice(self.doc.source);
        }

        pub fn valueRawSlice(self: Self) []const u8 {
            return self.raw_attr.value.slice(self.doc.source);
        }

        pub fn namespacePrefix(self: Self) ?[]const u8 {
            const name = self.nameSlice();
            const split = std.mem.indexOfScalar(u8, name, ':') orelse return null;
            return name[0..split];
        }

        pub fn localName(self: Self) []const u8 {
            const name = self.nameSlice();
            const split = std.mem.indexOfScalar(u8, name, ':') orelse return name;
            return name[split + 1 ..];
        }

        pub fn value(self: Self, alloc: std.mem.Allocator) ValueError!common.SliceResult {
            if (!self.raw_attr.hasValue()) return .{ .value = "" };
            if (self.raw_attr.value_state.isDecoded()) return .{ .value = self.valueRawSlice() };
            return self.doc.decodeValueResult(alloc, self.valueRawSlice());
        }

        pub fn write(self: Self, writer: anytype) !void {
            try writer.writeAll(self.nameSlice());
            if (!self.raw_attr.hasValue()) return;
            try writer.writeAll("=\"");
            const bytes = self.valueRawSlice();
            if (self.raw_attr.value_state.isDecoded()) {
                try writeEscapedAttributeValue(writer, bytes);
            } else {
                try writeDoubleQuotedAttributeValue(writer, bytes);
            }
            try writer.writeAll("\"");
        }
    };
}

fn GetAttributeIterator(comptime options: ParseOptions) type {
    return struct {
        const DocumentType = GetDocument(options);
        const AttributeType = GetAttribute(options);
        const RawIteratorType = attrs_mod.Iterator(options.non_destructive, options.validate_well_formedness);

        doc: *DocumentType,
        raw: RawIteratorType,

        pub fn next(self: *@This()) ?AttributeType {
            const raw_attr = self.raw.next() orelse return null;
            return .{ .doc = self.doc, .raw_attr = raw_attr };
        }
    };
}

fn GetNode(comptime options: ParseOptions) type {
    return struct {
        const Self = @This();
        const DocumentType = GetDocument(options);
        const RawNodeType = GetRawNode(options);
        const AttributeIteratorType = GetAttributeIterator(options);
        const AttributeType = GetAttribute(options);

        doc: *DocumentType,
        index: IndexInt,
        kind: NodeType,

        inline fn raw(self: Self) *const RawNodeType {
            return &self.doc.nodes[@intCast(self.index)];
        }

        inline fn rawAttributes(self: Self) attrs_mod.Iterator(options.non_destructive, options.validate_well_formedness) {
            const IteratorType = attrs_mod.Iterator(options.non_destructive, options.validate_well_formedness);
            if (self.kind != .element) return IteratorType.initElement(self.doc.source, @intCast(self.doc.source.len));
            return IteratorType.initElement(self.doc.source, @intCast(self.raw().name_or_text.end));
        }

        inline fn materializeAttributes(self: Self) void {
            if (comptime options.non_destructive) return;
            if (self.kind != .element) return;
            _ = attrs_mod.materializeAttributes(
                options.validate_well_formedness,
                self.doc.source,
                @intCast(self.raw().name_or_text.end),
                self.doc.entityMap(),
            );
        }

        inline fn findAttributeRaw(self: Self, name: []const u8) ?RawAttribute {
            var it = self.rawAttributes();
            while (it.next()) |attr| {
                if (std.mem.eql(u8, attr.name.slice(self.doc.source), name)) return attr;
            }
            return null;
        }

        pub fn attributes(self: Self) AttributeIteratorType {
            self.materializeAttributes();
            return .{ .doc = self.doc, .raw = self.rawAttributes() };
        }

        pub fn nameSlice(self: Self) []const u8 {
            if (self.kind == .text or self.kind == .comment or self.kind == .cdata or self.kind == .doctype or self.kind == .document) return "";
            return self.raw().name_or_text.slice(self.doc.source);
        }

        pub fn namespacePrefix(self: Self) ?[]const u8 {
            const name = self.nameSlice();
            const split = std.mem.indexOfScalar(u8, name, ':') orelse return null;
            return name[0..split];
        }

        pub fn localName(self: Self) []const u8 {
            const name = self.nameSlice();
            const split = std.mem.indexOfScalar(u8, name, ':') orelse return name;
            return name[split + 1 ..];
        }

        pub fn namespaceUri(self: Self) ?[]const u8 {
            if (self.kind != .element) return null;
            const prefix = self.namespacePrefix();
            if (prefix) |p| {
                if (std.mem.eql(u8, p, "xml")) return "http://www.w3.org/XML/1998/namespace";
            }
            var cur: ?Self = self;
            while (cur) |node| : (cur = node.parentNode()) {
                if (node.kind != .element) continue;
                var attrs = node.rawAttributes();
                while (attrs.next()) |attr| {
                    const name = attr.name.slice(node.doc.source);
                    if (prefix) |p| {
                        if (std.mem.startsWith(u8, name, "xmlns:") and std.mem.eql(u8, name["xmlns:".len..], p)) {
                            const uri = attr.value.slice(node.doc.source);
                            return if (uri.len == 0) null else uri;
                        }
                    } else if (std.mem.eql(u8, name, "xmlns")) {
                        const uri = attr.value.slice(node.doc.source);
                        return if (uri.len == 0) null else uri;
                    }
                }
            }
            return null;
        }

        pub fn valueRawSlice(self: Self) []const u8 {
            if (self.kind == .element or self.kind == .document) return "";
            return self.raw().valueSpan(self.index).slice(self.doc.source);
        }

        pub fn value(self: Self, alloc: std.mem.Allocator) ValueError!common.SliceResult {
            if (self.kind == .text) return self.doc.materializeText(self.index, alloc);
            return .{ .value = self.valueRawSlice() };
        }

        pub fn firstChild(self: Self) ?Self {
            const idx = self.index + 1;
            if (@as(usize, @intCast(idx)) >= self.doc.nodes.len) return null;
            if (self.doc.nodes[@intCast(idx)].parent != self.index) return null;
            return self.doc.nodeAt(idx);
        }

        pub fn lastChild(self: Self) ?Self {
            if (comptime options.store_last_child) return self.doc.nodeAt(self.raw().last_child);
            var idx = self.index + 1;
            var last: IndexInt = InvalidIndex;
            const end = self.raw().subtree_end;
            while (idx <= end and @as(usize, @intCast(idx)) < self.doc.nodes.len) {
                if (self.doc.nodes[@intCast(idx)].parent == self.index) last = idx;
                const tail = self.doc.subtreeEndAt(idx);
                idx = tail + 1;
            }
            return self.doc.nodeAt(last);
        }

        pub fn nextSibling(self: Self) ?Self {
            const parent_idx = self.raw().parent;
            if (parent_idx == InvalidIndex) return null;
            const next_idx = self.doc.subtreeEndAt(self.index) + 1;
            if (@as(usize, @intCast(next_idx)) >= self.doc.nodes.len) return null;
            if (self.doc.nodes[@intCast(next_idx)].parent != parent_idx) return null;
            return self.doc.nodeAt(next_idx);
        }

        pub fn prevSibling(self: Self) ?Self {
            if (comptime options.store_prev_sibling) return self.doc.nodeAt(self.raw().prev_sibling);
            const parent_idx = self.raw().parent;
            if (parent_idx == InvalidIndex) return null;
            var idx = parent_idx + 1;
            var prev: IndexInt = InvalidIndex;
            while (idx < self.index) {
                if (self.doc.nodes[@intCast(idx)].parent == parent_idx) prev = idx;
                const tail = self.doc.subtreeEndAt(idx);
                idx = tail + 1;
            }
            return self.doc.nodeAt(prev);
        }

        pub fn parentNode(self: Self) ?Self {
            return self.doc.nodeAt(self.raw().parent);
        }

        pub fn getAttributeValueRaw(self: Self, name: []const u8) ?[]const u8 {
            const attr = self.findAttributeRaw(name) orelse return null;
            return attr.value.slice(self.doc.source);
        }

        pub fn getAttributeValue(self: Self, alloc: std.mem.Allocator, name: []const u8) ValueError!?common.SliceResult {
            if (comptime !options.non_destructive) self.materializeAttributes();
            const raw_attr = self.findAttributeRaw(name) orelse return null;
            if (!raw_attr.hasValue()) return .{ .value = "" };
            const raw_value = raw_attr.value.slice(self.doc.source);
            if (raw_attr.value_state.isDecoded()) return .{ .value = raw_value };
            return try self.doc.decodeValueResult(alloc, raw_value);
        }

        pub fn firstAttribute(self: Self) ?AttributeType {
            var it = self.attributes();
            return it.next();
        }

        pub fn innerTextRaw(self: Self) ?[]const u8 {
            if (self.kind == .text or self.kind == .cdata) return self.valueRawSlice();
            const end = self.raw().subtree_end;
            var first: ?[]const u8 = null;
            var idx = self.index + 1;
            while (idx <= end and @as(usize, @intCast(idx)) < self.doc.nodes.len) : (idx += 1) {
                const kind = self.doc.kindAt(idx);
                if (kind != .text and kind != .cdata) continue;
                if (first != null) return null;
                first = self.doc.nodes[@intCast(idx)].valueSpan(idx).slice(self.doc.source);
            }
            return first orelse "";
        }

        pub fn innerText(self: Self, alloc: std.mem.Allocator) ValueError!common.SliceResult {
            if (self.kind == .text) return self.value(alloc);
            if (self.kind == .cdata) return .{ .value = self.valueRawSlice() };

            var out = std.ArrayList(u8).empty;
            errdefer out.deinit(alloc);
            const end = self.raw().subtree_end;
            var idx = self.index + 1;
            while (idx <= end and @as(usize, @intCast(idx)) < self.doc.nodes.len) : (idx += 1) {
                switch (self.doc.kindAt(idx)) {
                    .text => {
                        const materialized = try self.doc.materializeText(idx, alloc);
                        defer materialized.free(alloc);
                        try out.appendSlice(alloc, materialized.value);
                    },
                    .cdata => try out.appendSlice(alloc, self.doc.nodes[@intCast(idx)].valueSpan(idx).slice(self.doc.source)),
                    else => {},
                }
            }
            if (out.items.len == 0) {
                out.deinit(alloc);
                return .{ .value = "" };
            }
            return .{ .value = try out.toOwnedSlice(alloc), .owned = true };
        }

        pub fn querySelector(self: Self, selector: []const u8) ?Self {
            var idx = self.index + 1;
            const end = self.raw().subtree_end;
            while (idx <= end and @as(usize, @intCast(idx)) < self.doc.nodes.len) : (idx += 1) {
                const child = self.doc.nodeAt(idx).?;
                if (child.kind == .element and selectorMatches(child, selector)) return child;
            }
            return null;
        }

        pub fn querySelectorAll(self: Self, alloc: std.mem.Allocator, selector: []const u8) std.mem.Allocator.Error![]Self {
            var out = std.ArrayList(Self).empty;
            errdefer out.deinit(alloc);
            var idx = self.index + 1;
            const end = self.raw().subtree_end;
            while (idx <= end and @as(usize, @intCast(idx)) < self.doc.nodes.len) : (idx += 1) {
                const child = self.doc.nodeAt(idx).?;
                if (child.kind == .element and selectorMatches(child, selector)) try out.append(alloc, child);
            }
            return out.toOwnedSlice(alloc);
        }

        pub fn write(self: Self, writer: anytype) !void {
            try self.doc.writeNode(writer, self);
        }
    };
}

pub fn GetDocument(comptime options: ParseOptions) type {
    return struct {
        const Self = @This();
        pub const Options = options;
        pub const RawNode = GetRawNode(options);
        pub const Node = GetNode(options);
        pub const Attribute = GetAttribute(options);
        pub const AttributeIterator = GetAttributeIterator(options);
        const EntityMap = if (options.expand_dtd_entities) std.StringHashMap([]u8) else void;

        allocator: std.mem.Allocator,
        source: options.Input() = emptyInput(options),
        /// Finished node storage. Growth and parse scratch live in parser state.
        nodes: []RawNode = &[_]RawNode{},
        entity_map: EntityMap,

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .allocator = allocator,
                .entity_map = if (options.expand_dtd_entities) std.StringHashMap([]u8).init(allocator) else {},
            };
        }

        pub fn deinit(self: *Self) void {
            self.clearEntityMap();
            if (comptime options.expand_dtd_entities) self.entity_map.deinit();
            if (self.nodes.len != 0) self.allocator.free(self.nodes);
            self.nodes = &[_]RawNode{};
        }

        pub fn clear(self: *Self) void {
            self.clearEntityMap();
            if (self.nodes.len != 0) self.allocator.free(self.nodes);
            self.nodes = &[_]RawNode{};
            self.source = emptyInput(options);
        }

        inline fn clearEntityMap(self: *Self) void {
            if (comptime !options.expand_dtd_entities) return;
            if (self.entity_map.count() == 0) return;
            var it = self.entity_map.iterator();
            while (it.next()) |entry| {
                self.allocator.free(entry.key_ptr.*);
                self.allocator.free(entry.value_ptr.*);
            }
            self.entity_map.clearRetainingCapacity();
        }

        inline fn entityMap(self: *const Self) ?*const std.StringHashMap([]u8) {
            return if (comptime options.expand_dtd_entities) &self.entity_map else null;
        }

        fn decodeValueResult(self: *const Self, alloc: std.mem.Allocator, raw: []const u8) ValueError!common.SliceResult {
            if (std.mem.indexOfScalar(u8, raw, '&') == null) return .{ .value = raw };
            return .{
                .value = try entities.decodeAllocWithEntityMap(alloc, raw, options.validate_well_formedness, self.entityMap()),
                .owned = true,
            };
        }

        inline fn textState(self: *const Self, idx: IndexInt) TextMaterializationState {
            if (comptime options.non_destructive) return .raw;
            const node = &self.nodes[@intCast(idx)];
            const end: usize = @intCast(node.name_or_text.end);
            if (end >= self.source.len) return .raw;
            return switch (self.source[end]) {
                @intFromEnum(TextMaterializationState.decoded) => .decoded,
                @intFromEnum(TextMaterializationState.decode_failed) => .decode_failed,
                else => .raw,
            };
        }

        inline fn markTextState(self: *Self, idx: IndexInt, state: TextMaterializationState) void {
            if (comptime options.non_destructive) return;
            const end: usize = @intCast(self.nodes[@intCast(idx)].name_or_text.end);
            if (end < self.source.len) self.source[end] = @intFromEnum(state);
        }

        fn materializeText(self: *Self, idx: IndexInt, alloc: std.mem.Allocator) ValueError!common.SliceResult {
            const node = &self.nodes[@intCast(idx)];
            std.debug.assert(node.nodeKind(idx) == .text);
            if (comptime options.non_destructive) return self.decodeValueResult(alloc, node.name_or_text.slice(self.source));

            switch (self.textState(idx)) {
                .decoded => return .{ .value = node.name_or_text.slice(self.source) },
                .decode_failed => {
                    const raw = node.name_or_text.slice(self.source);
                    return .{
                        .value = try entities.decodeAllocWithEntityMap(alloc, raw, options.validate_well_formedness, self.entityMap()),
                        .owned = true,
                    };
                },
                .raw => {},
            }

            const original_end = node.name_or_text.end;
            const result = try entities.decodeInPlaceWithEntityMap(node.name_or_text.sliceMut(self.source), options.validate_well_formedness, self.entityMap());
            if (result.complete) {
                node.name_or_text.end = node.name_or_text.start + @as(IndexInt, @intCast(result.len));
                self.markTextState(idx, .decoded);
                return .{ .value = node.name_or_text.slice(self.source) };
            }

            node.name_or_text.end = original_end;
            self.markTextState(idx, .decode_failed);
            const raw = node.name_or_text.slice(self.source);
            return .{
                .value = try entities.decodeAllocWithEntityMap(alloc, raw, options.validate_well_formedness, self.entityMap()),
                .owned = true,
            };
        }

        pub fn registerDoctypeEntities(self: *Self, doctype_value: []const u8) ParseError!void {
            if (comptime !options.expand_dtd_entities) return;
            const subset_range = try findInternalSubset(doctype_value) orelse return;
            const subset = doctype_value[subset_range.start..subset_range.end];
            var declarations = std.StringHashMap([]const u8).init(self.allocator);
            defer declarations.deinit();
            var iterator = try ExpandedDtdIterator.init(self.allocator, subset, false);
            defer iterator.deinit();

            while (try iterator.next()) |decl| {
                if (decl.kind != .entity) continue;
                var i: usize = 0;
                if (!skipRequiredXmlWhitespace(decl.body, &i)) return error.InvalidDoctype;
                if (i < decl.body.len and decl.body[i] == '%') continue;
                const name_start = i;
                try consumeDtdName(decl.body, &i);
                const name = decl.body[name_start..i];
                if (!skipRequiredXmlWhitespace(decl.body, &i)) return error.InvalidDoctype;
                if (i >= decl.body.len or (decl.body[i] != '\'' and decl.body[i] != '"')) continue;
                const quote = decl.body[i];
                const value_start = i + 1;
                const value_end = std.mem.indexOfScalarPos(u8, decl.body, value_start, quote) orelse return error.InvalidDoctype;
                if (!self.entity_map.contains(name) and !declarations.contains(name)) {
                    try declarations.put(name, decl.body[value_start..value_end]);
                }
            }

            entities.resolveEntityDeclarationsBounded(
                self.allocator,
                &declarations,
                &self.entity_map,
                options.validate_well_formedness,
                options.max_entity_value_len,
            ) catch |err| switch (err) {
                error.OutputTooLarge => return error.EntityValueTooLarge,
                else => |e| return e,
            };
        }

        pub fn root(self: *const Self) ?Node {
            return @constCast(self).nodeAt(0);
        }

        pub inline fn kindAt(self: *const Self, idx: IndexInt) NodeType {
            return self.nodes[@intCast(idx)].nodeKind(idx);
        }

        /// Inclusive subtree tail. Compact text/misc nodes store zero in the raw
        /// field as their kind sentinel, so leaves derive their tail from index.
        inline fn subtreeEndAt(self: *const Self, idx: IndexInt) IndexInt {
            return switch (self.kindAt(idx)) {
                .document, .element => self.nodes[@intCast(idx)].subtree_end,
                else => idx,
            };
        }

        pub fn nodeAt(self: *const Self, idx: IndexInt) ?Node {
            if (idx == InvalidIndex or idx >= self.nodes.len) return null;
            const doc = @constCast(self);
            return .{ .doc = doc, .index = idx, .kind = doc.kindAt(idx) };
        }

        pub fn write(self: *const Self, writer: anytype) !void {
            const root_node = self.root() orelse return;
            try self.writeNode(writer, root_node);
        }

        fn writeNode(self: *const Self, writer: anytype, node: Node) !void {
            if (node.index == InvalidIndex or node.index >= self.nodes.len) return;
            const start = node.index;
            const end = self.subtreeEndAt(start);
            var open_idx: IndexInt = InvalidIndex;
            var idx = start;
            while (idx <= end and @as(usize, @intCast(idx)) < self.nodes.len) : (idx += 1) {
                while (open_idx != InvalidIndex and self.kindAt(open_idx) == .element and self.nodes[@intCast(open_idx)].subtree_end < idx) {
                    const closing = open_idx;
                    open_idx = self.nodes[@intCast(closing)].parent;
                    try self.writeCloseElement(writer, closing);
                }

                const raw = &self.nodes[@intCast(idx)];
                switch (self.kindAt(idx)) {
                    .document => {},
                    .element => {
                        try self.writeOpenElement(writer, idx);
                        if (raw.subtree_end == idx) {
                            try writer.writeAll("/>");
                        } else {
                            try writer.writeAll(">");
                            open_idx = idx;
                        }
                    },
                    .text => {
                        const text = raw.valueSpan(idx).slice(self.source);
                        if (comptime !options.non_destructive) {
                            if (self.textState(idx) == .decoded) {
                                try writeEscapedText(writer, text);
                            } else try writer.writeAll(text);
                        } else try writer.writeAll(text);
                    },
                    .comment => {
                        try writer.writeAll("<!--");
                        try writer.writeAll(raw.valueSpan(idx).slice(self.source));
                        try writer.writeAll("-->");
                    },
                    .cdata => {
                        try writer.writeAll("<![CDATA[");
                        try writer.writeAll(raw.valueSpan(idx).slice(self.source));
                        try writer.writeAll("]]>");
                    },
                    .pi, .declaration => {
                        try writer.writeAll("<?");
                        try writer.writeAll(raw.name_or_text.slice(self.source));
                        const value = raw.valueSpan(idx);
                        if (!value.isEmpty()) {
                            try writer.writeAll(" ");
                            try writer.writeAll(value.slice(self.source));
                        }
                        try writer.writeAll("?>");
                    },
                    .doctype => {
                        try writer.writeAll("<!DOCTYPE");
                        const value = raw.valueSpan(idx);
                        if (!value.isEmpty()) {
                            const bytes = value.slice(self.source);
                            if (!tables.isWhitespace(bytes[0])) try writer.writeAll(" ");
                            try writer.writeAll(bytes);
                        }
                        try writer.writeAll(">");
                    },
                }
            }

            while (open_idx != InvalidIndex and open_idx >= start and self.kindAt(open_idx) == .element) {
                const closing = open_idx;
                open_idx = self.nodes[@intCast(closing)].parent;
                try self.writeCloseElement(writer, closing);
            }
        }

        fn writeOpenElement(self: *const Self, writer: anytype, idx: IndexInt) !void {
            const raw = &self.nodes[@intCast(idx)];
            try writer.writeAll("<");
            try writer.writeAll(raw.name_or_text.slice(self.source));
            var attrs = attrs_mod.Iterator(options.non_destructive, options.validate_well_formedness).initElement(self.source, raw.name_or_text.end);
            while (attrs.next()) |raw_attr| {
                try writer.writeAll(" ");
                try writer.writeAll(raw_attr.name.slice(self.source));
                if (raw_attr.hasValue()) {
                    try writer.writeAll("=\"");
                    const value = raw_attr.value.slice(self.source);
                    if (raw_attr.value_state.isDecoded()) {
                        try writeEscapedAttributeValue(writer, value);
                    } else {
                        try writeDoubleQuotedAttributeValue(writer, value);
                    }
                    try writer.writeAll("\"");
                }
            }
        }

        fn writeCloseElement(self: *const Self, writer: anytype, idx: IndexInt) !void {
            try writer.writeAll("</");
            try writer.writeAll(self.nodes[@intCast(idx)].name_or_text.slice(self.source));
            try writer.writeAll(">");
        }
    };
}

fn writeEscapedText(writer: anytype, value: []const u8) !void {
    var start: usize = 0;
    for (value, 0..) |c, i| {
        const escaped: ?[]const u8 = switch (c) {
            '&' => "&amp;",
            '<' => "&lt;",
            '>' => "&gt;",
            else => null,
        };
        if (escaped) |bytes| {
            try writer.writeAll(value[start..i]);
            try writer.writeAll(bytes);
            start = i + 1;
        }
    }
    try writer.writeAll(value[start..]);
}

fn writeEscapedAttributeValue(writer: anytype, value: []const u8) !void {
    var start: usize = 0;
    for (value, 0..) |c, i| {
        const escaped: ?[]const u8 = switch (c) {
            '&' => "&amp;",
            '<' => "&lt;",
            '"' => "&quot;",
            else => null,
        };
        if (escaped) |bytes| {
            try writer.writeAll(value[start..i]);
            try writer.writeAll(bytes);
            start = i + 1;
        }
    }
    try writer.writeAll(value[start..]);
}

fn writeDoubleQuotedAttributeValue(writer: anytype, value: []const u8) !void {
    var start: usize = 0;
    while (std.mem.indexOfScalarPos(u8, value, start, '"')) |quote| {
        try writer.writeAll(value[start..quote]);
        try writer.writeAll("&quot;");
        start = quote + 1;
    }
    try writer.writeAll(value[start..]);
}

pub const SubsetRange = struct { start: usize, end: usize };

pub fn findInternalSubset(input: []const u8) ParseError!?SubsetRange {
    var i: usize = 0;
    var quote: u8 = 0;
    while (i < input.len) : (i += 1) {
        const c = input[i];
        if (quote != 0) {
            if (c == quote) quote = 0;
            continue;
        }
        if (c == '\'' or c == '"') {
            quote = c;
            continue;
        }
        if (c != '[') continue;

        const start = i + 1;
        var depth: usize = 1;
        i = start;
        while (i < input.len) : (i += 1) {
            const inner = input[i];
            if (quote != 0) {
                if (inner == quote) quote = 0;
                continue;
            }
            if (i + 3 < input.len and std.mem.eql(u8, input[i .. i + 4], "<!--")) {
                const end = std.mem.indexOfPos(u8, input, i + 4, "-->") orelse return error.UnexpectedEndOfData;
                i = end + 2;
                continue;
            }
            if (i + 1 < input.len and input[i] == '<' and input[i + 1] == '?') {
                const end = std.mem.indexOfPos(u8, input, i + 2, "?>") orelse return error.UnexpectedEndOfData;
                i = end + 1;
                continue;
            }
            if (inner == '\'' or inner == '"') {
                quote = inner;
                continue;
            }
            if (inner == '[') {
                depth += 1;
                continue;
            }
            if (inner == ']') {
                depth -= 1;
                if (depth == 0) return .{ .start = start, .end = i };
            }
        }
        return error.UnexpectedEndOfData;
    }
    return null;
}

fn findMarkupDeclEnd(input: []const u8, start: usize) ?usize {
    var i = start;
    var quote: u8 = 0;
    while (i < input.len) : (i += 1) {
        const c = input[i];
        if (quote != 0) {
            if (c == quote) quote = 0;
            continue;
        }
        if (c == '\'' or c == '"') {
            quote = c;
            continue;
        }
        if (c == '>') return i;
    }
    return null;
}

fn selectorMatches(node: anytype, selector: []const u8) bool {
    if (selector.len == 0 or node.kind != .element) return false;

    var rest = selector;
    if (rest[0] != '*' and rest[0] != '#' and rest[0] != '.' and rest[0] != '[') {
        var end: usize = 0;
        while (end < rest.len and rest[end] != '#' and rest[end] != '.' and rest[end] != '[') : (end += 1) {}
        if (!std.mem.eql(u8, node.nameSlice(), rest[0..end])) return false;
        rest = rest[end..];
    } else if (rest[0] == '*') {
        rest = rest[1..];
    }

    while (rest.len != 0) {
        switch (rest[0]) {
            '#' => {
                const part = selectorPart(rest[1..]);
                const id = node.getAttributeValueRaw("id") orelse return false;
                if (!std.mem.eql(u8, id, part.value)) return false;
                rest = part.rest;
            },
            '.' => {
                const part = selectorPart(rest[1..]);
                const class = node.getAttributeValueRaw("class") orelse return false;
                if (!hasClassToken(class, part.value)) return false;
                rest = part.rest;
            },
            '[' => {
                const close = std.mem.indexOfScalar(u8, rest, ']') orelse return false;
                const expr = rest[1..close];
                if (std.mem.indexOfScalar(u8, expr, '=')) |eq| {
                    const name = trimAscii(expr[0..eq]);
                    const want = trimQuotes(trimAscii(expr[eq + 1 ..]));
                    const got = node.getAttributeValueRaw(name) orelse return false;
                    if (!std.mem.eql(u8, got, want)) return false;
                } else if (node.getAttributeValueRaw(trimAscii(expr)) == null) return false;
                rest = rest[close + 1 ..];
            },
            else => return false,
        }
    }
    return true;
}

const SelectorPart = struct {
    value: []const u8,
    rest: []const u8,
};

fn selectorPart(input: []const u8) SelectorPart {
    var end: usize = 0;
    while (end < input.len and input[end] != '#' and input[end] != '.' and input[end] != '[') : (end += 1) {}
    return .{ .value = input[0..end], .rest = input[end..] };
}

fn hasClassToken(class: []const u8, token: []const u8) bool {
    if (token.len == 0) return false;
    var i: usize = 0;
    while (i < class.len) {
        while (i < class.len and tables.isWhitespace(class[i])) : (i += 1) {}
        const start = i;
        while (i < class.len and !tables.isWhitespace(class[i])) : (i += 1) {}
        if (std.mem.eql(u8, class[start..i], token)) return true;
    }
    return false;
}

fn trimAscii(input: []const u8) []const u8 {
    var start: usize = 0;
    var end = input.len;
    while (start < end and tables.isWhitespace(input[start])) : (start += 1) {}
    while (end > start and tables.isWhitespace(input[end - 1])) : (end -= 1) {}
    return input[start..end];
}

fn trimQuotes(input: []const u8) []const u8 {
    if (input.len >= 2 and ((input[0] == '\'' and input[input.len - 1] == '\'') or (input[0] == '"' and input[input.len - 1] == '"'))) {
        return input[1 .. input.len - 1];
    }
    return input;
}

test "generated DOM layout removes disabled metadata" {
    const compact = ParseOptions{};
    const full = ParseOptions{ .store_last_child = true, .store_prev_sibling = true };
    const rich = ParseOptions{ .include_misc_nodes = true };

    const CompactNode = compact.Document().RawNode;
    const FullNode = full.Document().RawNode;
    const RichNode = rich.Document().RawNode;

    try std.testing.expectEqual(@as(usize, @sizeOf(IndexInt) * 4), @sizeOf(CompactNode));
    try std.testing.expect(@sizeOf(FullNode) > @sizeOf(CompactNode));
    try std.testing.expect(@sizeOf(RichNode) > @sizeOf(CompactNode));
    try std.testing.expectEqual(void, @FieldType(CompactNode, "last_child"));
    try std.testing.expectEqual(void, @FieldType(CompactNode, "prev_sibling"));
    try std.testing.expectEqual(void, @FieldType(CompactNode, "kind"));

    const CompactDocument = compact.Document();
    const DtdDocument = (ParseOptions{ .expand_dtd_entities = true }).Document();
    try std.testing.expectEqual(void, @FieldType(CompactDocument, "entity_map"));
    try std.testing.expect(@FieldType(DtdDocument, "entity_map") != void);
    try std.testing.expect(@sizeOf(CompactDocument) < @sizeOf(DtdDocument));
}

test "parse source mutability is selected at comptime" {
    try std.testing.expectEqual([]u8, (ParseOptions{}).Input());
    try std.testing.expectEqual([]const u8, (ParseOptions{ .non_destructive = true }).Input());
}

test "Span helpers expose slices and lengths" {
    const buf = "abcdef";
    const span: Span = .{ .start = 1, .end = 4 };
    try std.testing.expectEqual(@as(IndexInt, 3), span.len());
    try std.testing.expectEqualStrings("bcd", span.slice(buf));
}

test "parse diagnostics treat CRLF and CR as line endings" {
    const crlf = ParseDiagnostic{ .err = error.ExpectedGt, .offset = 5, .source = "a\r\nb\nc" };
    try std.testing.expectEqual(ParseDiagnostic.Location{ .line = 3, .column = 1 }, crlf.location());
    const cr = ParseDiagnostic{ .err = error.ExpectedGt, .offset = 4, .source = "a\rb\rc" };
    try std.testing.expectEqual(ParseDiagnostic.Location{ .line = 3, .column = 1 }, cr.location());
}

test "XML Name validation handles ASCII Unicode and malformed UTF-8 in one pass" {
    try std.testing.expect(isValidXmlName("root"));
    try std.testing.expect(isValidXmlName("a-b.c_7"));
    try std.testing.expect(isValidXmlName("\xC3\xA9l\xC3\xA9ment"));
    try std.testing.expect(isValidXmlName("a\xC2\xB7b"));
    try std.testing.expect(!isValidXmlName("7root"));
    try std.testing.expect(!isValidXmlName("\xC3\x97"));
    try std.testing.expect(!isValidXmlName("a\xCD\xBE"));
    try std.testing.expect(!isValidXmlName("\xC3"));
    try std.testing.expect(!isValidXmlName("\xC0\xAF"));
}

test "assume-valid UTF-8 XML Name classifier matches range boundaries" {
    const codepoints = [_]u21{
        0xB7,   0xBF,   0xC0,    0xD6,    0xD7,    0xD8,     0xF6,   0xF7,   0xF8,
        0x2FF,  0x300,  0x36F,   0x370,   0x37D,   0x37E,    0x37F,  0x1FFF, 0x2000,
        0x200B, 0x200C, 0x200D,  0x200E,  0x203E,  0x203F,   0x2040, 0x2041, 0x206F,
        0x2070, 0x218F, 0x2190,  0x2BFF,  0x2C00,  0x2FEF,   0x2FF0, 0x3000, 0x3001,
        0xD7FF, 0xE000, 0xF8FF,  0xF900,  0xFDCF,  0xFDD0,   0xFDEF, 0xFDF0, 0xFFFD,
        0xFFFE, 0xFFFF, 0x10000, 0xEFFFF, 0xF0000, 0x10FFFF,
    };

    for (codepoints) |cp| {
        var encoded: [4]u8 = undefined;
        const len = try std.unicode.utf8Encode(cp, &encoded);
        const first_name = encoded[0..len];
        try std.testing.expectEqual(isValidXmlName(first_name), isValidXmlNameAssumeValidUtf8(first_name));

        var continued: [5]u8 = undefined;
        continued[0] = 'a';
        @memcpy(continued[1 .. len + 1], encoded[0..len]);
        const continued_name = continued[0 .. len + 1];
        try std.testing.expectEqual(isValidXmlName(continued_name), isValidXmlNameAssumeValidUtf8(continued_name));
    }
}

test "validateDoctype enforces the outer XML grammar" {
    const valid = [_][]const u8{
        " r",
        " r ",
        " r[]",
        " r [<!ELEMENT r EMPTY>] ",
        " r SYSTEM 'urn:test'",
        " r SYSTEM \"\"[]",
        " r PUBLIC '-//W3C//DTD XHTML 1.0//EN' 'about:legacy-compat'",
    };
    for (valid) |value| {
        const info = try validateDoctype(value);
        try std.testing.expectEqualStrings("r", value[info.name_start..info.name_end]);
    }

    const invalid = [_][]const u8{
        "",
        "r",
        " 1r",
        " \xC3\x97",
        " r garbage",
        " r SYSTEM'urn:test'",
        " r SYSTEM urn:test",
        " r PUBLIC 'id'",
        " r PUBLIC '^' 'sys'",
        " r PUBLIC 'id''sys'",
        " r [<!ELEMENT r EMPTY>] trailing",
    };
    for (invalid) |value| try std.testing.expectError(error.InvalidDoctype, validateDoctype(value));
}

test "validateDoctype handles deeply nested content models iteratively" {
    var value: std.ArrayList(u8) = .empty;
    defer value.deinit(std.testing.allocator);

    try value.appendSlice(std.testing.allocator, " r [<!ELEMENT r ");
    for (0..4096) |_| try value.append(std.testing.allocator, '(');
    try value.append(std.testing.allocator, 'a');
    for (0..4096) |_| try value.append(std.testing.allocator, ')');
    try value.appendSlice(std.testing.allocator, ">]");

    const info = try validateDoctypeAlloc(std.testing.allocator, value.items);
    try std.testing.expectEqualStrings("r", value.items[info.name_start..info.name_end]);
}

test "destructive text materialization caches decoded bytes in source" {
    const opts: ParseOptions = .{};
    var source = "<r>a&amp;b</r>".*;
    var doc = try opts.parse(std.testing.allocator, &source);
    defer doc.deinit();

    const text = doc.nodeAt(1).?.firstChild().?;
    const first = try text.value(std.testing.allocator);
    defer first.free(std.testing.allocator);
    try std.testing.expect(!first.owned);
    try std.testing.expectEqualStrings("a&b", first.value);
    try std.testing.expectEqualStrings("a&b", text.valueRawSlice());

    const after_first = source;
    const second = try text.value(std.testing.allocator);
    defer second.free(std.testing.allocator);
    try std.testing.expect(!second.owned);
    try std.testing.expectEqualStrings("a&b", second.value);
    try std.testing.expectEqualSlices(u8, &after_first, &source);

    var out: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer out.deinit();
    try doc.write(&out.writer);
    try std.testing.expectEqualStrings("<r>a&amp;b</r>", out.written());
}

test "raw attribute lookup does not trigger destructive materialization" {
    const opts: ParseOptions = .{};
    var source = "<r a='&amp;' b='two'/>".*;
    var doc = try opts.parse(std.testing.allocator, &source);
    defer doc.deinit();

    const before = source;
    const root = doc.nodeAt(1).?;
    try std.testing.expectEqualStrings("&amp;", root.getAttributeValueRaw("a").?);
    try std.testing.expectEqualStrings("two", root.getAttributeValueRaw("b").?);
    try std.testing.expectEqualSlices(u8, &before, &source);
}

test "destructive attribute materialization caches decoded bytes and preserves handles" {
    const opts: ParseOptions = .{};
    var source = "<r a='&amp;' b='second' c='&lt;'></r>".*;
    var doc = try opts.parse(std.testing.allocator, &source);
    defer doc.deinit();

    const root = doc.nodeAt(1).?;
    var attrs = root.attributes();
    const a = attrs.next() orelse return error.TestUnexpectedResult;
    const b = attrs.next() orelse return error.TestUnexpectedResult;

    const first = try a.value(std.testing.allocator);
    defer first.free(std.testing.allocator);
    try std.testing.expect(!first.owned);
    try std.testing.expectEqualStrings("&", first.value);
    try std.testing.expectEqualStrings("b", b.nameSlice());
    try std.testing.expectEqualStrings("second", b.valueRawSlice());

    const after_first = source;
    const second = try a.value(std.testing.allocator);
    defer second.free(std.testing.allocator);
    try std.testing.expect(!second.owned);
    try std.testing.expectEqualStrings("&", second.value);
    try std.testing.expectEqualSlices(u8, &after_first, &source);

    const c = try root.getAttributeValue(std.testing.allocator, "c") orelse return error.TestUnexpectedResult;
    defer c.free(std.testing.allocator);
    try std.testing.expect(!c.owned);
    try std.testing.expectEqualStrings("<", c.value);

    var out: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer out.deinit();
    try doc.write(&out.writer);
    try std.testing.expectEqualStrings("<r a=\"&amp;\" b=\"second\" c=\"&lt;\"/>", out.written());
}

test "expanding DTD attribute uses owned fallback while shrinkable peers cache" {
    const opts: ParseOptions = .{ .expand_dtd_entities = true };
    var source = "<!DOCTYPE r [<!ENTITY x 'EXPANDED'>]><r a='&x;' b='&amp;'></r>".*;
    var doc = try opts.parse(std.testing.allocator, &source);
    defer doc.deinit();

    const root = doc.root().?.firstChild().?;
    const a = root.firstAttribute() orelse return error.TestUnexpectedResult;
    var attrs = root.attributes();
    _ = attrs.next() orelse return error.TestUnexpectedResult;
    const b = attrs.next() orelse return error.TestUnexpectedResult;

    const expanded = try a.value(std.testing.allocator);
    defer expanded.free(std.testing.allocator);
    try std.testing.expect(expanded.owned);
    try std.testing.expectEqualStrings("EXPANDED", expanded.value);
    try std.testing.expectEqualStrings("&x;", a.valueRawSlice());

    const cached = try b.value(std.testing.allocator);
    defer cached.free(std.testing.allocator);
    try std.testing.expect(!cached.owned);
    try std.testing.expectEqualStrings("&", cached.value);
    try std.testing.expectEqualStrings("b", b.nameSlice());
}

test "non destructive text decoding owns fallback and preserves source" {
    const opts: ParseOptions = .{ .non_destructive = true };
    const source = "<r>a&amp;b</r>";
    var doc = try opts.parse(std.testing.allocator, source);
    defer doc.deinit();

    const value = try doc.nodeAt(1).?.firstChild().?.value(std.testing.allocator);
    defer value.free(std.testing.allocator);
    try std.testing.expect(value.owned);
    try std.testing.expectEqualStrings("a&b", value.value);
    try std.testing.expectEqualStrings("<r>a&amp;b</r>", source);
}

test "expanding DTD text uses owned fallback without partial source decode" {
    const opts: ParseOptions = .{ .expand_dtd_entities = true };
    var source = "<!DOCTYPE r [<!ENTITY x 'EXPANDED'>]><r>&x;</r>".*;
    var doc = try opts.parse(std.testing.allocator, &source);
    defer doc.deinit();

    const root = doc.nodeAt(1).?;
    const text = root.firstChild().?;
    const before_raw = try std.testing.allocator.dupe(u8, text.valueRawSlice());
    defer std.testing.allocator.free(before_raw);
    const value = try text.value(std.testing.allocator);
    defer value.free(std.testing.allocator);
    try std.testing.expect(value.owned);
    try std.testing.expectEqualStrings("EXPANDED", value.value);
    try std.testing.expectEqualSlices(u8, before_raw, text.valueRawSlice());
}
