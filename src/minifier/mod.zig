// Main minifier module that exports all components
pub const types = @import("types.zig");
pub const utils = @import("utils.zig");
pub const pretty = @import("pretty.zig");
pub const handlers = @import("handlers.zig");

// Phase 1 Optimizations
pub const simd_utils = @import("simd_utils.zig");
pub const optimized_handlers = @import("optimized_handlers.zig");
pub const optimized_types = @import("optimized_types.zig");
pub const optimized_buffer = @import("optimized_buffer.zig");

// Phase 3 Advanced Algorithms
pub const predictive_parser = @import("predictive_parser.zig");
pub const zero_copy = @import("zero_copy.zig");
pub const optimized_state_machine = @import("optimized_state_machine.zig");

// Re-export the main parser type for convenience
pub const MinifyingParser = types.MinifyingParser;
pub const Context = types.Context;
pub const State = types.State;

// Re-export optimized parser types
pub const OptimizedMinifyingParser = optimized_types.OptimizedMinifyingParser;
pub const AlignedBuffer = optimized_types.AlignedBuffer;
pub const OptimizedWorkItem = optimized_types.OptimizedWorkItem;

// Re-export optimized buffer types
pub const OptimizedBuffer = optimized_buffer.OptimizedBuffer;
pub const RingBuffer = optimized_buffer.RingBuffer;
pub const BufferPool = optimized_buffer.BufferPool;

// Re-export utility functions
pub const isWhitespace = utils.isWhitespace;
pub const isHexDigit = utils.isHexDigit;
pub const skipWhitespaceSimd = utils.skipWhitespaceSimd;

// Re-export SIMD utilities
pub const SimdUtils = simd_utils.SimdUtils;
pub const classifyCharsSimd = simd_utils.SimdUtils.classifyCharsSimd;
pub const copyStringSimd = simd_utils.SimdUtils.copyStringSimd;
pub const findNumberEndSimd = simd_utils.SimdUtils.findNumberEndSimd;
pub const skipWhitespaceSimd64 = simd_utils.SimdUtils.skipWhitespaceSimd64;
pub const findStructureBoundarySimd = simd_utils.SimdUtils.findStructureBoundarySimd;

// Re-export optimized handlers
pub const handleTopLevelOptimized = optimized_handlers.handleTopLevelOptimized;
pub const handleStringOptimized = optimized_handlers.handleStringOptimized;
pub const handleNumberOptimized = optimized_handlers.handleNumberOptimized;
pub const handleObjectValueOptimized = optimized_handlers.handleObjectValueOptimized;
pub const handleArrayValueOptimized = optimized_handlers.handleArrayValueOptimized;
pub const processStringSimd = optimized_handlers.processStringSimd;
pub const processNumberSimd = optimized_handlers.processNumberSimd;

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

// Re-export Phase 3 components
pub const PredictiveParser = predictive_parser.PredictiveParser;
pub const ZeroCopyProcessor = zero_copy.ZeroCopyProcessor;
pub const OptimizedStateMachine = optimized_state_machine.OptimizedStateMachine;
