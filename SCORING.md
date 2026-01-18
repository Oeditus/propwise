# PropWise Scoring System

This document explains the criteria used to identify property-based testing candidates and how the testability score is calculated.

## Overview

PropWise analyzes functions based on two primary factors:
1. **Purity** - Whether the function has side effects
2. **Pattern Detection** - Whether the function exhibits patterns suitable for property testing

Only pure functions (those without side effects) receive a score. Impure functions automatically receive a score of 0.

## Purity Analysis

### What Makes a Function Pure?

A function is considered pure if it:
- Does not perform I/O operations
- Does not interact with processes or concurrency primitives
- Does not modify external state
- Always returns the same output for the same input

### Side Effects Detected

PropWise walks the function's AST looking for the following side effects:

#### I/O Operations
- `File.*` - File system operations
- `IO.*` - Standard input/output
- `Logger.*` - Logging operations

#### Process Operations
- `GenServer.*` - GenServer calls
- `Agent.*` - Agent operations
- `Task.*` - Task spawning
- `Process.*` - Process management
- `send/2` - Message sending
- `spawn/*` - Process spawning
- `spawn_link/*` - Linked process spawning
- `receive` blocks - Message receiving

#### Database Operations
- `Ecto.Repo.*` - Database queries
- `Ecto.Query.*` - Query building with execution

#### HTTP Operations
- `HTTPoison.*` - HTTP requests
- `Tesla.*` - HTTP client operations
- `Req.*` - HTTP requests

#### System Operations
- `System.*` - System calls
- `:ets.*` - ETS table operations
- `:dets.*` - DETS operations
- `:mnesia.*` - Mnesia database operations

#### State Modification
- `put_in/2` - Nested data structure updates
- `update_in/2` - Nested data structure updates
- `get_and_update_in/2` - Nested data structure updates

### Result

If any side effects are detected, the function is marked as `{:impure, [side_effects]}` and receives a score of 0.

If no side effects are found, the function is marked as `{:pure, []}` and proceeds to pattern detection and scoring.

## Pattern Detection

PropWise detects seven types of patterns that indicate good property-based testing candidates:

### 1. Collection Operations

**Detection criteria:**
- Uses `Enum.*` functions (map, filter, sort, group, reduce, flat_map, chunk)
- Uses `Stream.*` functions (map, filter, chunk, take, drop)
- Contains pipeline operations with Enum (`|> Enum.`)
- Uses list comprehensions (`for ... <- ...`)

**Why property-testable:**
Collection operations often have invariants like:
- Size preservation or predictable size changes
- Element preservation
- Order properties
- Idempotence

**Example properties:**
- Output length equals input length (for map)
- All input elements present in output
- Sorting twice produces same result

### 2. Data Transformations

**Detection criteria:**
- Contains pipeline operations (`|>`)
- Contains `with` expressions
- Manipulates struct fields
- Manipulates map fields

**Why property-testable:**
Transformations should maintain certain invariants:
- Type preservation
- Structural consistency
- Round-trip properties
- Relationship between input and output

**Example properties:**
- Transformed data maintains required fields
- Nested transformations are associative
- Transformations preserve semantic meaning

### 3. Validation Functions

**Detection criteria:**
- Function name starts with "valid" or contains "validate"
- Function name starts with "check"
- Function returns a boolean value

**Why property-testable:**
Validators should be:
- Consistent (same input always gives same result)
- Boolean-typed
- Well-defined for edge cases

**Example properties:**
- Validation is deterministic
- Invalid input consistently rejected
- Edge cases handled correctly

### 4. Algebraic Structures

**Detection criteria:**
Function name contains:
- "merge"
- "concat"
- "combine"
- "union"
- "intersect"
- "compose"
- "append"
- "add"
- "multiply"

**Why property-testable:**
Algebraic operations often have mathematical properties:
- Associativity: `(a op b) op c == a op (b op c)`
- Commutativity: `a op b == b op a`
- Identity element: `a op identity == a`
- Inverse elements

**Example properties:**
- Merge is associative
- Union is commutative
- Empty list is identity for concatenation

### 5. Encoder/Decoder Functions

**Detection criteria:**
Function name contains:
- "encode" or "decode"
- "serialize" or "deserialize"
- "to_json" or "from_json"

**Why property-testable:**
Encoding/decoding should have:
- Round-trip properties: `decode(encode(x)) == x`
- Error handling for invalid input
- Type preservation

**Example properties:**
- Encode-decode round-trip preserves data
- Decoder handles malformed input gracefully
- Encoding is deterministic

### 6. Parser Functions

**Detection criteria:**
- Function name contains "parse"
- Function body uses `String.split`
- Function body uses `Regex.run` or `Regex.scan`

**Why property-testable:**
Parsers should:
- Have well-defined success/failure cases
- Support round-trip with formatter (if available)
- Handle edge cases and invalid input

**Example properties:**
- Parse-format round-trip preserves semantics
- Parser returns consistent structure
- Invalid input handled appropriately

### 7. Numeric Algorithms

**Detection criteria:**
- Uses numeric functions: `div`, `rem`, `abs`, `round`, `floor`, `ceil`, `sqrt`, `pow`
- Contains arithmetic operators: `+`, `-`, `*`, `/`

**Why property-testable:**
Numeric functions often have:
- Mathematical properties
- Boundary conditions
- Special values (zero, negatives, infinity)
- Precision requirements

**Example properties:**
- Function handles boundary values correctly
- Special numeric values processed appropriately
- Numeric relationships maintained

## Score Calculation

For pure functions, the score is calculated as follows:

### Base Score
**1 point** - Just for being pure

### Pattern Score
**2 points per pattern detected**

If a function matches multiple pattern types, each adds 2 points.

### Multi-Pattern Bonus
**2 points** - If function has 2 or more detected patterns

Functions that match multiple patterns tend to be especially good candidates for property testing.

### Complexity Bonus
**1 point** - If the function is non-trivial

A function is considered non-trivial if:
- The function body has more than 3 lines when converted to string, OR
- The function contains conditional logic (`case`, `cond`, or `with` expressions)

Simple one-line functions are less interesting for property testing.

### Visibility Bonus
**1 point** - If the function is public (`def` vs `defp`)

Public functions are the API surface and generally more important to test thoroughly.

## Score Formula

```elixir
score = base_score + pattern_score + multi_pattern_bonus + complexity_bonus + visibility_bonus
```

Where:
- `base_score = 1` (for pure functions)
- `pattern_score = num_patterns * 2`
- `multi_pattern_bonus = num_patterns >= 2 ? 2 : 0`
- `complexity_bonus = is_complex? ? 1 : 0`
- `visibility_bonus = is_public? ? 1 : 0`

## Examples

### Example 1: Simple Pure Function
```elixir
defp double(x), do: x * 2
```
- Pure: ✓ (base = 1)
- Patterns: Numeric (2)
- Multi-pattern bonus: 0
- Complexity: 0 (too simple)
- Visibility: 0 (private)
- **Total: 3**

### Example 2: Complex Public Transformation
```elixir
def transform_users(users) do
  users
  |> Enum.map(&normalize_user/1)
  |> Enum.filter(&valid_email?/1)
  |> Enum.sort_by(& &1.name)
end
```
- Pure: ✓ (base = 1)
- Patterns: Collection (2), Transformation (2), Validation (2)
- Multi-pattern bonus: 2
- Complexity: 1 (multiple lines)
- Visibility: 1 (public)
- **Total: 11**

### Example 3: Round-trip Functions
```elixir
def encode_json(data), do: Jason.encode!(data)
def decode_json(json), do: Jason.decode!(json)
```
- Pure: ✓ (base = 1 each)
- Patterns: Encoder/Decoder (2 each)
- Multi-pattern bonus: 0 (only one pattern)
- Complexity: 0 (simple)
- Visibility: 1 (public)
- **Total: 4 each**
- **Plus**: Detected as inverse pair!

### Example 4: Impure Function
```elixir
def save_to_file(data, path) do
  File.write!(path, data)
end
```
- Pure: ✗ (has side effect: File.write!)
- **Total: 0** (impure functions always score 0)

## Minimum Score Threshold

By default, PropWise only reports functions with a score of 3 or higher. This threshold can be adjusted:

```bash
mix propwise --min-score 5
./propwise --min-score 5 .
```

## Inverse Function Pairs

In addition to scoring individual functions, PropWise detects inverse function pairs:
- encode/decode
- serialize/deserialize
- parse/format or parse/generate
- compress/decompress
- encrypt/decrypt
- to_*/from_*
- pack/unpack
- marshal/unmarshal

These pairs are reported separately with suggestions to test round-trip properties.

## Limitations

### False Positives

PropWise may report functions that:
- Call other module functions that have side effects (can't determine purity of external calls)
- Are detected by pattern matching but don't actually have testable properties
- Are too trivial to benefit from property testing despite matching patterns

### False Negatives

PropWise may miss functions that:
- Have testable properties but don't match any detection patterns
- Use macros or dynamically generated code
- Hide side effects in called functions

### Recommendations

Use PropWise as a discovery tool, not an absolute authority. Review suggestions critically and apply judgment about which functions truly benefit from property-based testing.
