# PropWise

An AST-based analyzer for identifying property-based testing candidates in Elixir codebases.

## Overview

PropWise analyzes your Elixir code to find functions that would benefit from property-based testing. It examines the Abstract Syntax Tree (AST) of your code to:

- Detect pure functions (functions without side effects)
- Identify common patterns suitable for property testing
- Find inverse function pairs (encode/decode, serialize/deserialize, etc.)
- Score and rank candidates by testability
- Provide specific testing suggestions for each candidate
- Rank findings meaningfully (inverse pairs first) and show only the top 3 by
  default, with `--show-all` to expand

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
- **Data Transformations**: Struct update and map write operations
- **Validation Functions**: Functions following naming conventions (`?` suffix, `valid`/`check`/`is_` prefix)
- **Algebraic Structures**: Merge, concat, union, compose, and other potentially algebraic operations
- **Encoders/Decoders**: Serialization and encoding/decoding functions
- **Numeric Algorithms**: `:math` module calls, kernel numeric functions, and significant arithmetic (2+ operations)

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
Generates ready-to-use property-based test code:
- Supports multiple libraries: `stream_data` (default) and `PropEr`
- Specific test properties tailored to detected patterns
- Complete test blocks with appropriate generators
- Assertions matching the function's expected behavior
- Copy-paste ready test code to get started quickly

## Installation

### As a Library

Add `propwise` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:propwise, "~> 0.2"}
  ]
end
```

### As a Command-Line Tool

#### Option 1: escript (Recommended for standalone use)

Build and install the standalone executable:

```bash
cd propwise
mix deps.get
mix escript.build

# Copy to a directory in your PATH
sudo cp propwise /usr/local/bin/
# Or just use it directly
./propwise
```

The escript bundles all dependencies and works without Mix or any additional setup.

#### Option 2: Mix archive

Install globally from Hex as a Mix archive:

```bash
mix archive.install hex propwise
```

This makes the `mix propwise` task available in any project. Note: This requires `jason` to be available in your Mix environment.

To uninstall:

```bash
mix archive.uninstall propwise
```

#### Option 3: As a dependency

When added as a project dependency, PropWise provides a Mix task:

```bash
mix propwise
```

## Usage

### Command Line

#### Using escript

```bash
# Analyze current project
./propwise .

# Analyze with custom minimum score
./propwise --min-score 5 ./my_project

# Output as JSON
./propwise --format json ./my_project

# Use PropEr instead of stream_data
./propwise --library proper ./my_project

# Show all findings instead of just the top 3
./propwise --show-all ./my_project

# Show help
./propwise --help
```

#### Using Mix task

```bash
# Analyze current project
mix propwise

# Analyze with custom minimum score
mix propwise --min-score 5

# Output as JSON
mix propwise --format json

# Use PropEr instead of stream_data
mix propwise --library proper

# Show all findings instead of just the top 3
mix propwise --show-all

# Analyze another project
mix propwise ../other_project

# Show help
mix propwise --help
```

### As a Library

```elixir
# Analyze a project
result = PropWise.analyze("./my_project")

# Analyze with custom options
result = PropWise.analyze("./my_project", min_score: 5, library: :proper)

# Print the report
PropWise.print_report(result)

# Print as JSON
PropWise.print_report(result, format: :json)
```

### Analyzing a Subset of Files (for Pull Requests)

PropWise supports analyzing specific files or file subsets. This is ideal for PR workflows to focus analysis only on modified or newly added code.

1. **Single File**:
   ```bash
   mix propwise lib/my_app/user.ex
   # or
   ./propwise lib/my_app/user.ex
   ```

2. **Comma-Separated File List (`--files` flag)**:
   ```bash
   mix propwise --files "lib/my_app/user.ex,lib/my_app/auth.ex"
   ```

3. **Multiple File Path Arguments**:
   ```bash
   mix propwise lib/my_app/user.ex lib/my_app/auth.ex
   ```

### CI / PR Integration

You can easily integrate PropWise into your CI pipeline to run property testing candidate detection on Pull Requests:

#### Bash / CI Pipeline Script

```bash
# Get modified or added .ex files relative to main branch
CHANGED_FILES=$(git diff --name-only origin/main...HEAD | grep '\.ex$' | paste -sd,)

if [ -n "$CHANGED_FILES" ]; then
  mix propwise --no-fail --files "$CHANGED_FILES"
else
  echo "No Elixir files modified in this PR."
fi
```

#### GitHub Actions Example (`.github/workflows/propwise.yml`)

```yaml
name: PropWise PR Analysis

on:
  pull_request:
    branches: [ main ]

jobs:
  analyze-pr:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - uses: erlef/setup-beam@v1
        with:
          elixir-version: '1.18'
          otp-version: '27'

      - run: mix deps.get

      - name: Run PropWise on PR Changed Files
        run: |
          CHANGED_FILES=$(git diff --name-only origin/main...HEAD | grep '\.ex$' | paste -sd,)
          if [ -n "$CHANGED_FILES" ]; then
            mix propwise --no-fail --files "$CHANGED_FILES"
          else
            echo "No Elixir files modified in this PR."
          fi
```

## Example Output

By default, PropWise shows the top 3 ranked candidates and inverse pairs, then a
`… and N more` note. Pass `--show-all` to see everything.

```
PropWise Analysis Report

Summary
  ▸ Total functions analyzed: 143
  ▸ Property test candidates: 24
  ▸ Candidates dropped (below threshold): 12
  ▸ Coverage: 16.8%

Inverse Function Pairs Detected

  1. `MyApp.Encoder.encode/1` <-> `decode/1`
    - Suggestion: Test round-trip property: decode(encode(x)) == x

Candidates (ranked)

1. MyApp.Encoder.encode/1
  ▸ Rank: #1
  ▸ Score: 4
  ▸ Location: lib/my_app/encoder.ex:12
  ▸ Type: public
  ▸ Patterns:
      ▸ Encoder/Decoder: Encoding/decoding function
  ▸ Testing suggestions:
      property "encode/decode round-trip" do
        check all(data <- term()) do
          encoded = Encoder.encode(data)
          assert Encoder.decode(encoded) == {:ok, data}
        end
      end

2. MyApp.Encoder.decode/1
  ▸ Rank: #2
  ▸ Score: 4
  ▸ Location: lib/my_app/encoder.ex:18
  ▸ Type: public
  ▸ Patterns:
      ▸ Encoder/Decoder: Encoding/decoding function
  ▸ Testing suggestions:
      ...

3. MyApp.List.merge_sorted/2
  ▸ Rank: #3
  ▸ Score: 8
  ▸ Location: lib/my_app/list.ex:15
  ▸ Type: public
  ▸ Patterns:
      ▸ Collection Operation: Uses Enum collection operations
      ▸ Algebraic Structure: Potentially algebraic operation
  ▸ Testing suggestions:
      ...

… and 21 more (run with `--show-all` to see all findings).
```

> Note how `encode`/`decode` rank above `merge_sorted` even though they have a
> lower score: inverse-pair members are the most actionable findings, so they are
> always ranked first.

## Scoring System

Functions are scored based on multiple factors:

- **Base score**: 1 point for pure functions
- **Pattern detection**: 2 points per detected pattern
- **Multiple patterns**: 2 bonus points for functions with 2+ patterns
- **Complexity**: 1 bonus point for non-trivial functions
- **Visibility**: 1 bonus point for public functions

Default minimum score is 4, but this can be adjusted based on your needs.

**For detailed information about all detection criteria and scoring rules, see [Scoring](stuff/docs/SCORING.md).**

## Configuration

You can customize PropWise's behavior by creating a `.propwise.exs` file in your project root.

### Example Configuration

```elixir
# .propwise.exs
%{
  # Directories to analyze (relative to project root)
  # Default: ["lib"]
  analyze_paths: ["lib"],

  # Property-based testing library to use for suggestions
  # Options: :stream_data (default) or :proper
  library: :stream_data

  # You can analyze multiple directories:
  # analyze_paths: ["lib", "src", "apps/my_app/lib"]
}
```

### Configuration Options

- `analyze_paths` - List of directories to analyze relative to project root (default: `["lib"]`)
- `library` - Property testing library for code generation: `:stream_data` or `:proper` (default: `:stream_data`)

If no `.propwise.exs` file is present, PropWise will use the defaults.

## Options

### CLI Options

- `-m, --min-score NUM`: Minimum score for candidates (default: 4)
- `-f, --format FORMAT`: Output format: text or json (default: text)
- `-o, --output FILE`: Write output to file instead of stdout
- `-l, --library LIB`: Property testing library: stream_data or proper (default: stream_data)
- `--show-all`: Show all findings instead of just the top 3 (still ranked)
- `--no-fail`: Exit with code 0 even when suggestions are found
- `-h, --help`: Show help message

Note: CLI options override configuration file settings.

### Library Options

- `:min_score` - Minimum score threshold (integer, default: 4)
- `:format` - Output format (`:text` or `:json`, default: `:text`)
- `:library` - Property testing library (`:stream_data` or `:proper`, default: `:stream_data`)
- `:show_all` - Show all findings instead of the top 3 (boolean, default: `false`)
- `:limit` - Override the default display limit of 3 (integer; ignored when `:show_all` is `true`)

## Ranking and Output Volume

PropWise reports can be noisy on larger codebases. To keep them actionable, findings are
**ranked** and **truncated by default**:

- Every candidate is assigned a 1-based **rank** (shown as `Rank: #N` and as a heading prefix).
- Ranking prioritizes, in order:
  1. **Inverse-pair members** (e.g. `encode`/`decode`) — round-trip properties are the
     highest-value tests, so these always rank above other candidates regardless of score.
  2. Higher **score**.
  3. **Public** functions before private ones.
  4. A stable alphabetical tie-break.
- By default only the **top 3** candidates and **top 3** inverse pairs are shown, each
  followed by a `… and N more` note.
- Pass `--show-all` to display **every** finding (still ranked).

```bash
# Default: top 3 findings only
mix propwise

# Show every finding, still ranked
mix propwise --show-all
```

## How It Works

1. **Parse**: Recursively finds all `.ex` files in configured directories (default: `lib`)
2. **Extract**: Parses each file's AST and extracts function definitions
3. **Analyze Purity**: Walks the AST to detect side effects
4. **Detect Patterns**: Looks for common patterns in function structure and naming
5. **Score**: Calculates a testability score for each function
6. **Find Pairs**: Identifies inverse function pairs across the codebase
7. **Generate Suggestions**: Creates concrete property-based test examples using your chosen library
8. **Report**: Presents findings with ready-to-use test code

## Limitations

- Static analysis only - doesn't execute code
- May produce false positives for functions that call other module functions (can't determine if those are pure)
- Pattern detection is heuristic-based
- Doesn't analyze macros or dynamically generated code in depth

## Security Note

PropWise loads configuration from `.propwise.exs` files using `Code.eval_file/1`,
which executes arbitrary Elixir code. Only analyze projects you trust.

## Contributing

Contributions are welcome! Areas for improvement:

- Additional pattern detectors
- Smarter purity analysis (tracking function calls across modules)
- Integration with existing property testing libraries
- IDE integration

## License

MIT

