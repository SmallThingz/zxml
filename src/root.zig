const std = @import("std");
const strings = @import("strings.zig");

// const assert = std.debug.assert;
// const mem = std.mem;
// const Allocator = std.mem.Allocator;

/// Enumeration listing all node types produced by the parser.
pub const NodeType = enum(u3) {
  /// The invisible root of the entire tree. Created implicitly by the parser.
  Document,
  /// The declaration node `<?xml ... ?>`
  Declaration,
  /// A processing instruction node `<?target data?>`
  Pi,
  /// A doctype node `<!DOCTYPE ... >`
  Doctype,
  /// Unparsed Character Data `<![CDATA[...]]>`
  CData,
  /// An element node (e.g., `<a></a>`).
  Element,
  /// The string value, etc inside of a node
  Data,
  /// A comment node `<!-- ... -->`
  Comment,
};

/// Flags used to control the behavior of the parser.
pub const ParsingOptions = packed struct {
  /// Validates that the name in the closing tag matches the name in the opening tag (e.g., `<a></b>` would throw an error).
  /// Setting this to false will increase performance but may parse incorrectly.
  validate_closing_tags: bool,

  /// Disables UTF-8 handling and assumes plain 8-bit characters (ASCII/Latin-1).
  /// This applies to both attribute values and text content, thus this is here and not in `string`.
  utf8: bool,

  /// Manages the data node parsing and options.
  data: Data,

  /// Manages the string parsing options.
  string: String,

  /// Instruct which node should or should not be parsed. Data nodes are separately managed via `data`.
  node: @This().Node,

  /// Options for parsing data nodes.
  pub const Data = packed struct {
    /// Prevents the parser from creating separate `NodeType.Data` nodes when set to false.
    /// When this is true, the text appearing after the first text node will be lost, eg: `<a> kept <b>...</b> lost <c>...</c> lost </a>`.
    ///   This is to say, only one text segment is kept per node, eg: `<a><b>...</b> kept <c>...</c> lost </a>`
    data_nodes: bool,

    /// When set to false, prevents the parser from assigning the text of the first data node to the `value` field of its parent element.
    element_values: bool,

    /// Trims all leading and trailing whitespace from data nodes when set to true.
    trim_whitespace: bool,
  };

  /// Options for string parsing and translation.
  pub const String = packed struct {
    /// Instructs the parser not to modify the source text to insert null terminators. `[*:0]u8` strings will be used instead of slices if this is true.
    /// In Zig, where we use slices (`[]u8`), this is primarily used to prevent in-place modification of the input buffer.
    add_terminators: bool,

    /// When set to false, Disables translation of XML entities (e.g., `&amp;`, `&lt;`, `&#123;`).
    /// If true, the raw entity text remains in the output. This results in faster parsing as no in-place string modification is required.
    entity_translation: bool,

    /// Condenses all runs of whitespace characters in data nodes into a single space character. This modifies the source text in-place.
    normalize_whitespace: bool,
  };

  /// Instructs the parser to create nodes for specific node types.
  pub const Node = packed struct {
    /// Instructs the parser to create a `NodeType.Declaration` node when it encounters an XML declaration (e.g., `<?xml ... ?>`).
    declaration: bool,

    /// Instructs the parser to create `NodeType.Comment` nodes for comments (e.g., `<!-- ... -->`).
    comment: bool,

    /// Instructs the parser to create a `NodeType.Doctype` node when it encounters a `<!DOCTYPE ... >` declaration.
    doctype: bool,

    /// Instructs the parser to create `NodeType.Pi` nodes for Processing Instructions (e.g., `<?target data?>`).
    pi: bool,
  };
};

const RawAttribute = struct {
  name: [*]u8,
  _value: [:0]u8,

  const Tag = packed struct(u8) {
    _padding: u2 = 0b10, // makes this an invalid utf8 byte
    next_exists: bool,
    have_comma: bool,
    next_distance: u5,
  };

  pub fn getTag(self: *const @This()) *Tag {
    return @as(*Tag, @ptrCast(self._value.ptr - 1));
  }

  pub fn next(self: *const @This()) ?@This() {
    const tag = self.getTag().*;

    if (!tag.next_exists) return null;
    const start = if (tag.beyond) blk: {
      const beyond_ptr = std.mem.alignForward(usize, @intFromPtr(self._value.ptr + self._value.len + 1), 8);
      break :blk @ptrCast([*]u8, beyond_ptr + @as(usize, @intCast(@as(*align(8) u64, @ptrCast(beyond_ptr)).*)));
    } else @ptrFromInt(@intFromPtr(self._value.ptr) + self._value.len + 1 + tag.next_distance);

    var retval: @This() = undefined;
    retval.name.ptr = @ptrCast(start);
    retval.name = std.mem.sliceTo(retval.name.ptr, 0);
    retval._value.ptr = @ptrCast(start + retval.name.len + 1 + 1); // +1 (null terminator) +1 (tag)
    retval._value = std.mem.sliceTo(retval._value.ptr, 0);
    return retval;
  }

  /// returns true if the value is parsed, false otherwise
  pub fn isParsed(self: *const @This()) bool {
    // If we are pointing to the byte after the name's null byte, the value is Unparsed, otherwise, the value is parsed
    return @as(*u8, @ptrCast(self._value.ptr - 1)).* == 0;
  }

  pub fn parseValue(self: *@This(), comptime parser: strings.Parser) !void {
    std.debug.assert(!self.isParsed());
    const tag = self.getTag();
    std.debug.assert(tag.parsed == false);
    const oglen = self._value.len + 1;
    const start_quote_kind = self._value[0];

    if (start_quote_kind != '\'' and start_quote_kind != '"') return error.InvalidQuoteChar;
    self._value
  }

  pub fn value(self: *@This(), comptime can_be_unparsed: bool)
};

pub const ComptimeOptions = struct {
  attribute: Attribute,
  node: @This().Node,

  pub const Attribute = struct {
    parse_on_access: bool,
    /// Class representing attribute node of XML document.
    pub fn Type(comptime attribute_options: @This()) type {
      const Str = if (attribute_options.null_terminated_string) [*:0]u8 else []u8;
      return struct {
        _name: Str,
        _value: Str,

        pub fn name(self: *const @This()) Str {
          std.heap.GeneralPurposeAllocator(comptime config: Config);
          return self._name;
        }

        pub fn value(self: *@This()) Str {
          if (comptime attribute_options.parse_on_access) {
            if (self._value.len != 0 and self._value[0] == 0) self._value = parseValueInplace(self._value);
          }
          return self._value;
        }

        fn parseValueInplace(value_str: Str) Str {
          _ = value_str;
          @compileError("TODO");
        }
      };
    }
  };

  pub const Node = struct {

  };
};

pub const ParseError = error {
  /// The input stream ended abruptly before the XML structure was complete (e.g., a tag or comment was left unclosed).
  UnexpectedEndOfData,
  /// The parser expected an opening bracket ('<') to start a new node but encountered a different character or end of stream.
  ExpectedLt,
  /// The parser expected a closing bracket ('>') to terminate a tag but encountered a different character or end of stream.
  ExpectedGt,
  /// A Processing Instruction (<?...?>) was missing its target name (e.g., found `<? ?>` instead of `<?xml-stylesheet ...?>`).
  ExpectedPiTarget,
  /// An element started with '<' but was not followed by a valid name (e.g., found `< >` or `<123>`).
  ExpectedElementName,
  /// An attribute was detected within a tag, but no valid name was provided before the '=' character or the end of the tag.
  ExpectedAttributeName,
  /// An attribute name was found, but it was not followed by the required '=' character (e.g., `<tag attr "value">`).
  ExpectedEq,
  /// An attribute value was not enclosed in valid quotes, or a closing quote was missing (e.g., `<tag attr=value>` or `<tag attr="value>`).
  ExpectedQuote,
  /// A numeric character entity (e.g., `&#123;` or `&#x123;`) was malformed, contained non-digit characters, or specified an invalid Unicode point.
  InvalidNumericCharacterEntity,
  /// Triggered when `validate_closing_tags` is enabled and the name in a closing tag does not match the opening tag (e.g., `<a></b>`).
  InvalidClosingTagName,
  OutOfMemory,
};


/// Class representing a node of XML document.
pub const Node = struct {
  type: NodeType,
  name: []u8 = &[_]u8{},
  value: []u8 = &[_]u8{},
  parent: ?*Node = null,
  first_node: ?*Node = null,
  last_node: ?*Node = null,
  first_attribute: ?*Attribute = null,
  last_attribute: ?*Attribute = null,
  prev_sibling: ?*Node = null,
  next_sibling: ?*Node = null,

  /// Gets first child node, optionally matching node name.
  pub fn firstNode(self: *const Node, name_opt: ?[]const u8) ?*Node {
    var child = self.first_node;
    if (name_opt) |name| {
      while (child) |c| : (child = c.next_sibling) {
        if (mem.eql(u8, c.name, name)) return c;
      }
      return null;
    }
    return child;
  }

  pub fn lastNode(self: *const Node, name_opt: ?[]const u8) ?*Node {
    var child = self.last_node;
    if (name_opt) |name| {
      while (child) |c| : (child = c.prev_sibling) {
        if (mem.eql(u8, c.name, name)) return c;
      }
      return null;
    }
    return child;
  }

  pub fn firstAttribute(self: *const Node, name_opt: ?[]const u8) ?*Attribute {
    var attr = self.first_attribute;
    if (name_opt) |name| {
      while (attr) |a| : (attr = a.next_attribute) {
        if (mem.eql(u8, a.name, name)) return a;
      }
      return null;
    }
    return attr;
  }

  pub fn appendNode(self: *Node, child: *Node) void {
    assert(child.parent == null); // Child must not have a parent
    if (self.first_node) |_| {
      child.prev_sibling = self.last_node;
      self.last_node.?.next_sibling = child;
    } else {
      child.prev_sibling = null;
      self.first_node = child;
    }
    self.last_node = child;
    child.parent = self;
    child.next_sibling = null;
  }

  pub fn prependNode(self: *Node, child: *Node) void {
    assert(child.parent == null);
    if (self.first_node) |first| {
      child.next_sibling = first;
      first.prev_sibling = child;
    } else {
      child.next_sibling = null;
      self.last_node = child;
    }
    self.first_node = child;
    child.parent = self;
    child.prev_sibling = null;
  }

  pub fn removeNode(self: *Node, child: *Node) void {
    assert(child.parent == self);
    if (child == self.first_node) {
      self.first_node = child.next_sibling;
    }
    if (child == self.last_node) {
      self.last_node = child.prev_sibling;
    }
    if (child.prev_sibling) |prev| {
      prev.next_sibling = child.next_sibling;
    }
    if (child.next_sibling) |next| {
      next.prev_sibling = child.prev_sibling;
    }
    child.parent = null;
    child.prev_sibling = null;
    child.next_sibling = null;
  }

  pub fn removeAllNodes(self: *Node) void {
    var child = self.first_node;
    while (child) |c| {
      const next = c.next_sibling;
      c.parent = null;
      child = next;
    }
    self.first_node = null;
    self.last_node = null;
  }

  pub fn appendAttribute(self: *Node, attr: *Attribute) void {
    assert(attr.parent == null);
    if (self.first_attribute) |_| {
      attr.prev_attribute = self.last_attribute;
      self.last_attribute.?.next_attribute = attr;
    } else {
      attr.prev_attribute = null;
      self.first_attribute = attr;
    }
    self.last_attribute = attr;
    attr.parent = self;
    attr.next_attribute = null;
  }
};

/// Main Document Object. Manages the memory arena.
/// The document itself acts as the root node.
pub const Document = struct {
  root: Node,
  arena: std.heap.ArenaAllocator,

  pub fn init(gpa: Allocator) Document {
    return Document{
      .root = Node{ .type = .Document },
      .arena = std.heap.ArenaAllocator.init(gpa),
    };
  }

  pub fn deinit(self: *Document) void {
    self.arena.deinit();
  }

  pub fn allocator(self: *Document) Allocator {
    return self.arena.allocator();
  }

  /// Allocates a new node from the pool.
  pub fn allocateNode(self: *Document, kind: NodeType) !*Node {
    const node = try self.allocator().create(Node);
    node.* = Node{ .type = kind };
    return node;
  }

  /// Allocates a new attribute from the pool.
  pub fn allocateAttribute(self: *Document) !*Attribute {
    const attr = try self.allocator().create(Attribute);
    attr.* = Attribute{};
    return attr;
  }

  /// Parses a zero-terminated (optional) XML string.
  /// The input text MUST be mutable. RapidXML works by modifying the string in-place
  /// (e.g. normalizing whitespace, expanding entities).
  /// If ParseFlags.NonDestructive is used, text modifications are minimized.
  pub fn parse(self: *Document, text: []u8, comptime flags: u32) !void {
    self.root.removeAllNodes();
    // Attributes on document node are not standard XML, but clearing them is safe
    self.root.first_attribute = null;
    self.root.last_attribute = null;

    var cursor = text;
    if (cursor.len == 0) return;

    // BOM check
    parseBom(&cursor);

    while (true) {
      skip(&cursor, Tables.Whitespace);
      if (cursor.len == 0 or cursor[0] == 0) break;

      if (cursor[0] == '<') {
        cursor = cursor[1..]; // Skip '<'
        if (try self.parseNode(&cursor, flags)) |node| {
          self.root.appendNode(node);
        }
      } else {
        return ParseError.ExpectedLt;
      }
    }
  }

  pub fn clear(self: *Document) void {
    self.root.removeAllNodes();
    _ = self.arena.reset(.retain_capacity);
  }

  // --- Internal Parsing Logic ---

  fn parseBom(text: *[]u8) void {
    if (text.len >= 3 and text.*[0] == 0xEF and text.*[1] == 0xBB and text.*[2] == 0xBF) {
      text.* = text.*[3..];
    }
  }

  fn parseNode(self: *Document, text: *[]u8, comptime flags: u32) !?*Node {
    if (text.len == 0) return ParseError.UnexpectedEndOfData;

    const char = text.*[0];

    switch (char) {
      '?' => {
        text.* = text.*[1..]; // Skip ?
        if (text.len >= 3 and
          (text.*[0] == 'x' or text.*[0] == 'X') and
          (text.*[1] == 'm' or text.*[1] == 'M') and
          (text.*[2] == 'l' or text.*[2] == 'L') and
          (text.len > 3 and Tables.Whitespace.check(text.*[3])))
        {
          text.* = text.*[4..]; // Skip 'xml '
          return self.parseXmlDeclaration(text, flags);
        } else {
          return self.parsePi(text, flags);
        }
      },
      '!' => {
        // Parse proper subset of <! node
        if (text.len >= 3 and text.*[1] == '-') { // <!-
          if (text.*[2] == '-') { // <!--
            text.* = text.*[3..];
            return self.parseComment(text, flags);
          }
        } else if (text.len >= 8 and text.*[1] == '[') { // <![
          if (mem.startsWith(u8, text.*[2..], "CDATA[")) {
            text.* = text.*[8..];
            return self.parseCData(text, flags);
          }
        } else if (text.len >= 9 and text.*[1] == 'D') { // <!D
          if (mem.startsWith(u8, text.*[2..], "OCTYPE") and Tables.Whitespace.check(text.*[8])) {
            text.* = text.*[9..];
            return self.parseDoctype(text, flags);
          }
        }

        // Unrecognized <! node, skip it
        text.* = text.*[1..]; // skip !
        while (text.len > 0 and text.*[0] != '>') {
          text.* = text.*[1..];
        }
        if (text.len == 0) return ParseError.UnexpectedEndOfData;
        text.* = text.*[1..]; // skip >
        return null;
      },
      else => {
        return self.parseElement(text, flags);
      },
    }
  }

  fn parseElement(self: *Document, text: *[]u8, comptime flags: u32) !*Node {
    const element = try self.allocateNode(.Element);

    // Name
    const name_start = text.*;
    skip(text, Tables.NodeName);
    if (text.ptr == name_start.ptr) return ParseError.ExpectedElementName;
    element.name = name_start[0 .. @intFromPtr(text.ptr) - @intFromPtr(name_start.ptr)];

    skip(text, Tables.Whitespace);

    try self.parseNodeAttributes(text, element, flags);

    if (text.len > 0 and text.*[0] == '>') {
      text.* = text.*[1..];
      try self.parseNodeContents(text, element, flags);
    } else if (text.len > 1 and text.*[0] == '/' and text.*[1] == '>') {
      text.* = text.*[2..];
    } else {
      return ParseError.ExpectedGt;
    }

    return element;
  }

  fn parseNodeAttributes(self: *Document, text: *[]u8, node: *Node, comptime flags: u32) !void {
    while (text.len > 0 and Tables.AttributeName.check(text.*[0])) {
      const name_start = text.*;
      text.* = text.*[1..]; // skip first char
      skip(text, Tables.AttributeName);
      if (text.ptr == name_start.ptr) return ParseError.ExpectedAttributeName;

      const attr = try self.allocateAttribute();
      attr.name = name_start[0 .. @intFromPtr(text.ptr) - @intFromPtr(name_start.ptr)];
      node.appendAttribute(attr);

      skip(text, Tables.Whitespace);

      if (text.len == 0 or text.*[0] != '=') return ParseError.ExpectedEq;
      text.* = text.*[1..]; // skip =

      skip(text, Tables.Whitespace);

      if (text.len == 0) return ParseError.UnexpectedEndOfData;
      const quote = text.*[0];
      if (quote != '\'' and quote != '"') return ParseError.ExpectedQuote;
      text.* = text.*[1..]; // skip quote

      const value_start = text.*;
      const att_flags = flags & ~ParseFlags.NormalizeWhitespace; // No whitespace normalization in attributes

      // Determine generic params for skipAndExpand
      if (quote == '\'') {
        skipAndExpandCharacterRefs(text, Tables.AttributeDataQuote1, Tables.AttributeDataQuote1Pure, att_flags);
      } else {
        skipAndExpandCharacterRefs(text, Tables.AttributeDataQuote2, Tables.AttributeDataQuote2Pure, att_flags);
      }

      attr.value = value_start[0 .. @intFromPtr(text.ptr) - @intFromPtr(value_start.ptr)];

      if (text.len == 0 or text.*[0] != quote) return ParseError.ExpectedQuote;
      text.* = text.*[1..]; // skip quote

      skip(text, Tables.Whitespace);
    }
  }

  fn parseNodeContents(self: *Document, text: *[]u8, node: *Node, comptime flags: u32) !void {
    while (true) {
      const contents_start = text.*;
      skip(text, Tables.Whitespace);
      if (text.len == 0) return ParseError.UnexpectedEndOfData;

      const next_char = text.*[0];

      switch (next_char) {
        '<' => {
          if (text.len > 1 and text.*[1] == '/') {
            // Node closing
            text.* = text.*[2..]; // skip </
            if (flags & ParseFlags.ValidateClosingTags != 0) {
              const closing_name = text.*;
              skip(text, Tables.NodeName);
              const parsed_name = closing_name[0 .. @intFromPtr(text.ptr) - @intFromPtr(closing_name.ptr)];
              if (!mem.eql(u8, node.name, parsed_name)) {
                return ParseError.InvalidClosingTagName;
              }
            } else {
              skip(text, Tables.NodeName);
            }

            skip(text, Tables.Whitespace);
            if (text.len == 0 or text.*[0] != '>') return ParseError.ExpectedGt;
            text.* = text.*[1..]; // skip >
            return; // Done
          } else {
            // Child Node
            text.* = text.*[1..]; // skip <
            if (try self.parseNode(text, flags)) |child| {
              node.appendNode(child);
            }
          }
        },
        0 => return ParseError.UnexpectedEndOfData,
        else => {
          // Data Node
          try self.parseAndAppendData(node, text, contents_start, flags);
        },
      }
    }
  }

  fn parseAndAppendData(self: *Document, node: *Node, text: *[]u8, contents_start: []u8, comptime flags: u32) !void {
    // Backup to contents start if whitespace trimming is disabled
    if (flags & ParseFlags.TrimWhitespace == 0) {
      text.* = contents_start;
    }

    const value_start = text.*;

    if (flags & ParseFlags.NormalizeWhitespace != 0) {
      skipAndExpandCharacterRefs(text, Tables.Text, Tables.TextPureWithWs, flags);
    } else {
      skipAndExpandCharacterRefs(text, Tables.Text, Tables.TextPureNoWs, flags);
    }

    var value_end = text.ptr;

    // Trim trailing whitespace if needed
    if (flags & ParseFlags.TrimWhitespace != 0) {
      if (flags & ParseFlags.NormalizeWhitespace != 0) {
        // Whitespace is already condensed to single space, trim 1 char
        const len_so_far = @intFromPtr(value_end) - @intFromPtr(value_start.ptr);
        if (len_so_far > 0 and (value_end - 1)[0] == ' ') {
          value_end -= 1;
        }
      } else {
        // Backup
        while (@intFromPtr(value_end) > @intFromPtr(value_start.ptr)) {
          if (Tables.Whitespace.check((value_end - 1)[0])) {
            value_end -= 1;
          } else {
            break;
          }
        }
      }
    }

    const len = @intFromPtr(value_end) - @intFromPtr(value_start.ptr);
    const data_slice = value_start[0..len];

    if (flags & ParseFlags.NoDataNodes == 0 and len > 0) {
      const data_node = try self.allocateNode(.Data);
      data_node.value = data_slice;
      node.appendNode(data_node);
    }

    if (flags & ParseFlags.NoElementValues == 0 and node.value.len == 0 and len > 0) {
      node.value = data_slice;
    }
  }

  fn parseXmlDeclaration(self: *Document, text: *[]u8, comptime flags: u32) !?*Node {
    if (flags & ParseFlags.DeclarationNode == 0) {
      // Skip
      while (text.len >= 2 and (text.*[0] != '?' or text.*[1] != '>')) {
        if (text.len == 0) return ParseError.UnexpectedEndOfData;
        text.* = text.*[1..];
      }
      if (text.len >= 2) text.* = text.*[2..];
      return null;
    }

    const decl = try self.allocateNode(.Declaration);
    skip(text, Tables.Whitespace);
    try self.parseNodeAttributes(text, decl, flags);

    if (text.len < 2 or text.*[0] != '?' or text.*[1] != '>') return ParseError.ExpectedGt;
    text.* = text.*[2..];

    return decl;
  }

  fn parseComment(self: *Document, text: *[]u8, comptime flags: u32) !?*Node {
    if (flags & ParseFlags.CommentNodes == 0) {
      while (text.len >= 3 and (text.*[0] != '-' or text.*[1] != '-' or text.*[2] != '>')) {
        if (text.len == 0) return ParseError.UnexpectedEndOfData;
        text.* = text.*[1..];
      }
      if (text.len >= 3) text.* = text.*[3..];
      return null;
    }

    const value_start = text.*;
    while (text.len >= 3 and (text.*[0] != '-' or text.*[1] != '-' or text.*[2] != '>')) {
      if (text.len == 0) return ParseError.UnexpectedEndOfData;
      text.* = text.*[1..];
    }

    const comment = try self.allocateNode(.Comment);
    comment.value = value_start[0 .. @intFromPtr(text.ptr) - @intFromPtr(value_start.ptr)];

    if (text.len >= 3) text.* = text.*[3..];
    return comment;
  }

  fn parseDoctype(self: *Document, text: *[]u8, comptime flags: u32) !?*Node {
    const value_start = text.*;
    while (text.len > 0 and text.*[0] != '>') {
      const ch = text.*[0];
      if (ch == '[') {
        text.* = text.*[1..];
        var depth: i32 = 1;
        while (depth > 0) {
          if (text.len == 0) return ParseError.UnexpectedEndOfData;
          switch (text.*[0]) {
            '[' => depth += 1,
            ']' => depth -= 1,
            else => {},
          }
          text.* = text.*[1..];
        }
      } else if (ch == 0) {
        return ParseError.UnexpectedEndOfData;
      } else {
        text.* = text.*[1..];
      }
    }

    if (flags & ParseFlags.DoctypeNode != 0) {
      const doctype = try self.allocateNode(.Doctype);
      doctype.value = value_start[0 .. @intFromPtr(text.ptr) - @intFromPtr(value_start.ptr)];
      text.* = text.*[1..]; // skip >
      return doctype;
    } else {
      text.* = text.*[1..]; // skip >
      return null;
    }
  }

  fn parsePi(self: *Document, text: *[]u8, comptime flags: u32) !?*Node {
    if (flags & ParseFlags.PiNodes != 0) {
      const pi = try self.allocateNode(.Pi);
      const name_start = text.*;
      skip(text, Tables.NodeName);
      if (text.ptr == name_start.ptr) return ParseError.ExpectedPiTarget;
      pi.name = name_start[0 .. @intFromPtr(text.ptr) - @intFromPtr(name_start.ptr)];

      skip(text, Tables.Whitespace);
      const value_start = text.*;

      while (text.len >= 2 and (text.*[0] != '?' or text.*[1] != '>')) {
        if (text.len == 0) return ParseError.UnexpectedEndOfData;
        text.* = text.*[1..];
      }

      pi.value = value_start[0 .. @intFromPtr(text.ptr) - @intFromPtr(value_start.ptr)];
      if (text.len >= 2) text.* = text.*[2..];
      return pi;
    } else {
      while (text.len >= 2 and (text.*[0] != '?' or text.*[1] != '>')) {
        if (text.len == 0) return ParseError.UnexpectedEndOfData;
        text.* = text.*[1..];
      }
      if (text.len >= 2) text.* = text.*[2..];
      return null;
    }
  }

  fn parseCData(self: *Document, text: *[]u8, comptime flags: u32) !?*Node {
    if (flags & ParseFlags.NoDataNodes != 0) {
      while (text.len >= 3 and (text.*[0] != ']' or text.*[1] != ']' or text.*[2] != '>')) {
        if (text.len == 0) return ParseError.UnexpectedEndOfData;
        text.* = text.*[1..];
      }
      if (text.len >= 3) text.* = text.*[3..];
      return null;
    }

    const value_start = text.*;
    while (text.len >= 3 and (text.*[0] != ']' or text.*[1] != ']' or text.*[2] != '>')) {
      if (text.len == 0) return ParseError.UnexpectedEndOfData;
      text.* = text.*[1..];
    }

    const cdata = try self.allocateNode(.CData);
    cdata.value = value_start[0 .. @intFromPtr(text.ptr) - @intFromPtr(value_start.ptr)];
    if (text.len >= 3) text.* = text.*[3..];
    return cdata;
  }
};

// --- Utilities ---

fn skip(text: *[]u8, comptime Table: anytype) void {
  var ptr = text.ptr;
  const end = ptr + text.len;
  while (@intFromPtr(ptr) < @intFromPtr(end) and Table.check(ptr[0])) {
    ptr += 1;
  }
  text.* = text.*[@intFromPtr(ptr) - @intFromPtr(text.ptr) ..];
}

fn skipAndExpandCharacterRefs(
  text: *[]u8,
  comptime StopPred: anytype,
  comptime StopPredPure: anytype,
  comptime flags: u32,
) void {
  if ((flags & ParseFlags.NoEntityTranslation != 0) and
    (flags & ParseFlags.NormalizeWhitespace == 0) and
    (flags & ParseFlags.TrimWhitespace == 0))
  {
    skip(text, StopPred);
    return;
  }

  // Fast skip until something tricky
  skip(text, StopPredPure);

  var src = text.ptr;
  var dest = src;
  const end = text.ptr + text.len;

  while (@intFromPtr(src) < @intFromPtr(end) and StopPred.check(src[0])) {
    if (flags & ParseFlags.NoEntityTranslation == 0) {
      if (src[0] == '&') {
        // Entity decoding
        if (src + 1 < end) {
          switch (src[1]) {
            'a' => {
              if (mem.startsWith(u8, src[0 .. @intFromPtr(end) - @intFromPtr(src)], "&amp;")) {
                dest[0] = '&';
                dest += 1;
                src += 5;
                continue;
              }
              if (mem.startsWith(u8, src[0 .. @intFromPtr(end) - @intFromPtr(src)], "&apos;")) {
                dest[0] = '\'';
                dest += 1;
                src += 6;
                continue;
              }
            },
            'q' => {
              if (mem.startsWith(u8, src[0 .. @intFromPtr(end) - @intFromPtr(src)], "&quot;")) {
                dest[0] = '"';
                dest += 1;
                src += 6;
                continue;
              }
            },
            'g' => {
              if (mem.startsWith(u8, src[0 .. @intFromPtr(end) - @intFromPtr(src)], "&gt;")) {
                dest[0] = '>';
                dest += 1;
                src += 4;
                continue;
              }
            },
            'l' => {
              if (mem.startsWith(u8, src[0 .. @intFromPtr(end) - @intFromPtr(src)], "&lt;")) {
                dest[0] = '<';
                dest += 1;
                src += 4;
                continue;
              }
            },
            '#' => {
              if (src + 2 < end and src[2] == 'x') {
                // Hex
                var code: u32 = 0;
                src += 3;
                while (@intFromPtr(src) < @intFromPtr(end)) : (src += 1) {
                  const digit = Tables.Digits.lookup(src[0]);
                  if (digit == 0xFF) break;
                  code = code * 16 + digit;
                }
                dest = insertCodedCharacter(dest, code, flags);
              } else {
                // Decimal
                var code: u32 = 0;
                src += 2;
                while (@intFromPtr(src) < @intFromPtr(end)) : (src += 1) {
                  const digit = Tables.Digits.lookup(src[0]);
                  if (digit == 0xFF) break;
                  code = code * 10 + digit;
                }
                dest = insertCodedCharacter(dest, code, flags);
              }
              if (@intFromPtr(src) < @intFromPtr(end) and src[0] == ';') {
                src += 1;
              }
              continue;
            },
            else => {},
          }
        }
      }
    }

    if (flags & ParseFlags.NormalizeWhitespace != 0) {
      if (Tables.Whitespace.check(src[0])) {
        dest[0] = ' ';
        dest += 1;
        src += 1;
        while (@intFromPtr(src) < @intFromPtr(end) and Tables.Whitespace.check(src[0])) {
          src += 1;
        }
        continue;
      }
    }

    dest[0] = src[0];
    dest += 1;
    src += 1;
  }

  text.* = src[0 .. @intFromPtr(end) - @intFromPtr(src)];
}

fn insertCodedCharacter(dest: [*]u8, code: u32, comptime flags: u32) [*]u8 {
  var d = dest;
  if (flags & ParseFlags.NoUtf8 != 0) {
    d[0] = @as(u8, @truncate(code));
    return d + 1;
  }
  // UTF-8 Encode
  if (code < 0x80) {
    d[0] = @as(u8, @truncate(code));
    return d + 1;
  } else if (code < 0x800) {
    d[1] = @as(u8, @truncate((code | 0x80) & 0xBF));
    d[0] = @as(u8, @truncate((code >> 6) | 0xC0));
    return d + 2;
  } else if (code < 0x10000) {
    d[2] = @as(u8, @truncate((code | 0x80) & 0xBF));
    d[1] = @as(u8, @truncate(((code >> 6) | 0x80) & 0xBF));
    d[0] = @as(u8, @truncate((code >> 12) | 0xE0));
    return d + 3;
  } else {
    d[3] = @as(u8, @truncate((code | 0x80) & 0xBF));
    d[2] = @as(u8, @truncate(((code >> 6) | 0x80) & 0xBF));
    d[1] = @as(u8, @truncate(((code >> 12) | 0x80) & 0xBF));
    d[0] = @as(u8, @truncate((code >> 18) | 0xF0));
    return d + 4;
  }
}

// --- Lookup Tables ---

const Tables = struct {
  const Whitespace = TableWrapper("Whitespace", &.{
    0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 0, 0, 1, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  });

  const NodeName = TableWrapper("NodeName", &.{
    0, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 1, 1, 0, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0,
  }, true);

  const AttributeName = TableWrapper("AttributeName", &.{
    0, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 1, 1, 0, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0,
  }, true);

  const Text = TableWrapper("Text", &.{
    0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 1, 1, 1,
  }, true);

  const TextPureNoWs = TableWrapper("TextPureNoWs", &.{
    0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 1, 1, 1,
  }, true);

  const TextPureWithWs = TableWrapper("TextPureWithWs", &.{
    0, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 1, 1, 0, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    0, 1, 1, 1, 1, 1, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 1, 1, 1,
  }, true);

  const AttributeDataQuote1 = TableWrapper("AttributeDataQuote1", &.{
    0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 0, 1, 1, 1, 1, 1, 1, 1, 1,
  }, true);

  const AttributeDataQuote1Pure = TableWrapper("AttributeDataQuote1Pure", &.{
    0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1,
  }, true);

  const AttributeDataQuote2 = TableWrapper("AttributeDataQuote2", &.{
    0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
  }, true);

  const AttributeDataQuote2Pure = TableWrapper("AttributeDataQuote2Pure", &.{
    0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 0, 1, 1, 1, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1,
  }, true);

  const Digits = TableWrapper("Digits", &.{
    // 0-F are 255 (invalid), '0'-'9' map to 0-9, 'a'-'f' & 'A'-'F' map to 10-15
    // Replicating logic via code for brevity in Zig struct, or could map explicitly
    // This is a special table that returns values, not bools
  }, false);
};

// Helper to generate the tables or wrap logic. RapidXML uses 256-byte arrays.
fn TableWrapper(comptime name: []const u8, comptime prefix_data: []const u8, comptime default_one: bool) type {
  return struct {
    // We generate the full 256 table at comptime
    const table: [256]u8 = blk: {
      var t = [_]u8{if (default_one) 1 else 0} ** 256;
      for (prefix_data, 0..) |v, i| {
        if (i < 256) t[i] = v;
      }
      if (mem.eql(u8, name, "Digits")) {
        @setEvalBranchQuota(2000);
        var d = [_]u8{255} ** 256;
        for ('0'..'9' + 1) |c| d[c] = @intCast(c - '0');
        for ('a'..'f' + 1) |c| d[c] = @intCast(c - 'a' + 10);
        for ('A'..'F' + 1) |c| d[c] = @intCast(c - 'A' + 10);
        break :blk d;
      }
      break :blk t;
    };

    pub fn check(c: u8) bool {
      return table[c] != 0;
    }
    pub fn lookup(c: u8) u8 {
      return table[c];
    }
  };
}
