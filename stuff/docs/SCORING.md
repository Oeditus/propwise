# PropWise Scoring System

This document explains the criteria used to identify property-based testing candidates and how the testability score is calculated.

## Overview

PropWise analyzes functions based on three factors:
1. **Purity** - three-state classification: `:pure`, `:unknown`, or `:impure`
2. **Pattern Detection** - whether the function exhibits patterns suitable for property testing
3. **Law Inference** - which algebraic laws the functions it calls imply

Impure functions automatically receive a score of 0 and are never reported.

## Purity Analysis

### The three states

A binary pure/impure split forces every function that calls *any* other function
to be guessed at. PropWise distinguishes:

| State | Meaning | Score |
| --- | --- | --- |
| `:pure` | Every call in the body resolves to a known-pure function | full |
| `:unknown` | No side effect found, but some calls could not be resolved | half (rounded down, min 1) |
| `:impure` | A known side effect was found | 0 |

`:unknown` candidates are still reported — they are simply ranked below `:pure`
ones so that genuinely clean functions come first.

### What makes a function `:impure`?

A function is `:impure` if the AST contains any of the following.

#### Semantic operations (from Metastatic `op_kind`)

Any call annotated with a semantic domain of `:db`, `:http`, `:cache`, `:file`,
`:auth`, `:queue`, or `:external_api`.

#### I/O operations
- `File.*` - File system operations
- `IO.*` - Standard input/output
- `Logger.*` - Logging operations

#### Process operations
- `GenServer.*`, `Agent.*`, `Task.*`, `Process.*`
- `send/2`, `spawn/*`, `spawn_link/*`
- `receive` blocks

#### Database / HTTP / System
- `Ecto.Repo.*`, `Ecto.Query.*`
- `Req.*`
- `System.*`, `:ets.*`, `:dets.*`, `:mnesia.*`
- `Registry.*`, `DynamicSupervisor.*`, `Supervisor.*`

### What makes a function `:pure` vs `:unknown`?

A function is `:pure` only when **every** call in its body resolves to a
known-pure function. The built-in pure set covers `Enum`, `Map`, `List`,
`String`, `Integer`, `Float`, `Kernel`, `Tuple`, `Keyword`, `MapSet`, `Range`,
`Access`, `Stream`, `Base`, `Jason`, `URI`, `Version`, and the `:erlang`,
`:lists`, `:maps`, `:binary`, `:math`, `:string`, `:unicode` modules.

Any call that cannot be resolved — another module's function, or an
unqualified local call — makes the function `:unknown`, because a static
analyzer cannot know whether that call is pure.

### Declaring your own pure modules

Configure `pure_modules` to promote calls into modules you know are pure:

```elixir
# .propwise.exs
%{pure_modules: [MyApp.Math, MyApp.Parsing]}
```

A call into one of these no longer downgrades the caller to `:unknown`. Real
side effects elsewhere in the body still make it `:impure`.

## Law Inference

Pattern detection says "this is worth testing". The law table says **which
property to write**.

PropWise collects the call names in a function body and looks them up in
`PropWise.LawTable`, which maps ~60 known functions to the algebraic laws they
imply:

| Call | Inferred laws |
| --- | --- |
| `Map.merge` | idempotence, associativity, identity (`%{}`) |
| `Enum.reverse` | involution, length preservation, permutation |
| `Enum.sort` | idempotence, length preservation, permutation, monotonicity |
| `String.trim` | idempotence |
| `String.split` | round-trip |
| `abs` | idempotence, monotonicity |
| `Base.encode64` | round-trip |

Pattern-derived laws are merged in, so an `:algebraic` pattern always
contributes associativity, commutativity and identity regardless of the callee.

### Law vocabulary

| Law | Property |
| --- | --- |
| `:involution` | `f(f(x)) == x` |
| `:idempotent` | `f(f(x)) == f(x)` (unary) / `f(a, a) == a` (binary) |
| `:associative` | `f(f(a, b), c) == f(a, f(b, c))` |
| `:commutative` | `f(a, b) == f(b, a)` |
| `:identity` | `f(a, identity) == a` |
| `:permutation` | output is a permutation of input |
| `:length_preserving` | `length(f(x)) == length(x)` |
| `:monotonic` | `a <= b implies f(a) <= f(b)` |
| `:round_trip` | paired with the inverse function |
| `:total` | never raises for generated input |
| `:bounded` | output stays within a known range |
| `:deterministic` | `f(x) == f(x)` — the weakest law, used as a fallback |

## Score Calculation

For non-impure functions, the score is calculated as follows:

### Base Score
**1 point** - Just for being pure or unknown

### Pattern Score
**2 points per pattern detected**

### Multi-Pattern Bonus
**2 points** - If function has 2 or more detected patterns

### Complexity Bonus
**1 point** - If the function contains conditional logic (`case`, `cond`,
`with`, or `if`), OR the function body has more than 12 AST nodes

Note: the node count is measured on the MetaAST, not on a stringified body.
`Metastatic.to_string/1` joins block statements with `"; "`, so a newline count
would never register a multi-statement body.

### Visibility Bonus
**1 point** - If the function is public (`def` vs `defp`)

### Purity Weighting

The raw score above is then weighted by purity:

- `:pure` → the raw score, unchanged
- `:unknown` → `max(1, round(raw * 0.5))`

## Score Formula

```elixir
raw = base_score + pattern_score + multi_pattern_bonus + complexity_bonus + visibility_bonus

score =
  case purity do
    :impure  -> 0
    :pure    -> raw
    :unknown -> max(1, round(raw * 0.5))
  end
```

Where:
- `base_score = 1`
- `pattern_score = num_patterns * 2`
- `multi_pattern_bonus = num_patterns >= 2 ? 2 : 0`
- `complexity_bonus = is_complex? ? 1 : 0`
- `visibility_bonus = is_public? ? 1 : 0`


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
- Struct update syntax (`%Struct{...}`)
- Map update syntax (`%{map | key: val}`)
- Map write operations (`Map.put`, `Map.merge`, `Map.update`, etc.)

Note: Bare pipelines (`|>`) and `with` expressions are deliberately excluded since they are too common in idiomatic Elixir to be meaningful signals.

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

**Detection criteria (name-based conventions):**
- Function name ends with `?` (Elixir predicate convention)
- Function name starts with `valid` or contains `validate`
- Function name starts with `check`
- Function name starts with `is_`

Note: Detection relies on naming conventions rather than body analysis, since boolean expressions appear in nearly all non-trivial functions.

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
Function name contains one of these as an exact underscore-separated segment:
- `merge`
- `concat`
- `combine`
- `union`
- `intersect`
- `compose`
- `append`

Note: Segment matching means `merge_configs` matches (segment `merge`), but `submerge` does not.

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
Function name contains one of these as an exact underscore-separated segment:
- `encode` or `decode`
- `serialize` or `deserialize`

Or the full function name matches:
- `to_json`, `from_json`, `to_xml`, `from_xml`

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
- Function name contains `parse` as an exact underscore-separated segment
- Function body uses `Regex.run` or `Regex.scan`

Note: `Regex.match?/2` is deliberately **not** a parser signal — it is a
predicate. Likewise, a function whose name ends in `?` is never classified as a
parser; it is a validation concern. This prevents a function like
`valid_email?/1` from being labelled both `validation` and `parser`.
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

**Detection criteria (AST-based, not regex):**
- Uses `:math` module calls (e.g., `:math.sqrt/1`, `:math.pow/2`)
- Uses kernel numeric functions: `div`, `rem`, `abs`, `round`, `floor`, `ceil`, `trunc`
- Contains 2 or more binary arithmetic operator nodes (`+`, `-`, `*`, `/`) in the AST

Note: A single arithmetic operation (e.g., `x + 1`) is not flagged. This prevents incidental matches on pipe operators, function arrows, and other syntax that happen to contain these characters.

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

## Minimum Score Threshold

By default, PropWise only reports functions with a score of 4 or higher. This threshold can be adjusted:

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

## Ranking

Candidates are ranked (1-based) so the most actionable findings come first. The
sort order is:

1. **Inverse-pair members** — functions participating in a detected inverse pair
   (e.g. `encode`/`decode`) always rank above non-pair candidates, regardless of
   score, because round-trip properties are the highest-value tests.
2. **Higher score** — among candidates of the same pair-membership class.
3. **`:pure` before `:unknown`** — a function whose purity is certain is more
   trustworthy than one with unresolved calls, even at the same score.
4. **Public before private**.
5. A stable alphabetical tie-break (module, name, arity).

By default only the top 3 ranked candidates and top 3 inverse pairs are shown,
followed by a `… and N more` note. Use `--show-all` (CLI) or `show_all: true`
(library) to display every finding — still ranked.

## Limitations

### False Positives

PropWise may report functions that:
- Are classified `:unknown` because they call an unresolvable module — add the
  module to `pure_modules` to sharpen this
- Are detected by pattern matching but don't actually have testable properties
- Are too trivial to benefit from property testing despite matching patterns

### False Negatives

PropWise may miss functions that:
- Have testable properties but don't match any detection pattern
- Use macros or dynamically generated code
- Hide side effects in called functions (a call into an unresolved module is
  treated as `:unknown`, not `:impure`)

### Law inference

The law table recognises ~60 specific functions. It does not reason about
arbitrary code: a function that implements `merge` by hand rather than calling
`Map.merge` gets no inferred laws (though the `:algebraic` name pattern still
contributes associativity/commutativity/identity).

### Recommendations

Use PropWise as a discovery tool, not an absolute authority. Review suggestions
critically and apply judgment about which functions truly benefit from
property-based testing.
