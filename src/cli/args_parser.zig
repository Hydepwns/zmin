//! Enhanced command-line argument parser with auto-completion support
//!
//! This module provides a robust argument parser with support for subcommands,
//! flags, and shell completion generation.

const std = @import("std");
const zmin = @import("zmin_lib");

/// Command-line options
pub const Options = struct {
    /// Input file path (- for stdin)
    input: ?[]const u8 = null,
    /// Output file path (- for stdout)
    output: ?[]const u8 = null,
    /// Processing mode
    mode: zmin.ProcessingMode = .sport,
    /// Enable verbose output
    verbose: bool = false,
    /// Suppress all output
    quiet: bool = false,
    /// Number of threads (turbo mode)
    threads: ?u32 = null,
    /// Show help
    help: bool = false,
    /// Show version
    version: bool = false,
    /// Validate only (don't minify)
    validate_only: bool = false,
    /// Show performance statistics
    show_stats: bool = false,
    /// Enter interactive mode
    interactive: bool = false,
    /// Generate shell completion
    completion: ?Shell = null,
    /// Run benchmark
    benchmark: bool = false,
    /// Benchmark iterations
    benchmark_iterations: u32 = 100,
};

/// Supported shells for completion
pub const Shell = enum {
    bash,
    zsh,
    fish,
    powershell,
};

/// Parse result
pub const ParseResult = union(enum) {
    options: Options,
    error_message: []const u8,
};

/// Argument parser
pub const ArgParser = struct {
    allocator: std.mem.Allocator,
    program_name: []const u8,

    pub fn init(allocator: std.mem.Allocator, program_name: []const u8) ArgParser {
        return .{
            .allocator = allocator,
            .program_name = program_name,
        };
    }

    pub fn parse(self: *ArgParser, args: []const []const u8) !ParseResult {
        var options = Options{};
        var positional_count: usize = 0;

        var i: usize = 0;
        while (i < args.len) : (i += 1) {
            const arg = args[i];

            if (std.mem.startsWith(u8, arg, "--")) {
                // Long option
                if (std.mem.eql(u8, arg, "--help")) {
                    options.help = true;
                } else if (std.mem.eql(u8, arg, "--version")) {
                    options.version = true;
                } else if (std.mem.eql(u8, arg, "--verbose")) {
                    options.verbose = true;
                } else if (std.mem.eql(u8, arg, "--quiet")) {
                    options.quiet = true;
                } else if (std.mem.eql(u8, arg, "--validate")) {
                    options.validate_only = true;
                } else if (std.mem.eql(u8, arg, "--stats")) {
                    options.show_stats = true;
                } else if (std.mem.eql(u8, arg, "--interactive")) {
                    options.interactive = true;
                } else if (std.mem.eql(u8, arg, "--benchmark")) {
                    options.benchmark = true;
                } else if (std.mem.startsWith(u8, arg, "--mode=")) {
                    const mode_str = arg[7..];
                    options.mode = try parseMode(mode_str);
                } else if (std.mem.startsWith(u8, arg, "--threads=")) {
                    const threads_str = arg[10..];
                    options.threads = try std.fmt.parseInt(u32, threads_str, 10);
                } else if (std.mem.startsWith(u8, arg, "--benchmark-iterations=")) {
                    const iter_str = arg[23..];
                    options.benchmark_iterations = try std.fmt.parseInt(u32, iter_str, 10);
                } else if (std.mem.startsWith(u8, arg, "--completion=")) {
                    const shell_str = arg[13..];
                    options.completion = try parseShell(shell_str);
                } else {
                    return ParseResult{ .error_message = try std.fmt.allocPrint(self.allocator, "Unknown option: {s}", .{arg}) };
                }
            } else if (std.mem.startsWith(u8, arg, "-") and arg.len > 1) {
                // Short options (can be combined like -vq)
                for (arg[1..]) |c| {
                    switch (c) {
                        'h' => options.help = true,
                        'V' => options.version = true,
                        'v' => options.verbose = true,
                        'q' => options.quiet = true,
                        'm' => {
                            // -m requires a value
                            if (i + 1 >= args.len) {
                                return ParseResult{ .error_message = "Option -m requires a value" };
                            }
                            i += 1;
                            options.mode = try parseMode(args[i]);
                        },
                        't' => {
                            // -t requires a value
                            if (i + 1 >= args.len) {
                                return ParseResult{ .error_message = "Option -t requires a value" };
                            }
                            i += 1;
                            options.threads = try std.fmt.parseInt(u32, args[i], 10);
                        },
                        else => {
                            return ParseResult{ .error_message = try std.fmt.allocPrint(self.allocator, "Unknown option: -{c}", .{c}) };
                        },
                    }
                }
            } else {
                // Positional argument
                if (positional_count == 0) {
                    options.input = arg;
                } else if (positional_count == 1) {
                    options.output = arg;
                } else {
                    return ParseResult{ .error_message = "Too many positional arguments" };
                }
                positional_count += 1;
            }
        }

        // Validate options
        if (options.verbose and options.quiet) {
            return ParseResult{ .error_message = "Cannot use --verbose and --quiet together" };
        }

        return ParseResult{ .options = options };
    }

    fn parseMode(mode_str: []const u8) !zmin.ProcessingMode {
        if (std.mem.eql(u8, mode_str, "eco")) {
            return .eco;
        } else if (std.mem.eql(u8, mode_str, "sport")) {
            return .sport;
        } else if (std.mem.eql(u8, mode_str, "turbo")) {
            return .turbo;
        } else {
            return error.InvalidMode;
        }
    }

    fn parseShell(shell_str: []const u8) !Shell {
        if (std.mem.eql(u8, shell_str, "bash")) {
            return .bash;
        } else if (std.mem.eql(u8, shell_str, "zsh")) {
            return .zsh;
        } else if (std.mem.eql(u8, shell_str, "fish")) {
            return .fish;
        } else if (std.mem.eql(u8, shell_str, "powershell")) {
            return .powershell;
        } else {
            return error.InvalidShell;
        }
    }

    pub fn printHelp(self: *ArgParser, writer: anytype) !void {
        try writer.print(
            \\Usage: {s} [OPTIONS] [INPUT] [OUTPUT]
            \\
            \\High-performance JSON minifier
            \\
            \\Arguments:
            \\  INPUT    Input JSON file (default: stdin)
            \\  OUTPUT   Output file (default: stdout)
            \\
            \\Options:
            \\  -h, --help                    Show this help message
            \\  -V, --version                 Show version information
            \\  -v, --verbose                 Enable verbose output
            \\  -q, --quiet                   Suppress all output
            \\  -m, --mode=MODE               Set processing mode (eco/sport/turbo)
            \\  -t, --threads=N               Number of threads for turbo mode
            \\      --validate                Validate JSON without minifying
            \\      --stats                   Show performance statistics
            \\      --interactive             Enter interactive mode
            \\      --benchmark               Run performance benchmark
            \\      --benchmark-iterations=N  Set benchmark iterations (default: 100)
            \\      --completion=SHELL        Generate shell completion script
            \\
            \\Processing Modes:
            \\  eco    Memory-efficient mode (64KB limit)
            \\  sport  Balanced performance (default)
            \\  turbo  Maximum speed using all CPU cores
            \\
            \\Examples:
            \\  {s} input.json output.json
            \\  {s} --mode=turbo large.json compressed.json
            \\  echo '{{}}' | {s} --validate
            \\  {s} --completion=bash > /etc/bash_completion.d/zmin
            \\
        , .{ self.program_name, self.program_name, self.program_name, self.program_name, self.program_name });
    }

    pub fn printVersion(self: *ArgParser, writer: anytype) !void {
        _ = self;
        try writer.print(
            \\zmin version 1.0.0
            \\High-performance JSON minifier written in Zig
            \\
            \\Copyright (c) 2024
            \\License: MIT
            \\
        , .{});
    }
};

/// Generate shell completion script
pub fn generateCompletion(shell: Shell, program_name: []const u8, writer: anytype) !void {
    switch (shell) {
        .bash => try generateBashCompletion(program_name, writer),
        .zsh => try generateZshCompletion(program_name, writer),
        .fish => try generateFishCompletion(program_name, writer),
        .powershell => try generatePowerShellCompletion(program_name, writer),
    }
}

fn generateBashCompletion(program_name: []const u8, writer: anytype) !void {
    try writer.print(
        \\# Bash completion for {s}
        \\_{s}() {{
        \\    local cur prev opts
        \\    COMPREPLY=()
        \\    cur="${{COMP_WORDS[COMP_CWORD]}}"
        \\    prev="${{COMP_WORDS[COMP_CWORD-1]}}"
        \\    
        \\    # Options
        \\    opts="--help --version --verbose --quiet --mode --threads --validate --stats --interactive --benchmark --completion"
        \\    short_opts="-h -V -v -q -m -t"
        \\    
        \\    # Mode values
        \\    modes="eco sport turbo"
        \\    
        \\    # Shell values
        \\    shells="bash zsh fish powershell"
        \\    
        \\    case "${{prev}}" in
        \\        --mode|-m)
        \\            COMPREPLY=( $(compgen -W "${{modes}}" -- "${{cur}}") )
        \\            return 0
        \\            ;;
        \\        --threads|-t)
        \\            COMPREPLY=( $(compgen -W "1 2 4 8 16 32" -- "${{cur}}") )
        \\            return 0
        \\            ;;
        \\        --completion)
        \\            COMPREPLY=( $(compgen -W "${{shells}}" -- "${{cur}}") )
        \\            return 0
        \\            ;;
        \\        --benchmark-iterations)
        \\            COMPREPLY=( $(compgen -W "10 100 1000" -- "${{cur}}") )
        \\            return 0
        \\            ;;
        \\    esac
        \\    
        \\    # Complete options
        \\    if [[ ${{cur}} == --* ]]; then
        \\        COMPREPLY=( $(compgen -W "${{opts}}" -- "${{cur}}") )
        \\        return 0
        \\    elif [[ ${{cur}} == -* ]]; then
        \\        COMPREPLY=( $(compgen -W "${{short_opts}}" -- "${{cur}}") )
        \\        return 0
        \\    fi
        \\    
        \\    # Complete files
        \\    COMPREPLY=( $(compgen -f -- "${{cur}}") )
        \\}}
        \\
        \\complete -F _{s} {s}
        \\
    , .{ program_name, program_name, program_name, program_name });
}

fn generateZshCompletion(program_name: []const u8, writer: anytype) !void {
    try writer.print(
        \\#compdef {s}
        \\
        \\_{s}() {{
        \\    local -a args
        \\    args=(
        \\        '(-h --help){{-h,--help}}'[Show help message]'
        \\        '(-V --version){{-V,--version}}'[Show version information]'
        \\        '(-v --verbose){{-v,--verbose}}'[Enable verbose output]'
        \\        '(-q --quiet){{-q,--quiet}}'[Suppress all output]'
        \\        '(-m --mode){{-m,--mode}}=[Set processing mode]:mode:(eco sport turbo)'
        \\        '(-t --threads){{-t,--threads}}=[Number of threads]:threads:'
        \\        '--validate[Validate JSON without minifying]'
        \\        '--stats[Show performance statistics]'
        \\        '--interactive[Enter interactive mode]'
        \\        '--benchmark[Run performance benchmark]'
        \\        '--benchmark-iterations=[Set benchmark iterations]:iterations:'
        \\        '--completion=[Generate shell completion]:shell:(bash zsh fish powershell)'
        \\        '1:input file:_files -g "*.json"'
        \\        '2:output file:_files'
        \\    )
        \\    
        \\    _arguments -s $args
        \\}}
        \\
        \\_{s} "$@"
        \\
    , .{ program_name, program_name, program_name });
}

fn generateFishCompletion(program_name: []const u8, writer: anytype) !void {
    try writer.print(
        \\# Fish completion for {s}
        \\
        \\# Disable file completion for options
        \\complete -c {s} -f
        \\
        \\# Options
        \\complete -c {s} -s h -l help -d "Show help message"
        \\complete -c {s} -s V -l version -d "Show version information"
        \\complete -c {s} -s v -l verbose -d "Enable verbose output"
        \\complete -c {s} -s q -l quiet -d "Suppress all output"
        \\complete -c {s} -s m -l mode -d "Set processing mode" -a "eco sport turbo"
        \\complete -c {s} -s t -l threads -d "Number of threads"
        \\complete -c {s} -l validate -d "Validate JSON without minifying"
        \\complete -c {s} -l stats -d "Show performance statistics"
        \\complete -c {s} -l interactive -d "Enter interactive mode"
        \\complete -c {s} -l benchmark -d "Run performance benchmark"
        \\complete -c {s} -l benchmark-iterations -d "Set benchmark iterations"
        \\complete -c {s} -l completion -d "Generate shell completion" -a "bash zsh fish powershell"
        \\
        \\# File completion for positional arguments
        \\complete -c {s} -n "__fish_is_first_arg" -a "*.json" -d "Input JSON file"
        \\complete -c {s} -n "not __fish_is_first_arg" -F -d "Output file"
        \\
    , .{ program_name, program_name, program_name, program_name, program_name, program_name, program_name, program_name, program_name, program_name, program_name, program_name, program_name, program_name, program_name, program_name });
}

fn generatePowerShellCompletion(program_name: []const u8, writer: anytype) !void {
    try writer.print(
        \\# PowerShell completion for {s}
        \\
        \\Register-ArgumentCompleter -CommandName {s} -ScriptBlock {{
        \\    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
        \\    
        \\    $options = @{{
        \\        '--help' = 'Show help message'
        \\        '--version' = 'Show version information'
        \\        '--verbose' = 'Enable verbose output'
        \\        '--quiet' = 'Suppress all output'
        \\        '--mode' = 'Set processing mode'
        \\        '--threads' = 'Number of threads'
        \\        '--validate' = 'Validate JSON without minifying'
        \\        '--stats' = 'Show performance statistics'
        \\        '--interactive' = 'Enter interactive mode'
        \\        '--benchmark' = 'Run performance benchmark'
        \\        '--benchmark-iterations' = 'Set benchmark iterations'
        \\        '--completion' = 'Generate shell completion'
        \\    }}
        \\    
        \\    $modes = @('eco', 'sport', 'turbo')
        \\    $shells = @('bash', 'zsh', 'fish', 'powershell')
        \\    
        \\    # Complete based on previous parameter
        \\    if ($commandAst.CommandElements.Count -gt 1) {{
        \\        $prev = $commandAst.CommandElements[-2].ToString()
        \\        
        \\        switch ($prev) {{
        \\            '--mode' {{ $modes | Where-Object {{ $_ -like "$wordToComplete*" }} | ForEach-Object {{ $_ }} }}
        \\            '-m' {{ $modes | Where-Object {{ $_ -like "$wordToComplete*" }} | ForEach-Object {{ $_ }} }}
        \\            '--completion' {{ $shells | Where-Object {{ $_ -like "$wordToComplete*" }} | ForEach-Object {{ $_ }} }}
        \\            '--threads' {{ 1..32 | Where-Object {{ "$_" -like "$wordToComplete*" }} | ForEach-Object {{ "$_" }} }}
        \\            '-t' {{ 1..32 | Where-Object {{ "$_" -like "$wordToComplete*" }} | ForEach-Object {{ "$_" }} }}
        \\            default {{
        \\                # Complete options
        \\                if ($wordToComplete -match '^-') {{
        \\                    $options.Keys | Where-Object {{ $_ -like "$wordToComplete*" }} | ForEach-Object {{
        \\                        [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterName', $options[$_])
        \\                    }}
        \\                }} else {{
        \\                    # Complete files
        \\                    Get-ChildItem -Path . -Filter "*.json" | Where-Object {{ $_.Name -like "$wordToComplete*" }} | ForEach-Object {{
        \\                        [System.Management.Automation.CompletionResult]::new($_.Name, $_.Name, 'ProviderItem', 'JSON file')
        \\                    }}
        \\                }}
        \\            }}
        \\        }}
        \\    }} else {{
        \\        # First argument - complete options or files
        \\        if ($wordToComplete -match '^-') {{
        \\            $options.Keys | Where-Object {{ $_ -like "$wordToComplete*" }} | ForEach-Object {{
        \\                [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterName', $options[$_])
        \\            }}
        \\        }} else {{
        \\            Get-ChildItem -Path . -Filter "*.json" | Where-Object {{ $_.Name -like "$wordToComplete*" }} | ForEach-Object {{
        \\                [System.Management.Automation.CompletionResult]::new($_.Name, $_.Name, 'ProviderItem', 'JSON file')
        \\            }}
        \\        }}
        \\    }}
        \\}}
        \\
    , .{ program_name, program_name });
}
