// Main minifier module that exports all components
pub const types = @import("types.zig");
pub const utils = @import("utils.zig");
pub const pretty = @import("pretty.zig");
pub const handlers = @import("handlers.zig");

// Re-export the main parser type for convenience
pub const MinifyingParser = types.MinifyingParser;
pub const Context = types.Context;
pub const State = types.State;

// Re-export utility functions
pub const isWhitespace = utils.isWhitespace;
pub const isHexDigit = utils.isHexDigit;
pub const skipWhitespaceSimd = utils.skipWhitespaceSimd;

// Re-export pretty printing functions
pub const writeByte = pretty.writeByte;
pub const writeBytes = pretty.writeBytes;
pub const writeIndent = pretty.writeIndent;
pub const writeNewline = pretty.writeNewline;
pub const writeIndentIfNeeded = pretty.writeIndentIfNeeded;
pub const increaseIndent = pretty.increaseIndent;
pub const decreaseIndent = pretty.decreaseIndent;

// Re-export all handler functions
pub const handleTopLevel = handlers.handleTopLevel;
pub const handleObjectStart = handlers.handleObjectStart;
pub const handleObjectKey = handlers.handleObjectKey;
pub const handleObjectKeyString = handlers.handleObjectKeyString;
pub const handleObjectKeyStringEscape = handlers.handleObjectKeyStringEscape;
pub const handleObjectKeyStringEscapeUnicode = handlers.handleObjectKeyStringEscapeUnicode;
pub const handleObjectColon = handlers.handleObjectColon;
pub const handleObjectValue = handlers.handleObjectValue;
pub const handleObjectComma = handlers.handleObjectComma;
pub const handleArrayStart = handlers.handleArrayStart;
pub const handleArrayValue = handlers.handleArrayValue;
pub const handleArrayComma = handlers.handleArrayComma;
pub const handleString = handlers.handleString;
pub const handleStringEscape = handlers.handleStringEscape;
pub const handleStringEscapeUnicode = handlers.handleStringEscapeUnicode;
pub const handleNumber = handlers.handleNumber;
pub const handleNumberDecimal = handlers.handleNumberDecimal;
pub const handleNumberExponent = handlers.handleNumberExponent;
pub const handleNumberExponentSign = handlers.handleNumberExponentSign;
pub const handleTrue = handlers.handleTrue;
pub const handleFalse = handlers.handleFalse;
pub const handleNull = handlers.handleNull;
