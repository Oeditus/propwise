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

### Property-based tests

PropWise dogfoods its own advice: `test/prop_wise/property_test.exs` uses
`stream_data` (a `only: :test` dependency) to check invariants of
`find_inverse_pairs/1` and `detect_patterns/1`.

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

The codebase follows a pipeline architecture with 12 modules:

1. **PropWise.Config** (`lib/prop_wise/config.ex`)
   - Loads configuration from `.propwise.exs` file
   - Provides defaults if no config file exists
   - Handles both map and keyword list configurations
   - Main function: `analyze_paths/1` returns directories to analyze

2. **PropWise.Parser** (`lib/prop_wise/parser.ex`)
   - Entry point for AST extraction
   - Recursively finds `.ex` files in the `lib` directory only (does not analyze test files or dependencies)
   - Parses files into ASTs and extracts function definitions with metadata (name, arity, module, args, body, location, visibility)
   - Returns list of `PropWise.FunctionInfo` structs
   - Accepts `analyze_paths` option to avoid re-loading config

3. **PropWise.PurityAnalyzer** (`lib/prop_wise/purity_analyzer.ex`)
   - Classifies functions into **three** states: `:pure`, `:unknown`, `:impure`
     - `:pure` — every call resolves to a known-pure function
     - `:unknown` — no side effect found, but some calls could not be resolved
     - `:impure` — a known side effect was found
   - Impure triggers: semantic `op_kind` domains (db/http/cache/file/auth/queue/
     external_api), `File`/`IO`/`Logger`, `GenServer`/`Agent`/`Task`/`Process`,
     `Ecto`/`Req`/`System`/`:ets`/`:dets`/`:mnesia`, `send`/`spawn`, `receive`
   - A call into a module in the built-in pure set (`Enum`, `Map`, `String`,
     `:erlang`, `:math`, …) or a user-configured `pure_modules` entry resolves
     to pure; anything else is unresolved and makes the function `:unknown`
   - `analyze/2` returns `%{purity:, side_effects:, unresolved_calls:}`;
     `classify/2` returns the atom; `pure?/2` is true only for `:pure`
   - Guards against a Metastatic quirk: a piped call into a dotted module
     (`x |> MyApp.f()`) carries a mangled name and must not resolve as pure

4. **PropWise.LawTable** (`lib/prop_wise/law_table.ex`)
   - Static, documented table mapping ~60 known call names to algebraic laws
     (`Map.merge` → idempotence/associativity/identity, `Enum.reverse` →
     involution, …)
   - `laws_for_call/1`, `laws_for_calls/1`, `identity_for/1`, `known_calls/0`
   - Adding an entry is a one-line change to `@table`; the first match wins
   - Matching is exact, with tolerance for a leading `:` (source writes
     `:math.sqrt`, MetaAST records `math.sqrt`)

5. **PropWise.PatternDetector** (`lib/prop_wise/pattern_detector.ex`)
   - Identifies patterns suitable for property testing:
     - Collection operations (Enum, Stream, comprehensions)
     - Data transformations (struct/map manipulation only, not bare pipelines)
     - Validation functions (name-based: `?` suffix, `valid`/`check`/`is_` prefix)
     - Algebraic structures (merge, concat, union, compose)
     - Encoders/decoders (encode/decode, serialize/deserialize)
     - Parsers (name segment `parse`, or `Regex.run`/`Regex.scan` — note
       `Regex.match?` is a predicate, not a parser, and `?`-suffixed functions
       are never classified as parsers)
     - Numeric algorithms (AST-based detection: :math calls, kernel numeric fns, 2+ arithmetic ops)
   - Detectors live in a registry (`detectors/0`); adding a pattern is a one-line
     change. Each detector receives a single context struct
     (`%{info:, meta_ast:, body_string:}`) and returns a reason string or `nil`.
   - `body_string` is computed lazily — most detectors never need it.
   - `find_inverse_pairs/1` uses a `{module, name}` index (O(n), not O(n²·9))
     and de-duplicates results; pairs never cross module boundaries.

5. **PropWise.LawTable** (`lib/prop_wise/law_table.ex`)
   - Static, extensible lookup table mapping known calls to algebraic laws
   - `Map.merge/2` → `[:idempotent, :associative, :commutative, :identity]`
   - Also maps function-name segments (`merge`, `concat`, `union`, …) to laws
   - Laws are ordered by *value to a property tester*, strongest first
   - Public API: `laws_for_calls/1`, `laws_for_name/1`, `identity_for/1`, `all/0`
   - Adding a law for a new function is a one-line change

6. **PropWise.Analyzer** (`lib/prop_wise/analyzer.ex`)
   - Orchestrates the analysis pipeline
   - Combines three-state purity, pattern detection, and law inference
   - Calculates testability scores based on:
     - Base score: 1 for `:pure` functions
     - Pattern score: 2 points per detected pattern
     - Multi-pattern bonus: 2 points for functions with 2+ patterns
     - Complexity bonus: 1 point for non-trivial functions (conditional logic,
       or more than 12 AST nodes — *not* a line count; `Metastatic.to_string/1`
       joins statements with `"; "` so newlines are meaningless there)
     - Visibility bonus: 1 point for public functions
   - **Purity weighting**: `:unknown` functions score at half weight
     (`@unknown_weight`), so they still surface but rank below `:pure` ones;
     `:impure` functions score 0
   - Infers laws per candidate via `PropWise.LawTable` and threads the concrete
     identity value (e.g. `%{}` for `Map.merge`) into the suggestion generator
   - Loads config once and threads through to Parser
   - Filters by minimum score (default: 4)
   - Ranks candidates: inverse-pair members first, then by score, then public-before-private,
     then a stable alphabetical tie-break; assigns a 1-based `rank` and an `inverse_pair` flag
   - Returns ranked list of `PropWise.Candidate` structs plus `purity_counts`

7. **PropWise.SuggestionGenerator** (`lib/prop_wise/suggestion_generator.ex`)
   - Generates library-specific property test suggestions
   - Supports multiple libraries:
     - `stream_data`: Uses `check all` syntax with generators like `list_of`, `one_of`
     - `PropEr`: Uses `forall` syntax with generators like `list`, `oneof`
   - **Law-driven** suggestions take precedence over generic pattern templates:
     each inferred law renders a concrete, compilable property
     (`associativity`, `commutativity`, `idempotence`, `identity element`,
     `round-trip`, `involution`, `length preservation`, `permutation`, `totality`)
   - Law renderers are arity-aware: idempotence is `f(f(x)) == f(x)` for arity 1
     and `f(a, a) == a` for arity 2
   - Emits the *full* module name so generated calls resolve without an alias
   - Builds call sites structurally (never by string-patching)

8. **PropWise.Baseline** (`lib/prop_wise/baseline.ex`)
   - CI ratcheting: persists accepted candidates to a JSON baseline
   - `write/2` stores `{module, name, arity}` + score for each candidate
   - `read/1` returns `{:ok, baseline}` / `{:error, reason}`
   - `diff/2` partitions current candidates into `:new` (regressions) and
     `:accepted` (pre-existing), so CI fails only on *new* findings

9. **PropWise.Reporter** (`lib/prop_wise/reporter.ex`)
   - Formats analysis results for output
   - Supports text, markdown, and JSON formats
   - Displays candidates ranked, showing `Rank: #N`, `Purity:`, `Inferred laws:`,
     and `Unresolved calls:`
   - Renders ANSI colour with a small built-in Markdown renderer (no external
     Markdown dependency); honours `NO_COLOR`
   - Shows only the top 3 candidates and top 3 inverse pairs by default, with a
     `… and N more` note; `show_all: true` (CLI `--show-all`) displays every finding

10. **PropWise.CommandLine** (`lib/prop_wise/command_line.ex`)
    - Shared argument parsing and analysis logic for CLI and Mix task
    - Eliminates duplication between escript and Mix entry points
    - Handles `--baseline` / `--write-baseline` ratcheting

9. **PropWise.CLI** (`lib/prop_wise/cli.ex`)
   - Thin escript entry point wrapper around CommandLine

10. **Mix.Tasks.Propwise** (`lib/mix/tasks/propwise.ex`)
    - Thin Mix task wrapper around CommandLine

11. **PropWise.FunctionInfo** (`lib/prop_wise/function_info.ex`)
    - Struct with enforced keys for parsed function metadata

12. **PropWise.Candidate** (`lib/prop_wise/candidate.ex`)
    - Struct with enforced keys for scored analysis results
    - `purity` is one of the three atoms `:pure`, `:unknown`, `:impure`
    - Carries `laws` (inferred algebraic laws) and `unresolved_calls`

### Data Flow

```
Project Path
    ↓
Parser: Extract all functions from .ex files
    ↓
Analyzer: For each function:
    ├─ PurityAnalyzer: Classify as :pure / :unknown / :impure
    ├─ PatternDetector: Identify testing patterns
    ├─ LawTable: Infer algebraic laws from called functions
    └─ Score: Calculate testability score (purity-weighted)
    ↓
PatternDetector: Find inverse function pairs across all functions
    ↓
Baseline (optional): Suppress previously accepted candidates
    ↓
Reporter: Format and display results
```

### Key Data Structures

**Function Metadata** (`PropWise.FunctionInfo` struct):
```elixir
%PropWise.FunctionInfo{
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

**Candidate Result** (`PropWise.Candidate` struct):
```elixir
%PropWise.Candidate{
  module: "ModuleName",
  name: :function_name,
  arity: 2,
  file: "path/to/file.ex",
  line: 42,
  type: :public | :private,
  purity: :pure | :unknown | :impure,
  side_effects: [effects],
  unresolved_calls: ["SomeModule.some_fn"],
  patterns: [{:collection_operation, "reason"}, ...],
  laws: [:associative, :commutative],
  score: integer,
  rank: integer,
  inverse_pair: boolean,
  suggestions: ["Test property X", ...]
}
```

## Configuration

PropWise supports configuration via a `.propwise.exs` file in the project root:

```elixir
%{
  analyze_paths: ["lib"],      # Directories to analyze (default: ["lib"])
  library: :stream_data,        # :stream_data or :proper (default: :stream_data)
  pure_modules: [MyApp.Math]    # Extra modules treated as pure (optional)
}
```

The `PropWise.Config` module handles loading and parsing this configuration. Configuration
problems are reported through the `:on_error` callback rather than silently swallowed.

## Testing Patterns

The project uses ExUnit. Key patterns:
- Tests use temporary directories created with `System.unique_integer([:positive])` for isolated file operations
- Cleanup happens with `File.rm_rf!/1` after tests
- Pattern matching used to assert on list sizes: `assert [_, _] = list` (preferred over `assert length(list) == 2`)
- Tests are marked `async: true` where possible for parallel execution
