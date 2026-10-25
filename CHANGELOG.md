# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

#### Three-state purity
- Purity is now classified as `:pure`, `:unknown` or `:impure` instead of a
  binary pure/impure split.
  - `:pure` — every call in the body resolves to a known-pure function.
  - `:unknown` — no side effect was found, but some calls could not be resolved
    (another module's function, an unqualified local call).
  - `:impure` — a known side effect was found.
- `:unknown` candidates are still reported but scored at half weight
  (`PropWise.Analyzer`'s `@unknown_weight`) and ranked below `:pure` ones, so
  genuinely clean functions come first.
- New `:pure_modules` configuration option (and `.propwise.exs` key) listing
  modules whose functions are known to be pure. A call into one of them does
  not downgrade the caller to `:unknown`.
- `PropWise.PurityAnalyzer.analyze/2` now returns a map
  (`%{purity:, side_effects:, unresolved_calls:}`); `classify/2` returns the
  atom directly and `pure?/2` is true only for `:pure`.
- Reports show the purity of each candidate, the purity breakdown in the
  summary, and — for `:unknown` functions — *which* calls could not be resolved.

#### Law-table inference
- New `PropWise.LawTable` maps known functions to the algebraic laws they imply
  (`Map.merge` → associativity, idempotence, identity; `Enum.reverse` →
  involution; `Enum.sort` → idempotence, permutation, monotonicity; and ~60
  more).
- The analyzer collects the call names in a function body and infers laws from
  them, merging in pattern-derived laws (an `:algebraic` pattern always
  contributes associativity/commutativity/identity).
- `PropWise.SuggestionGenerator` renders inferred laws as real properties —
  `merge(merge(a, b), c) == merge(a, merge(b, c))` — instead of the generic
  "deterministic output" fallback. Idempotence is rendered arity-appropriately
  (`f(f(x)) == f(x)` for unary, `f(a, a) == a` for binary).
- Concrete identity elements are rendered where the table knows one
  (`Map.merge` → `%{}`, `Enum.sum` → `0`, `Enum.concat` → `[]`).

#### Baseline CI ratcheting
- New `PropWise.Baseline` module and `--baseline FILE` /
  `--write-baseline FILE` CLI flags.
- `--write-baseline` snapshots the current candidates to JSON and exits.
- `--baseline` reports only candidates that are new or whose score increased,
  suppressing previously accepted ones. Exit code is non-zero only on
  regressions, so PropWise can be enforced in CI as a ratchet.
- A malformed or unreadable baseline is a hard error rather than a silent empty
  baseline (which would make every existing candidate look new).

### Fixed
- JSON output no longer crashes on `side_effects` tuples (`Jason.Encoder` is not
  implemented for tuples); side effects are serialised to plain maps.
- A piped call into a dotted module (`x |> MyApp.f()`) is no longer treated as
  pure. Metastatic renders such calls with a mangled name, which previously
  resolved against the wrong entry in the side-effect table.
- `Regex.match?/2` no longer marks a function as a parser — it is a predicate,
  not a parser. `?`-suffixed functions are now classified as validation only.
- `compress`/`decompress` inverse-pair mapping no longer maps `compress` to
  itself, so round-trip suggestions are correct.
- Suggestion generator now emits the **full** module name
  (`MyApp.Deep.Nested.Encoder.encode/1`) instead of truncating to the last
  segment, so generated snippets resolve without an extra `alias`.
- Suggestion generator builds call sites structurally instead of patching them
  with a regex; multi-argument and zero-arity calls are no longer mangled.
- The complexity bonus now counts AST nodes instead of newlines in a
  stringified body. `Metastatic.to_string/1` joins statements with `"; "`, so
  the previous line-count heuristic never fired.
- `.propwise.exs` errors are surfaced through an `:on_error` callback instead of
  being silently swallowed, which previously produced a confusing empty report.
- Removed the `marcli` dependency (and its Rust NIF) entirely: the text report
  is rendered by a small built-in ANSI renderer, so the project builds without a
  Rust toolchain and without downloading precompiled NIFs.

### Changed
- `find_inverse_pairs/1` uses a `{module, name}` index instead of an O(n² · 9)
  nested loop, and de-duplicates results.
- `PatternDetector` uses a detector registry, so adding a pattern is a one-line
  change. Detectors receive a single context struct instead of three arguments.
- `body_string` is computed lazily — most detectors never need it.
- `Candidate.rank` is now an enforced struct key; every candidate is ranked.
- `mix bundle_deps` only bundles runtime dependencies, so dev tooling (credo,
  dialyxir, ex_doc, excoveralls) can no longer leak into a published archive.
- `--format` values are validated; an unknown value no longer leaks an atom.
- `Parser` uses `String.to_existing_atom/1` so analysing untrusted source cannot
  exhaust the atom table.
- The reporter warns explicitly when no `.ex` files were analysed.
- CI matrix now covers Elixir 1.18 (the declared minimum) through 1.20, uses
  `actions/*@v4`, and keys the PLT cache per toolchain.

### Tests
- `test/prop_wise/law_table_test.exs` — table integrity, the `Map.merge`
  acceptance case, tolerance and edge cases.
- `test/prop_wise/law_suggestion_test.exs` — law → property rendering, arity
  awareness, library syntax.
- `test/prop_wise/baseline_test.exs` — snapshot/parse/diff/apply and the
  `--baseline` CLI integration including exit codes.
- `test/prop_wise/command_line_test.exs` — the CLI surface (arg parsing, file
  lists, exit codes, `--output`) was previously untested.
- `test/prop_wise/regression_test.exs` — one test per issue found in the audit.
- `test/prop_wise/property_test.exs` — StreamData properties for
  `find_inverse_pairs/1` and `detect_patterns/1`.

### Removed
- Stray `dllb_3010.sock` and `erl_crash.dump` from the repository root.

## [0.4.2] - 2026-04-01
### Added
- Ranked findings: every candidate now gets a 1-based rank, and inverse-pair members
  (e.g. `encode`/`decode`) always rank above non-pair candidates
- `--show-all` CLI flag (and `:show_all` library option) to display every finding
- `:limit` library option to override the default display limit of 3

### Changed
- Reports now show only the top 3 candidates and top 3 inverse pairs by default,
  followed by a `… and N more` note; `--show-all` shows everything (still ranked)
- Candidate headings and metadata now include the rank (`Rank: #N`)
- JSON output now includes `rank` and `inverse_pair` per candidate

…

## [0.3.0] - 2026-03-20

### Changed
- Rewrote pattern detection to drastically reduce false positives
  - Numeric detector now uses AST walking instead of regex on stringified code
  - Validation detector uses naming conventions (`?` suffix, `valid`/`check`/`is_` prefix) instead of body content
  - Transformation detector only matches struct/map manipulation, not bare pipelines
  - Inverse pair detection uses segment matching instead of substring matching
- Rewrote suggestion generator with template-based approach
  - Suggestions now use actual function names and arities
  - Encoder/decoder suggestions reference actual inverse function names
  - Added TODO comments to guide users on customizing placeholders
- Consolidated CLI and Mix task into shared `PropWise.CommandLine` module
- Added `--output` and `--no-fail` flags to escript CLI (previously Mix-only)

### Added
- `PropWise.FunctionInfo` struct with enforced keys for function metadata
- `PropWise.Candidate` struct with enforced keys for analysis results
- Typespecs on all public functions across all modules
- Comprehensive test suite for PatternDetector, Analyzer, SuggestionGenerator, and Reporter

### Fixed
- Purity analyzer no longer flags `!` (boolean not) as a side effect
- Removed `put_in/2`, `update_in/2`, `get_and_update_in/2` from side-effect list (they are pure)
- Config is now loaded once per analysis run instead of twice
- `Macro.to_string/1` is computed once per function instead of in each detector
- Default min_score aligned to 4 across all documentation

## [0.1.0] - 2026-01-19

### Added
- Initial release of PropWise
- AST-based analysis for identifying property-based testing candidates
- Purity analysis to detect functions without side effects
- Pattern detection for seven types of testable patterns:
  - Collection operations (Enum, Stream, comprehensions)
  - Data transformations (pipelines, struct/map manipulation)
  - Validation functions (predicates, boolean checks)
  - Algebraic structures (merge, concat, compose operations)
  - Encoder/decoder functions
  - Parser functions
  - Numeric algorithms
- Inverse function pair detection (encode/decode, serialize/deserialize, etc.)
- Concrete property-based test generation using stream_data
- Testability scoring system with configurable threshold
- Command-line interface via escript
- Mix task integration (`mix propwise`)
- JSON and text output formats
- Configuration file support (`.propwise.exs`)
- Comprehensive documentation and scoring guide

[Unreleased]: https://github.com/Oeditus/propwise/compare/v0.3.0...HEAD
[0.3.0]: https://github.com/Oeditus/propwise/compare/v0.1.0...v0.3.0
[0.1.0]: https://github.com/Oeditus/propwise/releases/tag/v0.1.0
