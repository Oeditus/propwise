# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
