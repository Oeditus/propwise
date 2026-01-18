# PropWise

An AST-based analyzer for identifying property-based testing candidates in Elixir codebases.

## Overview

PropWise analyzes your Elixir code to find functions that would benefit from property-based testing. It examines the Abstract Syntax Tree (AST) of your code to:

- Detect pure functions (functions without side effects)
- Identify common patterns suitable for property testing
- Find inverse function pairs (encode/decode, serialize/deserialize, etc.)
- Score and rank candidates by testability
- Provide specific testing suggestions for each candidate

## Features

### Purity Analysis
Detects side effects by analyzing function calls:
- I/O operations (File, IO)
- Process operations (GenServer, Agent, Task)
- Database operations (Ecto)
- HTTP requests
- System calls
- Message passing

### Pattern Detection
Identifies functions with characteristics ideal for property testing:
- **Collection Operations**: Functions using Enum, Stream, or list comprehensions
- **Data Transformations**: Pipeline operations, struct/map manipulation
- **Validation Functions**: Boolean predicates and validation logic
- **Algebraic Structures**: Merge, concat, union, and other potentially algebraic operations
- **Encoders/Decoders**: Serialization and parsing functions
- **Numeric Algorithms**: Arithmetic and mathematical operations

### Inverse Pair Detection
Finds function pairs that are inverses of each other:
- encode/decode
- serialize/deserialize
- parse/format or parse/generate
- compress/decompress
- encrypt/decrypt
- to_*/from_*
- pack/unpack
- marshal/unmarshal

### Concrete Test Generation
Generates ready-to-use property-based test code using `stream_data`:
- Specific test properties tailored to detected patterns
- Complete `check all` blocks with appropriate generators
- Assertions matching the function's expected behavior
- Copy-paste ready test code to get started quickly

## Installation

### As a Library

Add `propwise` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:propwise, "~> 0.1.0"}
  ]
end
```

### As a Command-Line Tool

```bash
cd propwise
mix deps.get
mix escript.build
```

This creates an executable `propwise` in the project directory.

## Usage

### Command Line

```bash
# Analyze current project
./propwise .

# Analyze with custom minimum score
./propwise --min-score 5 ./my_project

# Output as JSON
./propwise --format json ./my_project

# Show help
./propwise --help
```

### As a Library

```elixir
# Analyze a project
result = PropWise.analyze("./my_project")

# Analyze with custom options
result = PropWise.analyze("./my_project", min_score: 5)

# Print the report
PropWise.print_report(result)

# Print as JSON
PropWise.print_report(result, format: :json)
```

## Example Output

```
================================================================================
PropWise Analysis Report
================================================================================

Summary:
  Total functions analyzed: 143
  Property test candidates: 24
  Coverage: 16.8%

--------------------------------------------------------------------------------
Inverse Function Pairs Detected:
--------------------------------------------------------------------------------

  MyApp.Encoder.encode/1 <-> decode/1
  Suggestion: Test round-trip property: decode(encode(x)) == x

--------------------------------------------------------------------------------
Top Candidates (sorted by score):
--------------------------------------------------------------------------------

MyApp.Parser.parse_json/1
  Score: 8
  Location: lib/my_app/parser.ex:42
  Type: public
  Patterns:
    - Parser: Parser function
    - Data Transformation: Pipeline transformation
  Testing suggestions:
    - property "parse returns expected structure" do
  check all input <- string(:alphanumeric) do
    case Parser.parse_json(input) do
      {:ok, result} -> assert valid_parsed_structure?(result)
      {:error, _} -> true
    end
  end
end

    - property "parse/format round-trip" do
  check all data <- valid_data_generator() do
    formatted = Parser.format(data)
    assert Parser.parse_json(formatted) == {:ok, data}
  end
end

    - property "maintains structural invariants" do
  check all input <- term() do
    result = Parser.parse_json(input)
    # Add your invariant checks here
    assert valid_structure?(result)
  end
end

MyApp.List.merge_sorted/2
  Score: 7
  Location: lib/my_app/list.ex:15
  Type: public
  Patterns:
    - Collection Operation: Uses Enum collection operations
    - Algebraic Structure: Potentially algebraic operation
  Testing suggestions:
    - property "preserves input size" do
  check all list <- list_of(term()) do
    assert length(List.merge_sorted(list)) == length(list)
  end
end

    - property "associativity" do
  check all a <- term(), b <- term(), c <- term() do
    assert List.merge_sorted(List.merge_sorted(a, b), c) ==
           List.merge_sorted(a, List.merge_sorted(b, c))
  end
end
```

## Scoring System

Functions are scored based on multiple factors:

- **Base score**: 1 point for pure functions
- **Pattern detection**: 2 points per detected pattern
- **Multiple patterns**: 2 bonus points for functions with 2+ patterns
- **Complexity**: 1 bonus point for non-trivial functions
- **Visibility**: 1 bonus point for public functions

Default minimum score is 3, but this can be adjusted based on your needs.

## Configuration

You can customize PropWise's behavior by creating a `.propwise.exs` file in your project root.

### Example Configuration

```elixir
# .propwise.exs
%{
  # Directories to analyze (relative to project root)
  # Default: ["lib"]
  analyze_paths: ["lib"]

  # You can analyze multiple directories:
  # analyze_paths: ["lib", "src", "apps/my_app/lib"]
}
```

### Configuration Options

- `analyze_paths` - List of directories to analyze relative to project root (default: `["lib"]`)

If no `.propwise.exs` file is present, PropWise will analyze only the `lib` directory by default.

## Options

### CLI Options

- `-m, --min-score NUM`: Minimum score for candidates (default: 3)
- `-f, --format FORMAT`: Output format: text or json (default: text)
- `-h, --help`: Show help message

### Library Options

- `:min_score` - Minimum score threshold (integer, default: 3)
- `:format` - Output format (`:text` or `:json`, default: `:text`)

## How It Works

1. **Parse**: Recursively finds all `.ex` files in configured directories (default: `lib`)
2. **Extract**: Parses each file's AST and extracts function definitions
3. **Analyze Purity**: Walks the AST to detect side effects
4. **Detect Patterns**: Looks for common patterns in function structure and naming
5. **Score**: Calculates a testability score for each function
6. **Find Pairs**: Identifies inverse function pairs across the codebase
7. **Generate Suggestions**: Creates concrete property-based test examples using `stream_data`
8. **Report**: Presents findings with ready-to-use test code

## Limitations

- Static analysis only - doesn't execute code
- May produce false positives for functions that call other module functions (can't determine if those are pure)
- Pattern detection is heuristic-based
- Doesn't analyze macros or dynamically generated code in depth

## Contributing

Contributions are welcome! Areas for improvement:

- Additional pattern detectors
- Smarter purity analysis (tracking function calls across modules)
- Integration with existing property testing libraries
- Configuration file support
- IDE integration

## License

MIT

