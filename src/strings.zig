const std = @import("std");
const builtin = @import("builtin");
const meta = @import("meta.zig");
const tables = @import("tables.zig");

/// Copied from std.mem
const use_vectors = switch (builtin.zig_backend) {
  // These backends don't support vectors yet.
  .stage2_aarch64,
  .stage2_powerpc,
  .stage2_riscv64,
  => false,
  // The SPIR-V backend does not support the optimized path yet.
  .stage2_spirv => false,
  else => true,
};

/// Copied from std.mem
const use_vectors_for_comparison = use_vectors and
  !builtin.fuzz and // The naive memory comparison implementation is more useful for fuzzers to find interesting inputs.
  !std.debug.inValgrind() // https://github.com/ziglang/zig/issues/17717
;

pub const Parser = struct {
  /// This functions is called on all all escape sequences that are encountered. The input points to character after `&`, character_references are handles separately.
  /// This must do the following:
  /// - in case of success => advance the input slice beyond the escape sequences, write the result to output and advance the output slice by the number of bytes written.
  /// - in case of error => you (may or may not) advance the input slice beyond the escape sequences and (may or may not) return an error.
  ///
  /// NOTE: you likely want to write `@` to output if you don't advance input slice
  ///
  /// NOTE: Be aware that the input and output slices may alias, that is, they may overlap or the slices may literally be the same slice.
  ///       As a consequence of this, the output size may NEVER be larger than the input size. You can't advance the output slice more than you advance the input slice
  escape_sequence_handler: ?fn (comptime options: Options, input: *[]u8, output: *[]u8) EscapeSequence.Error!void = null,

  /// Handler for parsing character references. This function is called on all character references that are encountered.
  /// This must do the following:
  /// - in case of success => advance the input slice beyond the escape sequences, write the result to output and advance the output slice by the number of bytes written.
  /// - in case of error => you (may or may not) advance the input slice beyond the escape sequences and (may or may not) return an error.
  ///
  /// NOTE: you likely want to write `@` and `#` to output if you don't advance input slice
  ///
  /// NOTE: the character references may be base10 or base16 (starting with `x`).
  character_reference_handler: ?fn (comptime options: Options, input: *[]u8, output: *[]u8) CharacterReference.Error!void = null,

  /// These are the options that dictate parsing behavior.
  options: Options,

  pub const DataError = error{UnexpectedEndOfData};

  pub const Options = struct {
    /// Weather or not to normalize whitespace (collapse newlines, tabs, etc to a single space)
    normalize_whitespace: bool,
    /// When set to true, the parser will recognize the utf8 sequences. When false, treats them as LATIN-1
    utf8: bool,
    /// What to do on invalid utf8 sequences.
    on_invalid_utf8: OnInvalid = .ignore,
    /// The sequence that marks the end of a string. The parser must return when this sequence is encountered.
    ending_sequence: EndingSequence,
    /// What to do on invalid escape sequences.
    on_invalid_escape_sequence: OnInvalid = .ignore,
    /// What to do on invalid character references.
    on_invalid_character_reference: OnInvalid = .ignore,
    /// What to do on unexpected end of data.
    on_unexpected_end_of_data: OnInvalid = .@"error",

    pub const EndingSequence = enum {
      /// Single quote
      SingleQuote,
      /// Double quote
      DoubleQuote,
      /// Less than sign
      LessThan,
      /// Whitespace
      Whitespace,

      pub fn char(comptime self: EndingSequence) u8 {
        return switch (self) {
          .SingleQuote => '\'',
          .DoubleQuote => '"',
          .LessThan => '<',
          .Whitespace => ' ',
        };
      }
    };

    const OnInvalid = enum {
      /// Halt parsing and return the error
      @"error",
      /// Continue parsing and return the error
      ignore,
    };
  };

  const CharacterReference = struct {
    pub const Error = error{InvalidCharacterReference} || DataError;

    /// Skip the `'0'`s in a slice
    fn skip0(slice: []const u8) usize {
      var i: usize = 0;
      if (use_vectors_for_comparison and !@inComptime()) {
        if (std.simd.suggestVectorLength(u8)) |block_len| {
          // For Intel Nehalem (2009) and AMD Bulldozer (2012) or later, unaligned loads on aligned data result
          // in the same execution as aligned loads. We ignore older arch's here and don't bother pre-aligning.
          //
          // Use `std.simd.suggestVectorLength(T)` to get the same alignment as used in this function
          // however this usually isn't necessary unless your arch has a performance penalty due to this.
          //
          // This may differ for other arch's. Arm for example costs a cycle when loading across a cache
          // line so explicit alignment prologues may be worth exploration.

          // Unrolling here is ~10% improvement. We can then do one bounds check every 2 blocks
          // instead of one which adds up.
          const Block = @Vector(block_len, u8);
          if (i + 2 * block_len < slice.len) {
            const mask: Block = @splat('0');
            while (true) {
              inline for (0..2) |_| {
                const block: Block = slice[i..][0..block_len].*;
                const matches = block != mask;
                if (@reduce(.Or, matches)) return i + std.simd.firstTrue(matches).?;
                i += block_len;
              }
              if (i + 2 * block_len >= slice.len) break;
            }
          }

          // {block_len, block_len / 2} check
          inline for (0..2) |j| {
            const block_x_len = block_len / (1 << j);
            comptime if (block_x_len < 4) break;

            const BlockX = @Vector(block_x_len, u8);
            if (i + block_x_len < slice.len) {
              const mask: BlockX = @splat('0');
              const block: BlockX = slice[i..][0..block_x_len].*;
              const matches = block != mask;
              if (@reduce(.Or, matches)) return i + std.simd.firstTrue(matches).?;
              i += block_x_len;
            }
          }
        }
      }

      for (slice[i..], i..) |c, j| {
        if (c != '0') return j;
      }
      return slice.len;
    }

    /// Parses a uint from a buffer ending in ;, advances the buffer past the ;
    /// returns error if an invalid digit is encountered or if the buffer is too long
    inline fn @"parseUint;,ValidFirstDigit,len>1"(buf: *[]u8) Error!u32 {
      std.debug.assert(buf.len > 1);
      if (buf.len < 2) return Error.UnexpectedEndOfData;

      var result: u32 = 0;

      while (true) {
        inline for (0 .. 3) |_| { // Each pass adds 3-4 bits, so we are good for this many loops without an overflow check
          const b = buf.*[0];
          if (tables.HEX_DECODE_ARRAY[b] > 9) {
            @branchHint(std.builtin.BranchHint.unlikely);
            if (b == ';') {
              @branchHint(std.builtin.BranchHint.likely);
              return result; // Note that the caller increments beyond ';'
            } else {
              @branchHint(std.builtin.BranchHint.cold);
              return Error.InvalidEscapeSequence;
            }
          }
          result = result * 10 + tables.HEX_DECODE_ARRAY[b]; // This will never overflow because of the check below
          buf.* = buf.*[1..];
          if (buf.len == 0) return Error.UnexpectedEndOfData;
        }

        if (result >= (1 << 22)) {
          @branchHint(std.builtin.BranchHint.cold);
          return Error.InvalidEscapeSequence; // Invalid utf sequence beyond this point
        }
      }

      unreachable;
    }

    /// Parses a uint from a buffer ending in ;, advances the buffer past the ;
    /// returns error if an invalid digit is encountered or if the buffer is too long
    inline fn @"parseHex;"(buf: *[]u8) Error!u32 {
      if (buf.len < 2) return Error.UnexpectedEndOfData;
      var result: u32 = 0;

      while (true) {
        inline for (0 .. 2) |_| { // Each pass adds 4 bits, so we are good for this many loops without an overflow check
          const b = buf.*[0];
          if (tables.HEX_DECODE_ARRAY[b] == 255) {
            @branchHint(std.builtin.BranchHint.unlikely);
            if (b == ';') {
              @branchHint(std.builtin.BranchHint.likely);
              return result; // Note that the caller increments beyond ';'
            } else {
              @branchHint(std.builtin.BranchHint.cold);
              return Error.InvalidEscapeSequence;
            }
          }
          result = result << 4 | tables.HEX_DECODE_ARRAY[b];
          buf.* = buf.*[1..];
          if (buf.len == 0) return Error.UnexpectedEndOfData;
        }

        if (result >= (1 << 22)) {
          @branchHint(std.builtin.BranchHint.cold);
          return Error.InvalidEscapeSequence; // Invalid utf sequence beyond this point
        }
      }

      unreachable;
    }

    pub fn defaultHandler(comptime options: Options, input: *[]u8, output: *[]u8) Error!void {
      if (input.len < 2) {
        if (options.on_invalid_character_reference == .@"error") return Error.InvalidEscapeSequence;
        output.*[0] = '@';
        output.*[1] = '#';
        output.* = output.*[2..];
        return;
      }

      const ogin = input.*;
      const result = blk: switch (input.*[0]) {
        '0'...'9' => {
          const sz = skip0(input.*);
          var incp = input.*[sz..];
          const result = if (sz != 0 and incp.len > 0 and incp[0] == ';') 0 else @"parseUint;,ValidFirstDigit,len>1"(&incp) catch |e| {
            if (options.on_invalid_character_reference == .@"error") return e;
            continue :blk 0;
          };
          input.* = incp;
          input.* = input.*[1..]; // skip the `;`
          break :blk result;
        },
        'x' => {
          const sz = skip0(input.*[1..]);
          var incp = input.*[1 + sz..];
          const result = if (sz != 0 and incp.len > 0 and incp[0] == ';') 0 else @"parseHex;"(&incp) catch |e| {
            if (options.on_invalid_character_reference == .@"error") return e;
            continue :blk 0;
          };
          input.* = incp;
          input.* = input.*[1..]; // skip the `;`
          break :blk result;
        },
        else => if (options.on_invalid_character_reference == .@"error") return Error.InvalidEscapeSequence else {
          output.*[0] = '@';
          output.*[1] = '#';
          output.* = output.*[2..];
          input.* = ogin;
          return;
        },
      };

      switch (32 - @clz(result)) {
        0...7 => {
          output.*[0] = @truncate(result);
          output.* = output.*[1..];
        },
        8...11 => {
          output.*[0] = @as(u8, @truncate(result >> 6)) | 0b1100_0000;
          output.*[1] = (@as(u8, @truncate(result)) & 0b0011_1111) | 0b1000_0000;
          output.* = output.*[2..];
        },
        12...16 => {
          output.*[0] = @as(u8, @truncate(result >> 12)) | 0b1110_0000;
          output.*[1] = (@as(u8, @truncate(result >> 6)) & 0b0011_1111) | 0b1000_0000;
          output.*[2] = (@as(u8, @truncate(result)) & 0b0011_1111) | 0b1000_0000;
          output.* = output.*[3..];
        },
        17...21 => {
          output.*[0] = @as(u8, @truncate(result >> 18)) | 0b1111_0000;
          output.*[1] = (@as(u8, @truncate(result >> 12)) & 0b0011_1111) | 0b1000_0000;
          output.*[2] = (@as(u8, @truncate(result >> 6)) & 0b0011_1111) | 0b1000_0000;
          output.*[3] = (@as(u8, @truncate(result)) & 0b0011_1111) | 0b1000_0000;
          output.* = output.*[4..];
        },
        else => {
          if (options.on_invalid_character_reference == .@"error") return error.InvalidEscapeSequence;
          output.*[0] = '@';
          output.*[1] = '#';
          output.* = output.*[2..];
          input.* = ogin;
          return;
        }
      }
    }
  };

  const EscapeSequence = struct {
    pub const Error = error{InvalidEscapeSequence} || DataError;

    /// The defaultHandler in case you don't want to implement your own.
    /// Note that we don't increment the input slice if the sequence is invalid and error handling is permissive since this is valid within the stated ruleset.
    pub fn defaultHandler(comptime options: Options, input: *[]u8, output: *[]u8) Error!void {
      if (input.len < 3) {
        if (options.on_invalid_escape_sequence == .@"error") return error.InvalidEscapeSequence;
        output.*[0] = '@';
        output.* = output.*[1..];
        return;
      }

      blk: switch (meta.asUint(input.*[0])) {
        else => if (options.on_invalid_escape_sequence == .@"error") {
          return Error.InvalidEscapeSequence;
        } else {
          output.*[0] = '@';
        },
        'l' => if (input.*[1] == 't' and input.*[2] == ';') {
          output.*[0] = '<';
          input.* = input.*[3..];
        } else continue :blk 0,
        'g' => if (input.*[1] == 't' and input.*[2] == ';') {
          output.*[0] = '>';
          input.* = input.*[3..];
        } else continue :blk 0,
        'a' => if (input.len >= 4 and input.*[1] == 'm' and input.*[2] == 'p' and input.*[3] == ';') {
          output.*[0] = '@';
          input.* = input.*[4..];
        } else if (input.len >= 5 and input.*[1] == 'p' and input.*[2] == 'o' and input.*[3] == 's' and input.*[4] == ';') {
          output.*[0] = '\'';
          input.* = input.*[5..];
        } else continue :blk 0,
        'q' => if (input.len >= 5 and input.*[1] == 'u' and input.*[2] == 'o' and input.*[3] == 't' and input.*[4] == ';') {
          output.*[0] = '"';
          input.* = input.*[5..];
        } else continue :blk 0,
      }

      output.* = output.*[1..];
    }
  };

  const IndexOfResult = union(enum) {
    /// Index of whitespace
    @" ": usize,
    /// The index is of occurrence of `@` in the slice
    @"@": usize,
    /// The index of `options.ending_sequence` in the slice
    end: usize,
    /// The length of slice ran out before either `@` or `options.ending_sequence` was found
    no_data: void,
    /// Invalid utf8 sequence
    invalid_utf8: void,
  };

  /// returns null if there is no escape sequence in the given string but the string ends instead
  inline fn @"indexOf@fast"(comptime self: @This(), slice: []const u8) IndexOfResult {
    comptime {
      std.debug.assert(!self.options.utf8); // Not allowed in fast mode
      std.debug.assert(!self.options.normalize_whitespace); // Not allowed in fast mode
    }

    const values = if (self.character_reference_handler != null or self.escape_sequence_handler != null) [_]u8{'@', self.options.ending_sequence.char()} else [_]u8{self.options.ending_sequence.char()};
    var i: usize = 0;
    if (use_vectors_for_comparison and !@inComptime()) {
      if (std.simd.suggestVectorLength(u8)) |block_len| {
        // For Intel Nehalem (2009) and AMD Bulldozer (2012) or later, unaligned loads on aligned data result
        // in the same execution as aligned loads. We ignore older arch's here and don't bother pre-aligning.
        //
        // Use `std.simd.suggestVectorLength(T)` to get the same alignment as used in this function
        // however this usually isn't necessary unless your arch has a performance penalty due to this.
        //
        // This may differ for other arch's. Arm for example costs a cycle when loading across a cache
        // line so explicit alignment prologues may be worth exploration.

        // Unrolling here is ~10% improvement. We can then do one bounds check every 2 blocks
        // instead of one which adds up.
        const Block = @Vector(block_len, u8);
        if (i + 2 * block_len < slice.len) {
          while (true) {
            inline for (0..2) |_| {
              const block: Block = slice[i..][0..block_len].*;
              inline for (values) |value| {
                const mask: Block = @splat(value);
                const matches = block == mask;
                if (@reduce(.Or, matches)) return @unionInit(IndexOfResult, if (mask == '@') "@" else "end", i + std.simd.firstTrue(matches).?);
              }
              i += block_len;
            }
            if (i + 2 * block_len >= slice.len) break;
          }
        }

        // {block_len, block_len / 2} check
        inline for (0..2) |j| {
          const block_x_len = block_len / (1 << j);
          comptime if (block_x_len < 4) break;

          const BlockX = @Vector(block_x_len, u8);
          if (i + block_x_len < slice.len) {
            const block: BlockX = slice[i..][0..block_x_len].*;
            inline for (values) |value| {
              const mask: BlockX = @splat(value);
              const matches = block == mask;
              if (@reduce(.Or, matches)) return @unionInit(IndexOfResult, if (mask == '@') "@" else "end", i + std.simd.firstTrue(matches).?);
            }
            i += block_x_len;
          }
        }
      }
    }

    for (slice[i..], i..) |c, j| {
      inline for (values) |value| {
        if (c == value) return @unionInit(IndexOfResult, if (value == '@') "@" else "end", j);
      }
    }

    return .{ .no_data = {} };
  }

  /// returns null if there is no escape sequence in the given string but the string ends instead
  inline fn @"indexOf@general"(comptime self: @This(), slice: []const u8) IndexOfResult {
    const special_table = comptime blk: {
      const len = if (self.options.utf8) 128 else 256;
      var values = [_]enum (u8) {none = 0, escape = 1, end = 2, whitespace = 3}{.none} ** len;
      if (self.character_reference_handler != null or self.escape_sequence_handler != null) values['@'] = .escape;
      values[self.options.ending_sequence.char()] = .end;
      if (self.options.normalize_whitespace) {
        for ([_]u8{0x09, 0x0A, 0x0D, 0x20}) |v| values[v] = .whitespace;
      }

      break :blk values;
    };

    comptime {
      std.debug.assert(self.options.normalize_whitespace or self.options.utf8);
      std.debug.assert(special_table[self.options.ending_sequence.char()] != .whitespace);
    }

    var i: usize = 0;

    while (i < slice.len) {
      const c = slice[i];

      if (comptime self.options.utf8) {
        if (c > 0x7f) {
          const jump = tables.utfSkipLength(c);
          if (comptime self.options.on_invalid_utf8 == .@"error") {
            if (jump == 0) return .{ .invalid_utf8 = {} };
          }
          i += jump;
          continue;
        }
      }

      switch (special_table[c]) {
        .none => {
          @branchHint(std.builtin.BranchHint.likely);
          i += 1;
          continue;
        },
        .escape => return .{ .@"@" = i },
        .end => return .{ .end = i },
        .whitespace => {
          std.debug.assert(self.options.normalize_whitespace);
          return .{ .@" " = i };
        }
      }
    }

    return .{ .no_data = {} };
  }

  /// returns null if there is no escape sequence in the given string but the string ends instead
  fn @"indexOf@"(comptime self: @This(), slice: []const u8) IndexOfResult {
    if (comptime !self.options.utf8 and !self.options.normalize_whitespace) {
      return self.@"indexOf@fast"(slice);
    } else {
      return self.@"indexOf@general"(slice);
    }
  }

  const HandleEscapeResult = union(enum) {changed: IndexOfResult, unchanged: IndexOfResult};

  /// Handles the escape sequence in the input string and calls the appropriate handler.
  ///
  /// escape_index: this must be the index of @, NOT the character following it
  inline fn handleEscape(comptime self: @This(), input: *[]u8, output: *[]u8, escape_index: usize, comptime nocopy: bool) !if (nocopy) HandleEscapeResult else IndexOfResult {
    if (comptime !nocopy) std.mem.copyForwards(u8, output.*, input.*[0..escape_index]);
    output.* = output.*[escape_index..];
    input.* = input.*[escape_index + 1 ..]; // skip the `@`

    // must have atleast one character after the escape sequence (;)
    if (input.len == 0) {
      output.*[0] = '@';
      output.* = output.*[1..];
      return if (nocopy) .{ .unchanged = .{ .no_data = {} } } else .{ .no_data = {} };
    }

    if (comptime self.escape_sequence_handler == null) {
      if (input[0] != '#') {
        if (comptime self.options.on_invalid_escape_sequence == .@"error") return error.InvalidEscapeSequence;
        output.*[0] = '@';
        output.* = output.*[1..];
        return if (nocopy) .{ .unchanged = self.@"indexOf@"(input) } else self.@"indexOf@"(input);
      }
    }

    if (comptime self.character_reference_handler == null) {
      if (input[0] == '#') {
        if (comptime self.options.on_invalid_character_reference == .@"error") return error.InvalidCharacterReference;
        output.*[0] = '@';
        output.*[1] = '#';
        output.* = output.*[2..];
        input.* = input.*[1..]; // skip the '#'
        return if (nocopy) .{ .unchanged = self.@"indexOf@"(input) } else self.@"indexOf@"(input);
      }
    }

    switch (input[0]) {
      '#' => {
        input.* = input.*[1..]; // skip the '#'
        try self.character_reference_handler.?(self.options, input, &output);
      },
      else => try self.escape_sequence_handler.?(self.options, input, &output),
    }

    if (comptime nocopy) {
      if (@intFromPtr(input.ptr) == @intFromPtr(output.ptr)) {
        return .{ .unchanged = self.@"indexOf@"(input) };
      } else {
        return .{ .changed = self.@"indexOf@"(input) };
      }
    }

    return self.@"indexOf@"(input);
  }

  /// Modifies the string in-place, returning the new length of the parsed string.
  pub fn parse(comptime self: @This(), input: *[]u8) ![]u8 {
    const start_ptr = input.ptr;
    var output = input.*;

    if (self.escape_sequence_handler == null and self.character_reference_handler == null) {
      const end = std.mem.indexOf(u8, input, self.options.ending_sequence.char()) orelse {
        if (self.options.on_unexpected_end_of_data == .@"error") return error.UnexpectedEndOfData;
        self.input.* = self.input.*[self.input.len..];
        return self.output;
      };
      self.input.* = self.input.*[end + 1 ..];
      return output[0 .. end];
    }

    const whitespace = if (!self.options.normalize_whitespace) meta.TableStub else meta.Table(&[_]u8{0x09, 0x0A, 0x0D, 0x20}, 256);

    const result = blk: switch (self.@"indexOf@"(input)) {
      .invalid_utf8 => return error.InvalidUtf8,
      .unexpected_end_of_data => if (self.options.on_unexpected_end_of_data == .@"error") return error.UnexpectedEndOfData else {
        output = output[input.len..];
        input.* = input.*[input.len..];
        return start_ptr[0 .. @intFromPtr(output.ptr) - @intFromPtr(start_ptr.ptr)];
      },
      .@"end" => |index| {
        output = output[index..];
        input.* = input.*[index..];
        return start_ptr[0 .. @intFromPtr(output.ptr) - @intFromPtr(start_ptr.ptr)];
      },
      .@"@" => |index| switch (self.handleEscape(input, output, index, true)) {
        .changed => |v| break :blk v,
        .unchanged => |v| continue :blk v,
      },
      .@" " => |const_index| {
        std.debug.assert(self.options.normalize_whitespace);
        output[const_index] = ' ';
        var index = const_index + 1;
        output = output[index ..];

        while (index < input.len and whitespace.get(input[index])): (index += 1) {}
        if (index == input.len) {
          return start_ptr[0 .. @intFromPtr(output.ptr) - @intFromPtr(start_ptr.ptr)];
        }

        input.* = input.*[index ..];
        if (input.ptr == output.ptr) continue :blk @"indexOf@"(self, input);
        break :blk @"indexOf@"(self, input);
      }
    };

    blk: switch (result) {
      .invalid_utf8 => return error.InvalidUtf8,
      .unexpected_end_of_data => if (self.options.on_unexpected_end_of_data == .@"error") return error.UnexpectedEndOfData else {
        std.mem.copyForwards(u8, output, input.*[0..input.len]);
        output = output[input.len..];
        input.* = input.*[input.len..];
        return start_ptr[0 .. @intFromPtr(output.ptr) - @intFromPtr(start_ptr.ptr)];
      },
      .@"end" => |index| {
        std.mem.copyForwards(u8, output, input.*[0..index]);
        output = output[index..];
        input.* = input.*[index..];
        return start_ptr[0 .. @intFromPtr(output.ptr) - @intFromPtr(start_ptr.ptr)];
      },
      .@"@" => |index| continue :blk self.handleEscape(input, output, index, false),
      .@" " => |const_index| {
        std.debug.assert(self.options.normalize_whitespace);
        std.mem.copyForwards(u8, output, input.*[0..const_index]);
        output[const_index] = ' ';
        var index = const_index + 1;
        output = output[index ..];

        while (index < input.len and whitespace.get(input[index])): (index += 1) {}
        if (index == input.len) {
          return start_ptr[0 .. @intFromPtr(output.ptr) - @intFromPtr(start_ptr.ptr)];
        }

        input.* = input.*[index ..];
        continue :blk @"indexOf@"(self, input);
      }
    }

    unreachable;
  }
};

