const std = @import("std");
const builtin = @import("builtin");
const common = @import("common.zig");
const parser = @import("parser.zig");
const entities = @import("entities.zig");
const tables = @import("tables.zig");

pub const IndexInt = common.IndexInt;
pub const InvalidIndex: IndexInt = common.InvalidIndex;

const xml_scan_vector_len: comptime_int = switch (builtin.cpu.arch) {
    .x86, .x86_64 => if (std.Target.x86.featureSetHas(builtin.cpu.features, .avx2)) 32 else 16,
    else => 16,
};

pub const ParseMode = enum {
    turbo,
    strict,
};

pub const ParseOptions = struct {
    mode: ParseMode = .turbo,
    validate_closing_tags: bool = false,
    require_closed_elements_on_eof: bool = false,
    expand_dtd_entities: bool = false,
    max_entity_value_len: usize = 4096,
    drop_whitespace_text_nodes: bool = true,
    include_misc_nodes: bool = true,

    /// Parses `input` and returns an owned document for this option set.
    pub fn parse(comptime options: @This(), allocator: std.mem.Allocator, input: []const u8) ParseError!options.Document() {
        var doc = options.Document().init(allocator);
        errdefer doc.deinit();
        try doc.parse(input, options);
        return doc;
    }

    /// Returns the document type for this option set.
    pub fn Document(comptime options: @This()) type {
        return Types(options).Document;
    }
};

pub fn Types(comptime options: ParseOptions) type {
    _ = options;
    const Self = @This();
    return struct {
        pub const IndexInt = Self.IndexInt;
        pub const Span = Self.Span;
        pub const RawAttribute = Self.RawAttribute;
        pub const Attribute = Self.Attribute;
        pub const RawNode = Self.RawNode;
        pub const Node = Self.Node;
        pub const Document = Self.Document;
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
) ParseError!void {
    return validateXmlReferencesInContextAlloc(allocator, value, allow_trailing_partial, doctype_value, require_declared_entities, .content);
}

pub fn validateXmlAttributeReferencesAlloc(
    allocator: std.mem.Allocator,
    value: []const u8,
    doctype_value: ?[]const u8,
    require_declared_entities: bool,
) ParseError!void {
    return validateXmlReferencesInContextAlloc(allocator, value, false, doctype_value, require_declared_entities, .attribute);
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
) ParseError!void {
    if (!try validateXmlReferenceSyntax(value, allow_trailing_partial)) return;

    var catalog = GeneralEntityCatalog.init(allocator);
    defer catalog.deinit();
    if (doctype_value) |doctype| try buildGeneralEntityCatalog(&catalog, doctype);
    try validateCustomXmlReferencesUsingCatalog(allocator, value, &catalog, require_declared_entities, context);
}

fn validateXmlReferenceSyntax(value: []const u8, allow_trailing_partial: bool) ParseError!bool {
    var has_custom_reference = false;
    var search_from: usize = 0;
    while (std.mem.indexOfScalarPos(u8, value, search_from, '&')) |amp| {
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
            has_custom_reference = true;
        }
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
            try validateGeneralEntityUse(catalog, &states, &frames, body, require_declared_entities, context);
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
        const amp = std.mem.indexOfScalarPos(u8, frame.replacement, frame.offset, '&') orelse {
            if (context == .attribute and std.mem.indexOfScalarPos(u8, frame.replacement, frame.offset, '<') != null) {
                return error.InvalidAttributeValue;
            }
            states.getPtr(frame.name).?.* = .done;
            frames.items.len -= 1;
            continue;
        };
        if (context == .attribute) {
            if (std.mem.indexOfScalarPos(u8, frame.replacement, frame.offset, '<')) |lt| {
                if (lt < amp) return error.InvalidAttributeValue;
            }
        }
        const semi = std.mem.indexOfScalarPos(u8, frame.replacement, amp + 1, ';') orelse return error.UnterminatedEntity;
        const body = frame.replacement[amp + 1 .. semi];
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

pub fn xmlValidPrefixLen(input: []const u8) ParseError!usize {
    const Vec = @Vector(xml_scan_vector_len, u8);
    const high_bit: Vec = @splat(0x80);
    const control_limit: Vec = @splat(0x20);
    const tab: Vec = @splat('\t');
    const newline: Vec = @splat('\n');
    const carriage_return: Vec = @splat('\r');

    var i: usize = 0;
    while (i < input.len) {
        // XML is overwhelmingly ASCII. Validate full SIMD-width runs at once and
        // drop to the scalar path only for non-ASCII or forbidden controls.
        while (i + @sizeOf(Vec) <= input.len) {
            const bytes: Vec = input[i..][0..@sizeOf(Vec)].*;
            const invalid_control = (bytes < control_limit) &
                (bytes != tab) & (bytes != newline) & (bytes != carriage_return);
            if (@reduce(.Or, (bytes >= high_bit) | invalid_control)) break;
            i += @sizeOf(Vec);
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

pub fn validateXmlCharacters(input: []const u8) ParseError!void {
    if (try xmlValidPrefixLen(input) != input.len) return error.InvalidXmlCharacter;
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
pub fn validateDoctypeEntityConstraintsAlloc(
    allocator: std.mem.Allocator,
    value: []const u8,
    require_declared_entities: bool,
) ParseError!void {
    const subset_range = try findInternalSubset(value) orelse return;
    const subset = value[subset_range.start..subset_range.end];

    var catalog = GeneralEntityCatalog.init(allocator);
    defer catalog.deinit();
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
/// left out, but the complete syntax and internal-subset PE restriction are
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
/// left out, but the complete syntax and internal-subset PE restriction are
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

pub const ParseStackEntry = struct {
    idx: IndexInt,
    tag_key: u64 = 0,
    tag_len: IndexInt = 0,
};

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

pub const Span = struct {
    start: IndexInt = 0,
    end: IndexInt = 0,

    pub fn len(self: @This()) IndexInt {
        return self.end - self.start;
    }

    pub fn isEmpty(self: @This()) bool {
        return self.start == self.end;
    }

    pub fn slice(self: @This(), source: []const u8) []const u8 {
        return source[self.start..self.end];
    }
};

pub const RawAttribute = struct {
    name: Span,
    value: Span,
};

pub const RawNode = struct {
    kind: NodeType,
    name: Span = .{},
    /// Text/value span for non-elements; half-open attribute-index span for elements.
    data: Span = .{},

    parent: IndexInt = InvalidIndex,
    /// Index of the last direct child, which makes append and reverse-sibling
    /// traversal O(1) without a separate sibling list allocation.
    last_child: IndexInt = InvalidIndex,
    /// Previous direct sibling in document order. `nextSibling()` is derived
    /// from `subtree_end + 1`.
    prev_sibling: IndexInt = InvalidIndex,
    /// Inclusive end index of this node's flattened subtree in `nodes.items`.
    subtree_end: IndexInt = 0,

    pub inline fn valueSpan(self: @This()) Span {
        return self.data;
    }

    pub inline fn attributeSpan(self: @This()) Span {
        return self.data;
    }
};

const ValueError = std.mem.Allocator.Error || entities.DecodeError;

pub const Attribute = struct {
    doc: *Document,
    index: IndexInt,

    inline fn raw(self: @This()) *const RawAttribute {
        return &self.doc.attrs.items[self.index];
    }

    pub fn nameSlice(self: @This()) []const u8 {
        return self.raw().name.slice(self.doc.source);
    }

    pub fn valueRawSlice(self: @This()) []const u8 {
        return self.raw().value.slice(self.doc.source);
    }

    pub fn namespacePrefix(self: @This()) ?[]const u8 {
        const name = self.nameSlice();
        const split = std.mem.indexOfScalar(u8, name, ':') orelse return null;
        return name[0..split];
    }

    pub fn localName(self: @This()) []const u8 {
        const name = self.nameSlice();
        const split = std.mem.indexOfScalar(u8, name, ':') orelse return name;
        return name[split + 1 ..];
    }

    pub fn value(self: @This(), alloc: std.mem.Allocator) ValueError![]u8 {
        return self.doc.decodeValueAlloc(alloc, self.valueRawSlice());
    }

    pub fn write(self: @This(), writer: anytype) !void {
        try writer.writeAll(self.nameSlice());
        try writer.writeAll("=\"");
        try writeDoubleQuotedAttributeValue(writer, self.valueRawSlice());
        try writer.writeAll("\"");
    }
};

pub const Node = struct {
    doc: *Document,
    index: IndexInt,
    kind: NodeType,

    inline fn raw(self: @This()) *const RawNode {
        return &self.doc.nodes.items[self.index];
    }

    inline fn findAttributeIndex(self: @This(), name: []const u8) ?IndexInt {
        if (self.kind != .element) return null;
        const node_raw = self.raw();
        const range = node_raw.attributeSpan();
        var i = range.start;
        const end = range.end;
        while (i < end) : (i += 1) {
            if (std.mem.eql(u8, self.doc.attrs.items[i].name.slice(self.doc.source), name)) {
                return i;
            }
        }
        return null;
    }

    pub fn nameSlice(self: @This()) []const u8 {
        return self.raw().name.slice(self.doc.source);
    }

    pub fn namespacePrefix(self: @This()) ?[]const u8 {
        const name = self.nameSlice();
        const split = std.mem.indexOfScalar(u8, name, ':') orelse return null;
        return name[0..split];
    }

    pub fn localName(self: @This()) []const u8 {
        const name = self.nameSlice();
        const split = std.mem.indexOfScalar(u8, name, ':') orelse return name;
        return name[split + 1 ..];
    }

    pub fn namespaceUri(self: @This()) ?[]const u8 {
        if (self.kind != .element) return null;
        const prefix = self.namespacePrefix();
        if (prefix) |p| {
            if (std.mem.eql(u8, p, "xml")) return "http://www.w3.org/XML/1998/namespace";
        }
        var cur: ?Node = self;
        while (cur) |node| : (cur = node.parentNode()) {
            const node_raw = node.raw();
            const range = node_raw.attributeSpan();
            var i = range.start;
            const end = range.end;
            while (i < end) : (i += 1) {
                const attr = node.doc.attrs.items[i];
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

    pub fn valueRawSlice(self: @This()) []const u8 {
        if (self.kind == .element or self.kind == .document) return "";
        return self.raw().valueSpan().slice(self.doc.source);
    }

    pub fn value(self: @This(), alloc: std.mem.Allocator) ValueError![]u8 {
        const raw_value = self.valueRawSlice();
        if (self.kind == .text) return self.doc.decodeValueAlloc(alloc, raw_value);
        return alloc.dupe(u8, raw_value);
    }

    pub fn firstChild(self: @This()) ?Node {
        const node_raw = self.raw();
        if (node_raw.subtree_end <= self.index) return null;
        return self.doc.nodeAt(self.index + 1);
    }

    pub fn lastChild(self: @This()) ?Node {
        return self.doc.nodeAt(self.raw().last_child);
    }

    pub fn nextSibling(self: @This()) ?Node {
        const next_idx = self.raw().subtree_end + 1;
        if (@as(usize, @intCast(next_idx)) >= self.doc.nodes.items.len) return null;
        if (self.doc.nodes.items[next_idx].prev_sibling != self.index) return null;
        return self.doc.nodeAt(next_idx);
    }

    pub fn prevSibling(self: @This()) ?Node {
        return self.doc.nodeAt(self.raw().prev_sibling);
    }

    pub fn parentNode(self: @This()) ?Node {
        return self.doc.nodeAt(self.raw().parent);
    }

    pub fn getAttributeValueRaw(self: @This(), name: []const u8) ?[]const u8 {
        const idx = self.findAttributeIndex(name) orelse return null;
        return self.doc.attrs.items[idx].value.slice(self.doc.source);
    }

    pub fn getAttributeValue(self: @This(), alloc: std.mem.Allocator, name: []const u8) ValueError!?[]u8 {
        const raw_value = self.getAttributeValueRaw(name) orelse return null;
        return try self.doc.decodeValueAlloc(alloc, raw_value);
    }

    pub fn firstAttribute(self: @This()) ?Attribute {
        if (self.kind != .element) return null;
        const node_raw = self.raw();
        const range = node_raw.attributeSpan();
        if (range.start == range.end) return null;
        return .{ .doc = self.doc, .index = range.start };
    }

    /// Returns a borrowed raw text slice when the subtree's text content is
    /// exactly one contiguous text node; otherwise returns null.
    pub fn innerTextRaw(self: @This()) ?[]const u8 {
        if (self.kind == .text or self.kind == .cdata) return self.valueRawSlice();

        const node_raw = self.raw();
        var first: ?[]const u8 = null;
        var idx = self.index + 1;
        while (idx <= node_raw.subtree_end and idx < self.doc.nodes.items.len) : (idx += 1) {
            const child = self.doc.nodes.items[idx];
            if (child.kind != .text and child.kind != .cdata) continue;
            if (first != null) return null;
            first = child.valueSpan().slice(self.doc.source);
        }
        return first orelse "";
    }

    /// Materializes subtree text into a dedicated decoded allocation.
    pub fn innerText(self: @This(), alloc: std.mem.Allocator) ValueError![]u8 {
        if (self.kind == .text or self.kind == .cdata) return self.value(alloc);

        var out = std.ArrayList(u8).empty;
        errdefer out.deinit(alloc);

        const node_raw = self.raw();
        var idx = self.index + 1;
        while (idx <= node_raw.subtree_end and idx < self.doc.nodes.items.len) : (idx += 1) {
            const child = self.doc.nodes.items[idx];
            switch (child.kind) {
                .text => try self.doc.appendDecodedValue(&out, alloc, child.valueSpan().slice(self.doc.source)),
                .cdata => try out.appendSlice(alloc, child.valueSpan().slice(self.doc.source)),
                else => {},
            }
        }
        return out.toOwnedSlice(alloc);
    }

    pub fn querySelector(self: @This(), selector: []const u8) ?Node {
        var idx = self.index + 1;
        const end = self.raw().subtree_end;
        while (idx <= end and idx < self.doc.nodes.items.len) : (idx += 1) {
            const child = self.doc.nodeAt(idx).?;
            if (child.kind == .element and selectorMatches(child, selector)) return child;
        }
        return null;
    }

    pub fn querySelectorAll(self: @This(), alloc: std.mem.Allocator, selector: []const u8) std.mem.Allocator.Error![]Node {
        var out = std.ArrayList(Node).empty;
        errdefer out.deinit(alloc);

        var idx = self.index + 1;
        const end = self.raw().subtree_end;
        while (idx <= end and idx < self.doc.nodes.items.len) : (idx += 1) {
            const child = self.doc.nodeAt(idx).?;
            if (child.kind == .element and selectorMatches(child, selector)) try out.append(alloc, child);
        }
        return out.toOwnedSlice(alloc);
    }

    pub fn write(self: @This(), writer: anytype) !void {
        try self.doc.writeNode(writer, self);
    }
};

pub const Document = struct {
    allocator: std.mem.Allocator,
    source: []const u8 = "",
    parse_mode: ParseMode = .turbo,
    expand_dtd_entities: bool = false,
    max_entity_value_len: usize = 4096,
    /// Largest input size we have reserved arrays for so repeated parses can
    /// reuse capacity instead of re-growing on every call.
    reserved_input_hint_len: usize = 0,
    last_error_offset: usize = 0,

    nodes: std.ArrayList(RawNode) = .empty,
    attrs: std.ArrayList(RawAttribute) = .empty,
    /// Kept compact because every parse mode uses this parent stack.
    parse_stack: std.ArrayList(IndexInt) = .empty,
    /// Interleaved validation stack selected only by strict/validated parses.
    parse_validate_stack: std.ArrayList(ParseStackEntry) = .empty,
    entity_map: std.StringHashMap([]u8),

    pub fn init(allocator: std.mem.Allocator) Document {
        return .{
            .allocator = allocator,
            .entity_map = std.StringHashMap([]u8).init(allocator),
        };
    }

    pub fn deinit(self: *Document) void {
        self.clearEntityMap();
        self.entity_map.deinit();
        self.nodes.deinit(self.allocator);
        self.attrs.deinit(self.allocator);
        self.parse_stack.deinit(self.allocator);
        self.parse_validate_stack.deinit(self.allocator);
    }

    inline fn resetParsedData(self: *Document) void {
        self.clearEntityMap();
        self.nodes.items.len = 0;
        self.attrs.items.len = 0;
        self.parse_stack.items.len = 0;
        self.parse_validate_stack.items.len = 0;
    }

    pub fn clear(self: *Document) void {
        self.resetParsedData();
        self.last_error_offset = 0;
        self.source = "";
        self.parse_mode = .turbo;
        self.expand_dtd_entities = false;
        self.max_entity_value_len = 4096;
    }

    pub fn parse(noalias self: *Document, input: []const u8, comptime opts: ParseOptions) ParseError!void {
        self.resetParsedData();
        self.source = input;
        self.parse_mode = opts.mode;
        self.expand_dtd_entities = opts.expand_dtd_entities;
        self.max_entity_value_len = opts.max_entity_value_len;
        try parser.parseInto(self, input, opts);
    }

    pub fn parseDiagnostic(noalias self: *Document, input: []const u8, comptime opts: ParseOptions) ?ParseDiagnostic {
        self.parse(input, opts) catch |err| return .{
            .err = err,
            .offset = self.last_error_offset,
            .source = input,
        };
        return null;
    }

    inline fn clearEntityMap(self: *Document) void {
        if (self.entity_map.count() == 0) return;
        var it = self.entity_map.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.entity_map.clearRetainingCapacity();
    }

    fn decodeValueAlloc(self: *const Document, alloc: std.mem.Allocator, raw: []const u8) ValueError![]u8 {
        if (!self.expand_dtd_entities) {
            return entities.decodeAllocWithEntityMap(alloc, raw, self.parse_mode == .strict, null);
        }
        return entities.decodeAllocWithEntityMap(alloc, raw, self.parse_mode == .strict, &self.entity_map);
    }

    fn appendDecodedValue(self: *const Document, out: *std.ArrayList(u8), alloc: std.mem.Allocator, raw: []const u8) ValueError!void {
        if (!self.expand_dtd_entities) {
            return entities.appendDecodedWithEntityMap(out, alloc, raw, self.parse_mode == .strict, null);
        }
        return entities.appendDecodedWithEntityMap(out, alloc, raw, self.parse_mode == .strict, &self.entity_map);
    }

    /// Scans the expanded internal subset for simple general-entity declarations
    /// and stores owned decoded values for later decoded text/attribute access.
    pub fn registerDoctypeEntities(self: *Document, doctype_value: []const u8) ParseError!void {
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

        if (self.expand_dtd_entities) {
            entities.resolveEntityDeclarationsBounded(
                self.allocator,
                &declarations,
                &self.entity_map,
                self.parse_mode == .strict,
                self.max_entity_value_len,
            ) catch |err| switch (err) {
                error.OutputTooLarge => return error.EntityValueTooLarge,
                else => |e| return e,
            };
        }
    }

    pub fn root(self: *const Document) ?Node {
        return @constCast(self).nodeAt(0);
    }

    pub fn nodeAt(self: *const Document, idx: IndexInt) ?Node {
        if (idx == InvalidIndex or @as(usize, @intCast(idx)) >= self.nodes.items.len) return null;
        const doc = @constCast(self);
        return .{
            .doc = doc,
            .index = idx,
            .kind = doc.nodes.items[idx].kind,
        };
    }

    pub fn write(self: *const Document, writer: anytype) !void {
        const root_node = self.root() orelse return;
        try self.writeNode(writer, root_node);
    }

    fn writeNode(self: *const Document, writer: anytype, node: Node) !void {
        if (node.index == InvalidIndex or @as(usize, @intCast(node.index)) >= self.nodes.items.len) return;

        const start = node.index;
        const end = self.nodes.items[start].subtree_end;
        var open_idx: IndexInt = InvalidIndex;

        var idx = start;
        while (idx <= end and @as(usize, @intCast(idx)) < self.nodes.items.len) : (idx += 1) {
            while (open_idx != InvalidIndex and
                self.nodes.items[open_idx].kind == .element and
                self.nodes.items[open_idx].subtree_end < idx)
            {
                const closing = open_idx;
                open_idx = self.nodes.items[closing].parent;
                try self.writeCloseElement(writer, closing);
            }

            const raw = self.nodes.items[idx];
            switch (raw.kind) {
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
                .text => try writer.writeAll(raw.valueSpan().slice(self.source)),
                .comment => {
                    try writer.writeAll("<!--");
                    try writer.writeAll(raw.valueSpan().slice(self.source));
                    try writer.writeAll("-->");
                },
                .cdata => {
                    try writer.writeAll("<![CDATA[");
                    try writer.writeAll(raw.valueSpan().slice(self.source));
                    try writer.writeAll("]]>");
                },
                .pi, .declaration => {
                    try writer.writeAll("<?");
                    try writer.writeAll(raw.name.slice(self.source));
                    if (!raw.valueSpan().isEmpty()) {
                        try writer.writeAll(" ");
                        try writer.writeAll(raw.valueSpan().slice(self.source));
                    }
                    try writer.writeAll("?>");
                },
                .doctype => {
                    try writer.writeAll("<!DOCTYPE");
                    if (!raw.valueSpan().isEmpty()) {
                        const value = raw.valueSpan().slice(self.source);
                        if (!tables.isWhitespace(value[0])) try writer.writeAll(" ");
                        try writer.writeAll(value);
                    }
                    try writer.writeAll(">");
                },
            }
        }

        while (open_idx != InvalidIndex and
            open_idx >= start and
            self.nodes.items[open_idx].kind == .element)
        {
            const closing = open_idx;
            open_idx = self.nodes.items[closing].parent;
            try self.writeCloseElement(writer, closing);
        }
    }

    fn writeOpenElement(self: *const Document, writer: anytype, idx: IndexInt) !void {
        const raw = self.nodes.items[idx];
        try writer.writeAll("<");
        try writer.writeAll(raw.name.slice(self.source));
        const range = raw.attributeSpan();
        var attr_i = range.start;
        const attr_end = range.end;
        while (attr_i < attr_end) : (attr_i += 1) {
            try writer.writeAll(" ");
            try writer.writeAll(self.attrs.items[attr_i].name.slice(self.source));
            try writer.writeAll("=\"");
            try writeDoubleQuotedAttributeValue(writer, self.attrs.items[attr_i].value.slice(self.source));
            try writer.writeAll("\"");
        }
    }

    fn writeCloseElement(self: *const Document, writer: anytype, idx: IndexInt) !void {
        try writer.writeAll("</");
        try writer.writeAll(self.nodes.items[idx].name.slice(self.source));
        try writer.writeAll(">");
    }

    pub fn reserveForInput(self: *Document, input_len: usize) !void {
        const est_nodes = @max(@as(usize, 16), input_len / 14 +| 8);
        const est_attrs = @max(@as(usize, 16), input_len / 32 +| 8);
        const est_stack = @max(@as(usize, 8), input_len / 512 +| 8);

        if (input_len <= self.reserved_input_hint_len and
            self.nodes.capacity >= est_nodes and
            self.attrs.capacity >= est_attrs and
            self.parse_stack.capacity >= est_stack) return;

        if (est_nodes > self.nodes.capacity) try self.nodes.ensureTotalCapacity(self.allocator, est_nodes);
        if (est_attrs > self.attrs.capacity) try self.attrs.ensureTotalCapacity(self.allocator, est_attrs);
        if (est_stack > self.parse_stack.capacity) try self.parse_stack.ensureTotalCapacity(self.allocator, est_stack);
        self.reserved_input_hint_len = @max(self.reserved_input_hint_len, input_len);
    }
};

fn writeDoubleQuotedAttributeValue(writer: anytype, value: []const u8) !void {
    var start: usize = 0;
    while (std.mem.indexOfScalarPos(u8, value, start, '"')) |quote| {
        try writer.writeAll(value[start..quote]);
        try writer.writeAll("&quot;");
        start = quote + 1;
    }
    try writer.writeAll(value[start..]);
}

const SubsetRange = struct { start: usize, end: usize };

fn findInternalSubset(input: []const u8) ParseError!?SubsetRange {
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

fn selectorMatches(node: Node, selector: []const u8) bool {
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

test "Types(options) exposes concrete DOM types" {
    const opts: ParseOptions = .{};
    const types = Types(opts);
    try std.testing.expectEqual(Span, types.Span);
    try std.testing.expectEqual(RawNode, types.RawNode);
    try std.testing.expectEqual(Node, types.Node);
    try std.testing.expectEqual(RawAttribute, types.RawAttribute);
    try std.testing.expectEqual(Attribute, types.Attribute);
    try std.testing.expectEqual(Document, types.Document);
    try std.testing.expectEqual(IndexInt, types.IndexInt);
}

test "Span helpers expose slices and lengths" {
    const opts: ParseOptions = .{};
    const SpanType = Types(opts).Span;
    const buf = "abcdef";
    const span: SpanType = .{ .start = 1, .end = 4 };
    try std.testing.expectEqual(@as(IndexInt, 3), span.len());
    try std.testing.expect(!span.isEmpty());
    try std.testing.expectEqualStrings("bcd", span.slice(buf));

    const empty: SpanType = .{ .start = 2, .end = 2 };
    try std.testing.expect(empty.isEmpty());
}

test "Document reserve and lookup helpers behave on empty and populated state" {
    const opts: ParseOptions = .{};
    const DocumentType = Types(opts).Document;
    var doc = DocumentType.init(std.testing.allocator);
    defer doc.deinit();

    try std.testing.expect(doc.root() == null);
    try std.testing.expect(doc.nodeAt(InvalidIndex) == null);
    try std.testing.expect(doc.nodeAt(0) == null);

    try doc.reserveForInput(256);
    try std.testing.expect(doc.nodes.capacity >= 16);
    try std.testing.expect(doc.attrs.capacity >= 16);
    try std.testing.expect(doc.parse_stack.capacity >= 8);

    const xml = "<r a='&amp;'>&lt;x&gt;</r>";
    try doc.parse(xml, .{ .mode = .strict });
    try std.testing.expect(doc.root() != null);
    try std.testing.expect(doc.nodeAt(1) != null);

    const root = doc.nodeAt(1).?;
    const attr = try root.getAttributeValue(std.testing.allocator, "a") orelse return error.TestUnexpectedResult;
    defer std.testing.allocator.free(attr);
    const text = try root.firstChild().?.value(std.testing.allocator);
    defer std.testing.allocator.free(text);

    try std.testing.expectEqualStrings("&", attr);
    try std.testing.expectEqualStrings("<x>", text);
    try std.testing.expectEqualStrings("&amp;", root.getAttributeValueRaw("a").?);
    try std.testing.expectEqualStrings("&lt;x&gt;", root.firstChild().?.valueRawSlice());
    try std.testing.expectEqual(@as(IndexInt, 0), root.parentNode().?.index);
    try std.testing.expectEqual(root.index, root.firstChild().?.parentNode().?.index);

    doc.clear();
    try std.testing.expect(doc.root() == null);
    try std.testing.expectEqualStrings("", doc.source);
    try std.testing.expectEqual(@as(usize, 0), doc.nodes.items.len);
    try std.testing.expectEqual(@as(usize, 0), doc.attrs.items.len);
}

test "empty input reserves parser scratch capacity" {
    var doc = Document.init(std.testing.allocator);
    defer doc.deinit();

    try doc.parse("", .{});
    try std.testing.expectEqual(@as(usize, 1), doc.nodes.items.len);
    try std.testing.expectEqual(NodeType.document, doc.root().?.kind);
}

test "lazy namespace helpers split names and resolve inherited xmlns" {
    var doc = Document.init(std.testing.allocator);
    defer doc.deinit();
    try doc.parse("<r xmlns='urn:default' xmlns:x='urn:x'><x:item x:id='1'/></r>", .{ .mode = .strict });

    const root_node = doc.nodeAt(1).?;
    const item = root_node.firstChild().?;
    const attr = item.firstAttribute().?;

    try std.testing.expect(root_node.namespacePrefix() == null);
    try std.testing.expectEqualStrings("r", root_node.localName());
    try std.testing.expectEqualStrings("urn:default", root_node.namespaceUri().?);
    try std.testing.expectEqualStrings("x", item.namespacePrefix().?);
    try std.testing.expectEqualStrings("item", item.localName());
    try std.testing.expectEqualStrings("urn:x", item.namespaceUri().?);
    try std.testing.expectEqualStrings("x", attr.namespacePrefix().?);
    try std.testing.expectEqualStrings("id", attr.localName());

    try doc.parse("<r xmlns='urn:outer'><inner xmlns=''><leaf/></inner></r>", .{ .mode = .strict, .validate_closing_tags = true });
    const inner = doc.nodeAt(2).?;
    const leaf = doc.nodeAt(3).?;
    try std.testing.expect(inner.namespaceUri() == null);
    try std.testing.expect(leaf.namespaceUri() == null);
}

test "node helpers are safe on non-elements and resolve the predefined xml prefix" {
    var doc = Document.init(std.testing.allocator);
    defer doc.deinit();
    try doc.parse("<xml:r>text</xml:r>", .{ .mode = .strict });

    const root = doc.nodeAt(1).?;
    const text = root.firstChild().?;
    try std.testing.expectEqualStrings("http://www.w3.org/XML/1998/namespace", root.namespaceUri().?);
    try std.testing.expect(text.namespaceUri() == null);
    try std.testing.expect(text.firstAttribute() == null);
    try std.testing.expect(text.getAttributeValueRaw("x") == null);
    try std.testing.expectEqualStrings("", root.valueRawSlice());
}

test "selector query helpers match tag id class and attributes" {
    var doc = Document.init(std.testing.allocator);
    defer doc.deinit();
    try doc.parse("<r><item id='a' class='hot new' data-x='1'/><item class='cold'/></r>", .{ .mode = .strict });

    const r = doc.nodeAt(1).?;
    try std.testing.expect(r.querySelector("item.hot") != null);
    try std.testing.expectEqualStrings("a", r.querySelector("#a").?.getAttributeValueRaw("id").?);
    try std.testing.expect(r.querySelector("item[data-x=1]") != null);

    const items = try r.querySelectorAll(std.testing.allocator, "item");
    defer std.testing.allocator.free(items);
    try std.testing.expectEqual(@as(usize, 2), items.len);
    try std.testing.expect(selectorMatches(items[1], "item.cold"));
}

test "parse diagnostics report offset location and context lazily" {
    var doc = Document.init(std.testing.allocator);
    defer doc.deinit();
    const diag = doc.parseDiagnostic("<r>\n  <1/>", .{ .mode = .strict }) orelse return error.TestUnexpectedResult;
    const loc = diag.location();

    try std.testing.expectEqual(ParseError.ExpectedElementName, diag.err);
    try std.testing.expectEqual(@as(usize, 2), loc.line);
    try std.testing.expectEqual(@as(usize, 4), loc.column);
    try std.testing.expect(std.mem.indexOf(u8, diag.context(8), "<1") != null);
}

test "registerDoctypeEntities finds the real subset and ignores non-declarations" {
    var doc = Document.init(std.testing.allocator);
    defer doc.deinit();
    doc.expand_dtd_entities = true;
    doc.parse_mode = .strict;

    try doc.registerDoctypeEntities(
        " r SYSTEM \"[<!ENTITY quoted 'bad'>]\" [<!-- <!ENTITY hidden 'bad'> --><?pi <!ENTITY pi 'bad'>?><!ENTITY a \"one\"><!ENTITY a 'two'>]",
    );
    try std.testing.expectEqual(@as(usize, 1), doc.entity_map.count());
    try std.testing.expectEqualStrings("one", doc.entity_map.get("a").?);
    try std.testing.expect(doc.entity_map.get("quoted") == null);
    try std.testing.expect(doc.entity_map.get("hidden") == null);
    try std.testing.expect(doc.entity_map.get("pi") == null);

    doc.clearEntityMap();
    try doc.registerDoctypeEntities(" r SYSTEM \"[<!ENTITY fake 'bad'>]\"");
    try std.testing.expectEqual(@as(usize, 0), doc.entity_map.count());
}

test "DTD entity expansion includes declarations from internal parameter entities" {
    var doc = Document.init(std.testing.allocator);
    defer doc.deinit();
    try doc.parse(
        "<!DOCTYPE r [<!ENTITY % q \"<!ENTITY e 'ok'>\"><!ENTITY % p '&#37;q;'>%p;<!ENTITY e 'later'>]><r>&e;</r>",
        .{ .mode = .strict, .expand_dtd_entities = true },
    );

    try std.testing.expectEqualStrings("ok", doc.entity_map.get("e").?);
    const root_node = doc.nodeAt(2) orelse return error.TestUnexpectedResult;
    const text = try root_node.firstChild().?.value(std.testing.allocator);
    defer std.testing.allocator.free(text);
    try std.testing.expectEqualStrings("ok", text);
}

test "DTD entity expansion replays parameter entities after later declarations" {
    var doc = Document.init(std.testing.allocator);
    defer doc.deinit();
    try doc.parse(
        "<!DOCTYPE r [<!ENTITY % p '&#37;q;'>%p;<!ENTITY % q \"<!ENTITY e 'ok'>\">%p;]><r>&e;</r>",
        .{ .mode = .strict, .expand_dtd_entities = true },
    );

    try std.testing.expectEqualStrings("ok", doc.entity_map.get("e").?);
    const root_node = doc.nodeAt(2) orelse return error.TestUnexpectedResult;
    const text = try root_node.firstChild().?.value(std.testing.allocator);
    defer std.testing.allocator.free(text);
    try std.testing.expectEqualStrings("ok", text);
}

test "Document.write serializes parsed tree without reparsing" {
    var doc = Document.init(std.testing.allocator);
    defer doc.deinit();
    const xml = "<?xml version='1.0'?><!DOCTYPE r [<!ENTITY x 'y'>]><r a='1'><c>t&amp;x</c><!--ok--><![CDATA[raw<]]></r>";
    try doc.parse(xml, .{ .mode = .strict });

    var out: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer out.deinit();
    try doc.write(&out.writer);

    try std.testing.expectEqualStrings("<?xml version='1.0'?><!DOCTYPE r [<!ENTITY x 'y'>]><r a=\"1\"><c>t&amp;x</c><!--ok--><![CDATA[raw<]]></r>", out.written());
}

test "Document.write does not allocate a traversal stack" {
    var doc = Document.init(std.testing.allocator);
    defer doc.deinit();
    try doc.parse("<r><a><b>text</b><c/></a><d/></r>", .{ .mode = .strict });

    const Sink = struct {
        buf: [256]u8 = undefined,
        len: usize = 0,

        pub fn writeAll(self: *@This(), bytes: []const u8) !void {
            if (bytes.len > self.buf.len - self.len) return error.NoSpaceLeft;
            @memcpy(self.buf[self.len..][0..bytes.len], bytes);
            self.len += bytes.len;
        }
    };
    var sink: Sink = .{};

    const allocator = doc.allocator;
    doc.allocator = std.testing.failing_allocator;
    defer doc.allocator = allocator;
    try doc.write(&sink);
    try std.testing.expectEqualStrings("<r><a><b>text</b><c/></a><d/></r>", sink.buf[0..sink.len]);
}

test "Document.write handles multiple turbo roots without an auxiliary stack" {
    var doc = Document.init(std.testing.allocator);
    defer doc.deinit();
    try doc.parse("<a><x/></a><b><y>z</y></b>", .{ .mode = .turbo });

    var out: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer out.deinit();
    try doc.write(&out.writer);
    try std.testing.expectEqualStrings("<a><x/></a><b><y>z</y></b>", out.written());
}

test "serialization escapes double quotes from single-quoted attributes" {
    var doc = Document.init(std.testing.allocator);
    defer doc.deinit();
    try doc.parse("<r a='say &quot;hi&quot; and \"raw\"'/>", .{ .mode = .strict });

    var out: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer out.deinit();
    try doc.write(&out.writer);
    try std.testing.expectEqualStrings("<r a=\"say &quot;hi&quot; and &quot;raw&quot;\"/>", out.written());

    var attr_out: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer attr_out.deinit();
    try doc.nodeAt(1).?.firstAttribute().?.write(&attr_out.writer);
    try std.testing.expectEqualStrings("a=\"say &quot;hi&quot; and &quot;raw&quot;\"", attr_out.written());
}

test "parse diagnostics treat CRLF and CR as line endings" {
    const crlf = ParseDiagnostic{ .err = error.ExpectedGt, .offset = 5, .source = "a\r\nb\nc" };
    try std.testing.expectEqual(ParseDiagnostic.Location{ .line = 3, .column = 1 }, crlf.location());

    const cr = ParseDiagnostic{ .err = error.ExpectedGt, .offset = 4, .source = "a\rb\rc" };
    try std.testing.expectEqual(ParseDiagnostic.Location{ .line = 3, .column = 1 }, cr.location());
}

test "DTD expansion limit applies while expanding referenced entity values" {
    var doc = Document.init(std.testing.allocator);
    defer doc.deinit();
    try std.testing.expectError(error.EntityValueTooLarge, doc.parse(
        "<!DOCTYPE r [<!ENTITY a '1234'><!ENTITY b '&a;&a;'>]><r/>",
        .{ .mode = .strict, .expand_dtd_entities = true, .max_entity_value_len = 4 },
    ));
}

test "DTD entity expansion resolves forward and nested references independent of declaration order" {
    var doc = Document.init(std.testing.allocator);
    defer doc.deinit();
    try doc.parse(
        "<!DOCTYPE r [<!ENTITY a '&b;!'><!ENTITY b '&c;'><!ENTITY c 'ok'>]><r>&a;</r>",
        .{ .mode = .strict, .expand_dtd_entities = true },
    );

    try std.testing.expectEqualStrings("ok!", doc.entity_map.get("a").?);
    const root_node = doc.nodeAt(2) orelse return error.TestUnexpectedResult;
    const text = try root_node.firstChild().?.value(std.testing.allocator);
    defer std.testing.allocator.free(text);
    try std.testing.expectEqualStrings("ok!", text);
}

test "DTD entity limit applies to decoded replacement text, not raw declaration bytes" {
    var doc = Document.init(std.testing.allocator);
    defer doc.deinit();
    try doc.parse(
        "<!DOCTYPE r [<!ENTITY a '&#65;'>]><r>&a;</r>",
        .{ .mode = .strict, .expand_dtd_entities = true, .max_entity_value_len = 1 },
    );
    try std.testing.expectEqualStrings("A", doc.entity_map.get("a").?);
}

test "DTD entity expansion rejects direct and indirect recursion" {
    inline for (.{
        "<!DOCTYPE r [<!ENTITY a '&a;'>]><r/>",
        "<!DOCTYPE r [<!ENTITY a '&b;'><!ENTITY b '&a;'>]><r/>",
    }) |xml| {
        var doc = Document.init(std.testing.allocator);
        defer doc.deinit();
        try std.testing.expectError(
            error.RecursiveEntity,
            doc.parse(xml, .{ .mode = .strict, .expand_dtd_entities = true }),
        );
    }
}

test "strict parsing rejects malformed UTF-8 and invalid XML characters" {
    const invalid = [_][]const u8{
        "<r>\xC0\xAF</r>",
        "<\xC0\xAF/>",
        "<r \xC0\xAF='x'/>",
        "<r a='\xC0\xAF'/>",
        "<r><![CDATA[\xC0\xAF]]></r>",
        "<r><!--\xC0\xAF--></r>",
        "<?p \xC0\xAF?><r/>",
        "<r>\x01</r>",
        "<r>\xEF\xBF\xBE</r>",
        "<r>\xEF\xBF\xBF</r>",
        "<r>\xED\xA0\x80</r>",
    };

    for (invalid) |input| {
        var doc = Document.init(std.testing.allocator);
        defer doc.deinit();
        try std.testing.expectError(error.InvalidXmlCharacter, doc.parse(input, .{ .mode = .strict }));
    }

    var doc = Document.init(std.testing.allocator);
    defer doc.deinit();
    try doc.parse("<\xC3\xA9l\xC3\xA9ment \xCE\xB1='ok'/>", .{ .mode = .strict });
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
