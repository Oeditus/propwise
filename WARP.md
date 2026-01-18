# WARP.md

This file provides guidance to WARP (warp.dev) when working with code in this repository.

## Project Overview

PropWise is an AST-based analyzer for identifying property-based testing candidates in Elixir codebases. It statically analyzes Elixir code to find pure functions that would benefit from property-based testing by examining the Abstract Syntax Tree.

The tool can be used both as a library and as a command-line escript executable.

## Development Commands

### Building
```bash
# Get dependencies
mix deps.get

# Compile the project
mix compile

# Build the escript executable
mix escript.build
```

### Testing
```bash
# Run all tests
mix test

# Run a specific test file
mix test test/prop_wise_test.exs

# Run tests with coverage
mix test --cover

# Run a specific test by line number
mix test test/prop_wise/parser_test.exs:26
```

### Code Quality
```bash
# Format code (always run before commits)
mix format

# Check code formatting without changing files
mix format --check-formatted
```

### Running the Tool
```bash
# Using Mix task (recommended during development)
mix propwise
mix propwise --min-score 5
mix propwise --format json

# Or using escript (after building)
./propwise .
./propwise --min-score 5 ./path/to/project
./propwise --format json ./path/to/project
```

## Architecture

### Core Components

The codebase follows a pipeline architecture with 8 main modules:

1. **PropWise.Config** (`lib/prop_wise/config.ex`)
   - Loads configuration from `.propwise.exs` file
   - Provides defaults if no config file exists
   - Handles both map and keyword list configurations
   - Main function: `analyze_paths/1` returns directories to analyze

2. **PropWise.Parser** (`lib/prop_wise/parser.ex`)
   - Entry point for AST extraction
   - Recursively finds `.ex` files in the `lib` directory only (does not analyze test files or dependencies)
   - Parses files into ASTs and extracts function definitions with metadata (name, arity, module, args, body, location, visibility)
   - Returns list of function metadata maps

3. **PropWise.PurityAnalyzer** (`lib/prop_wise/purity_analyzer.ex`)
   - Determines if functions are pure (no side effects)
   - Walks AST looking for impure operations:
     - I/O operations (File, IO, Logger)
     - Process operations (GenServer, Agent, Task, Process)
     - Database operations (Ecto)
     - HTTP requests (HTTPoison, Tesla, Req)
     - System calls, message passing (send, spawn, receive)
     - ETS/DETS/Mnesia operations
   - Returns `{:pure, []}` or `{:impure, side_effects}`

4. **PropWise.PatternDetector** (`lib/prop_wise/pattern_detector.ex`)
   - Identifies patterns suitable for property testing:
     - Collection operations (Enum, Stream, comprehensions)
     - Data transformations (pipelines, struct/map manipulation)
     - Validation functions (predicates, checks)
     - Algebraic structures (merge, concat, union, compose)
     - Encoders/decoders (encode/decode, serialize/deserialize)
     - Parsers (string parsing, regex)
     - Numeric algorithms (arithmetic, math operations)
   - Also finds inverse function pairs (encode/decode, to_*/from_*, etc.)
   - Returns list of `{pattern_type, reason}` tuples

5. **PropWise.Analyzer** (`lib/prop_wise/analyzer.ex`)
   - Orchestrates the analysis pipeline
   - Combines purity analysis and pattern detection
   - Calculates testability scores based on:
     - Base score: 1 for pure functions
     - Pattern score: 2 points per detected pattern
     - Multi-pattern bonus: 2 points for functions with 2+ patterns
     - Complexity bonus: 1 point for non-trivial functions (>3 lines or conditional logic)
     - Visibility bonus: 1 point for public functions
   - Generates testing suggestions for each pattern type
   - Filters by minimum score (default: 3)
   - Returns sorted list of candidates

6. **PropWise.Reporter** (`lib/prop_wise/reporter.ex`)
   - Formats analysis results for output
   - Supports text and JSON formats
   - Displays candidates sorted by score with suggestions

7. **PropWise.CLI** (`lib/prop_wise/cli.ex`)
   - Command-line interface for escript
   - Parses CLI arguments (min-score, format, help)
   - Entry point: `main/1` function

8. **Mix.Tasks.Propwise** (`lib/mix/tasks/propwise.ex`)
   - Mix task interface (`mix propwise`)
   - Same functionality as CLI but integrated with Mix
   - Entry point: `run/1` function

### Data Flow

```
Project Path
    ↓
Parser: Extract all functions from .ex files
    ↓
Analyzer: For each function:
    ├─ PurityAnalyzer: Check for side effects
    ├─ PatternDetector: Identify testing patterns
    └─ Score: Calculate testability score
    ↓
PatternDetector: Find inverse function pairs across all functions
    ↓
Reporter: Format and display results
```

### Key Data Structures

**Function Metadata** (from Parser):
```elixir
%{
  module: "ModuleName",
  name: :function_name,
  arity: 2,
  args: [...],
  body: ast,
  file: "path/to/file.ex",
  line: 42,
  type: :public | :private
}
```

**Candidate Result** (from Analyzer):
```elixir
%{
  module: "ModuleName",
  name: :function_name,
  arity: 2,
  file: "path/to/file.ex",
  line: 42,
  type: :public | :private,
  purity: {:pure, []} | {:impure, [effects]},
  patterns: [{:collection_operation, "reason"}, ...],
  score: integer,
  suggestions: ["Test property X", ...]
}
```

## Configuration

PropWise supports configuration via a `.propwise.exs` file in the project root:

```elixir
%{
  analyze_paths: ["lib"]  # Directories to analyze (default: ["lib"])
}
```

The `PropWise.Config` module handles loading and parsing this configuration, with graceful fallback to defaults if the file doesn't exist or is invalid.

## Testing Patterns

The project uses ExUnit. Key patterns:
- Tests use temporary directories created with `System.unique_integer([:positive])` for isolated file operations
- Cleanup happens with `File.rm_rf!/1` after tests
- Pattern matching used to assert on list sizes: `assert [_, _] = list` (preferred over `assert length(list) == 2`)
- Tests are marked `async: true` where possible for parallel execution
