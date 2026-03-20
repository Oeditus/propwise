# Multi-Language Support Analysis for PropWise

This document analyzes the feasibility of extending PropWise to support property-based testing candidate identification in multiple languages beyond Elixir.

## Executive Summary

Extending PropWise to support other languages is **moderately challenging** but entirely feasible. The core challenge is not in the architecture (which is well-designed and modular) but in:

1. Language-specific AST parsing and traversal
2. Side-effect detection patterns that vary by language
3. Idiomatic pattern recognition per language
4. Property testing library ecosystem differences

**Difficulty ranking by language** (easiest to hardest):
1. **Ruby** (easiest - dynamic, similar to Elixir, good AST tools)
2. **Python** (easy - excellent AST module, dynamic typing)
3. **JavaScript/TypeScript** (moderate - good parsers, but async complexity)
4. **Rust** (moderate-hard - different paradigm, but excellent tooling)
5. **Go** (moderate-hard - different patterns, but simple AST)
6. **Java** (hard - verbose AST, complex ecosystem)
7. **C#** (hard - complex AST, .NET integration required)

## Architecture Compatibility

PropWise's current architecture is **highly extensible** for multi-language support:

```
┌─────────────┐
│   Config    │  ← Language-agnostic
└──────┬──────┘
       ↓
┌─────────────┐
│   Parser    │  ← **NEEDS LANGUAGE-SPECIFIC IMPLEMENTATION**
└──────┬──────┘
       ↓
┌─────────────┐  ┌──────────────────┐
│   Purity    │←─┤ Side Effect      │  ← **NEEDS LANGUAGE-SPECIFIC PATTERNS**
│  Analyzer   │  │ Definitions      │
└──────┬──────┘  └──────────────────┘
       ↓
┌─────────────┐  ┌──────────────────┐
│  Pattern    │←─┤ Pattern          │  ← **NEEDS LANGUAGE-SPECIFIC PATTERNS**
│  Detector   │  │ Definitions      │
└──────┬──────┘  └──────────────────┘
       ↓
┌─────────────┐
│  Analyzer   │  ← Language-agnostic scoring logic
└──────┬──────┘
       ↓
┌─────────────┐  ┌──────────────────┐
│ Suggestion  │←─┤ Library          │  ← **NEEDS LIBRARY-SPECIFIC TEMPLATES**
│ Generator   │  │ Templates        │
└──────┬──────┘  └──────────────────┘
       ↓
┌─────────────┐
│  Reporter   │  ← Language-agnostic (minor adjustments)
└─────────────┘
```

### Key Components Analysis

#### 1. Parser (Requires Complete Rewrite Per Language)
**Current**: Uses Elixir's `Code.string_to_quoted/1` to get AST
**Required**: Language-specific AST parser

#### 2. PurityAnalyzer (Requires Pattern Customization)
**Current**: Detects Elixir-specific side effects (IO, GenServer, Ecto, etc.)
**Required**: Language-specific side effect patterns

#### 3. PatternDetector (Requires Pattern Customization)
**Current**: Detects Elixir patterns (Enum, Stream, pipelines, etc.)
**Required**: Language-specific idioms and patterns

#### 4. SuggestionGenerator (Requires Template Customization)
**Current**: Generates stream_data and PropEr test templates
**Required**: Language-specific property testing library templates

## Language-by-Language Analysis

### 1. JavaScript / TypeScript

**Difficulty**: Moderate (★★★☆☆)

#### AST Parsing
**Tool**: [babel-parser](https://babeljs.io/docs/babel-parser) or [typescript-compiler](https://github.com/microsoft/TypeScript)

```javascript
// Example using @babel/parser
const parser = require('@babel/parser');
const traverse = require('@babel/traverse').default;

const code = `
function merge(arr1, arr2) {
  return [...arr1, ...arr2].sort();
}
`;

const ast = parser.parse(code, {
  sourceType: 'module',
  plugins: ['typescript']
});
```

**Node.js Integration**: Use `:nodejs` port or create microservice

#### Side Effect Patterns
```elixir
@javascript_side_effects [
  # I/O
  {:console, :*, :*},
  {:fs, :*, :*},
  {:process, :*, :*},
  
  # HTTP
  {:fetch, :*},
  {:axios, :*, :*},
  
  # DOM
  {:document, :*, :*},
  {:window, :*, :*},
  {:localStorage, :*, :*},
  
  # Database
  {:mongoose, :*, :*},
  {:sequelize, :*, :*},
  
  # Side effect functions
  {:setTimeout, :*},
  {:setInterval, :*},
  {:Promise, :*, :*}  # async operations
]
```

#### Testable Patterns
- Array methods: `map`, `filter`, `reduce`, `flatMap`
- Pure functions (no `this`, no closures over mutable state)
- Transformations using spread operators
- Utility functions (lodash-style)
- Validators and predicates

#### Property Testing Libraries
- **fast-check** (most mature): https://github.com/dubzzz/fast-check
- **jsverify**: https://github.com/jsverify/jsverify
- **testcheck-js**: https://github.com/leebyron/testcheck-js

**Example Output**:
```javascript
// fast-check
const fc = require('fast-check');

test('merge preserves all elements', () => {
  fc.assert(
    fc.property(
      fc.array(fc.integer()),
      fc.array(fc.integer()),
      (arr1, arr2) => {
        const result = merge(arr1, arr2);
        return result.length === arr1.length + arr2.length;
      }
    )
  );
});
```

#### TypeScript Benefits
- Type information can improve pattern detection
- Can detect pure functions more accurately via types
- Easier to identify function signatures

**Recommendation**: Start with JavaScript, add TypeScript later

---

### 2. Python

**Difficulty**: Easy (★★☆☆☆)

#### AST Parsing
**Tool**: Built-in `ast` module (no external dependencies!)

```python
import ast

code = """
def merge_sorted(list1, list2):
    return sorted(list1 + list2)
"""

tree = ast.parse(code)

class FunctionVisitor(ast.NodeVisitor):
    def visit_FunctionDef(self, node):
        print(f"Function: {node.name}")
        print(f"Args: {[arg.arg for arg in node.args.args]}")
        # Walk the body
        self.generic_visit(node)
```

**Integration**: Use `:python` port or create separate Python tool that outputs JSON

#### Side Effect Patterns
```elixir
@python_side_effects [
  # I/O
  {:print, :*},
  {:open, :*},
  {:input, :*},
  {:file, :*, :*},
  {:io, :*, :*},
  
  # OS/System
  {:os, :*, :*},
  {:sys, :*, :*},
  {:subprocess, :*, :*},
  
  # HTTP
  {:requests, :*, :*},
  {:urllib, :*, :*},
  {:httpx, :*, :*},
  
  # Database
  {:sqlite3, :*, :*},
  {:psycopg2, :*, :*},
  {:sqlalchemy, :*, :*},
  {:pymongo, :*, :*},
  
  # Global state
  {:globals, :*},
  {:setattr, :*},
  {:delattr, :*},
  
  # Async (might be pure or impure)
  {:asyncio, :*, :*}
]
```

#### Testable Patterns
- List comprehensions
- `map()`, `filter()`, `reduce()` from `functools`
- Functions using `itertools`
- Data class transformations
- Validators (using predicates)
- Serialization: `json.dumps/loads`, `pickle`
- Pure mathematical functions

#### Property Testing Libraries
- **Hypothesis** (most mature): https://hypothesis.readthedocs.io/
- **QuickCheck** (Python port): limited
- **PropCheck**: https://github.com/Technologicat/propcheck

**Example Output**:
```python
from hypothesis import given
from hypothesis.strategies import lists, integers

@given(lists(integers()), lists(integers()))
def test_merge_sorted_preserves_length(list1, list2):
    result = merge_sorted(list1, list2)
    assert len(result) == len(list1) + len(list2)

@given(lists(integers()), lists(integers()))
def test_merge_sorted_is_sorted(list1, list2):
    result = merge_sorted(list1, list2)
    assert result == sorted(result)
```

**Recommendation**: Excellent candidate, Python's AST module is first-class

---

### 3. Go

**Difficulty**: Moderate-Hard (★★★★☆)

#### AST Parsing
**Tool**: Go's standard library `go/parser` and `go/ast`

```go
package main

import (
    "go/ast"
    "go/parser"
    "go/token"
)

func main() {
    src := `
    package main
    
    func merge(a, b []int) []int {
        result := append(a, b...)
        sort.Ints(result)
        return result
    }
    `
    
    fset := token.NewFileSet()
    f, _ := parser.ParseFile(fset, "", src, 0)
    
    ast.Inspect(f, func(n ast.Node) bool {
        if fn, ok := n.(*ast.FuncDecl); ok {
            // Process function
        }
        return true
    })
}
```

**Integration**: Create separate Go tool that outputs JSON, call from Elixir via Port

#### Side Effect Patterns
```elixir
@go_side_effects [
  # I/O
  {:fmt, :Print, :*},
  {:fmt, :Println, :*},
  {:fmt, :Printf, :*},
  {:os, :*, :*},
  {:io, :*, :*},
  {:bufio, :*, :*},
  
  # HTTP
  {:http, :*, :*},
  {:net, :*, :*},
  
  # Database
  {:sql, :*, :*},
  {:database, :*, :*},
  
  # Concurrency (channels, goroutines)
  {:go, :*},  # go keyword
  {:chan, :*}, # channel operations
  
  # File system
  {:ioutil, :*, :*},
  {:filepath, :*, :*},
  
  # Time
  {:time, :Sleep, :*},
  {:time, :Now, :*}
]
```

#### Testable Patterns
- Slice operations: `append`, copying
- Map transformations
- String manipulation
- Sorting and filtering
- Mathematical operations
- Encoders/decoders (JSON, XML, Protocol Buffers)
- Validators

#### Property Testing Libraries
- **gopter**: https://github.com/leanovate/gopter
- **quick** (standard library): limited functionality
- **rapid**: https://github.com/flyingmutant/rapid

**Example Output**:
```go
import (
    "testing"
    "github.com/leanovate/gopter"
    "github.com/leanovate/gopter/gen"
    "github.com/leanovate/gopter/prop"
)

func TestMergePreservesLength(t *testing.T) {
    properties := gopter.NewProperties(nil)
    
    properties.Property("merge preserves total length", prop.ForAll(
        func(a, b []int) bool {
            result := merge(a, b)
            return len(result) == len(a) + len(b)
        },
        gen.SliceOf(gen.Int()),
        gen.SliceOf(gen.Int()),
    ))
    
    properties.TestingRun(t)
}
```

**Challenges**:
- Go is not functional - many patterns differ
- Interface with Elixir requires separate process
- Different idioms (error handling, no exceptions)

**Recommendation**: Feasible but requires Go expertise

---

### 4. Rust

**Difficulty**: Moderate-Hard (★★★★☆)

#### AST Parsing
**Tool**: [syn](https://github.com/dtolnay/syn) - the de-facto Rust parser

```rust
use syn::{File, Item, ItemFn};

fn main() {
    let code = r#"
        fn merge_sorted<T: Ord>(mut a: Vec<T>, mut b: Vec<T>) -> Vec<T> {
            a.append(&mut b);
            a.sort();
            a
        }
    "#;
    
    let ast: File = syn::parse_file(code).unwrap();
    
    for item in ast.items {
        if let Item::Fn(func) = item {
            println!("Function: {}", func.sig.ident);
        }
    }
}
```

**Integration**: Create Rust CLI tool, call from Elixir via Port or NIFs (using Rustler)

#### Side Effect Patterns
```elixir
@rust_side_effects [
  # I/O
  {:println, :*},
  {:print, :*},
  {:std, :io, :*},
  {:std, :fs, :*},
  
  # HTTP
  {:reqwest, :*, :*},
  {:hyper, :*, :*},
  
  # Database
  {:diesel, :*, :*},
  {:sqlx, :*, :*},
  
  # Concurrency/async
  {:tokio, :*, :*},
  {:async_std, :*, :*},
  {:std, :sync, :Mutex},  # mutable shared state
  {:std, :sync, :RwLock},
  
  # System
  {:std, :process, :*},
  {:std, :env, :*},
  
  # Special: detect mutable borrows
  # This requires deeper analysis
  {:&mut, :*}
]
```

#### Testable Patterns
- Iterator methods: `map`, `filter`, `fold`, `flat_map`
- Pure transformations
- Mathematical operations
- Serialization (serde): `serialize`/`deserialize`
- String parsing
- Validators
- Result/Option handling (pure functional patterns)

#### Property Testing Libraries
- **proptest**: https://github.com/proptest-rs/proptest (most mature)
- **quickcheck**: https://github.com/BurntSushi/quickcheck
- **arbitrary**: https://github.com/rust-fuzz/arbitrary

**Example Output**:
```rust
use proptest::prelude::*;

proptest! {
    #[test]
    fn merge_sorted_preserves_length(
        a in prop::collection::vec(any::<i32>(), 0..100),
        b in prop::collection::vec(any::<i32>(), 0..100)
    ) {
        let result = merge_sorted(a.clone(), b.clone());
        prop_assert_eq!(result.len(), a.len() + b.len());
    }
    
    #[test]
    fn merge_sorted_is_sorted(
        a in prop::collection::vec(any::<i32>(), 0..100),
        b in prop::collection::vec(any::<i32>(), 0..100)
    ) {
        let result = merge_sorted(a, b);
        prop_assert!(result.windows(2).all(|w| w[0] <= w[1]));
    }
}
```

**Challenges**:
- Ownership/borrowing makes purity analysis complex
- Mutable vs immutable semantics
- Async functions complicate analysis
- Type system is complex

**Benefits**:
- Compiler guarantees help identify pure functions
- Strong type system aids analysis
- Excellent tooling

**Recommendation**: High value but requires Rust expertise

---

### 5. Ruby

**Difficulty**: Easy (★★☆☆☆)

#### AST Parsing
**Tool**: `parser` gem or `RubyVM::AbstractSyntaxTree` (Ruby 2.6+)

```ruby
require 'parser/current'

code = <<~RUBY
  def merge_sorted(arr1, arr2)
    (arr1 + arr2).sort
  end
RUBY

ast = Parser::CurrentRuby.parse(code)

# Or using built-in (Ruby 2.6+)
ast = RubyVM::AbstractSyntaxTree.parse(code)
```

**Integration**: Create Ruby CLI tool, call from Elixir via Port

#### Side Effect Patterns
```elixir
@ruby_side_effects [
  # I/O
  {:puts, :*},
  {:print, :*},
  {:p, :*},
  {:gets, :*},
  {:File, :*, :*},
  {:IO, :*, :*},
  
  # HTTP
  {:Net, :HTTP, :*},
  {:HTTParty, :*, :*},
  {:Faraday, :*, :*},
  
  # Database
  {:ActiveRecord, :*, :*},
  {:Sequel, :*, :*},
  
  # System
  {:system, :*},
  {:exec, :*},
  {:`, :*},  # backticks
  
  # Global state
  {:@, :*},  # instance variables
  {:@@, :*}, # class variables
  {:$, :*},  # global variables
  
  # Mutation
  {:!, :*}  # bang methods (convention for mutation)
]
```

#### Testable Patterns
- Enumerable methods: `map`, `select`, `reduce`, `flat_map`
- Pure transformations
- String manipulations
- Hash/Array operations
- JSON serialization
- Validators
- Mathematical operations

#### Property Testing Libraries
- **rantly**: https://github.com/abargnesi/rantly
- **propcheck**: https://github.com/Qqwy/ruby-prop_check
- **rspec-proptest**: https://github.com/hasclass/rspec-proptest

**Example Output**:
```ruby
require 'rantly'
require 'rspec'

describe '#merge_sorted' do
  it 'preserves total length' do
    property_of {
      arr1 = array { integer }
      arr2 = array { integer }
      [arr1, arr2]
    }.check { |arr1, arr2|
      result = merge_sorted(arr1, arr2)
      expect(result.length).to eq(arr1.length + arr2.length)
    }
  end
  
  it 'produces sorted output' do
    property_of {
      arr1 = array { integer }
      arr2 = array { integer }
      [arr1, arr2]
    }.check { |arr1, arr2|
      result = merge_sorted(arr1, arr2)
      expect(result).to eq(result.sort)
    }
  end
end
```

**Recommendation**: Excellent candidate, similar philosophy to Elixir

---

### 6. Java

**Difficulty**: Hard (★★★★★)

#### AST Parsing
**Tool**: [JavaParser](https://javaparser.org/) or [Eclipse JDT](https://www.eclipse.org/jdt/)

```java
import com.github.javaparser.JavaParser;
import com.github.javaparser.ast.CompilationUnit;
import com.github.javaparser.ast.body.MethodDeclaration;
import com.github.javaparser.ast.visitor.VoidVisitorAdapter;

String code = """
    public class Utils {
        public static List<Integer> mergeSorted(List<Integer> a, List<Integer> b) {
            List<Integer> result = new ArrayList<>(a);
            result.addAll(b);
            Collections.sort(result);
            return result;
        }
    }
    """;

CompilationUnit cu = new JavaParser().parse(code).getResult().get();

cu.accept(new VoidVisitorAdapter<Void>() {
    @Override
    public void visit(MethodDeclaration md, Void arg) {
        System.out.println("Method: " + md.getName());
        super.visit(md, arg);
    }
}, null);
```

**Integration**: Create Java CLI tool, call from Elixir via Port

#### Side Effect Patterns
```elixir
@java_side_effects [
  # I/O
  {:System, :out, :println},
  {:System, :err, :println},
  {:PrintStream, :*, :*},
  {:Scanner, :*, :*},
  {:Files, :*, :*},
  {:BufferedReader, :*, :*},
  
  # HTTP
  {:HttpClient, :*, :*},
  {:URLConnection, :*, :*},
  
  # Database
  {:Connection, :*, :*},
  {:Statement, :*, :*},
  {:EntityManager, :*, :*},  # JPA
  
  # Collections mutations
  {:add, :*},
  {:remove, :*},
  {:put, :*},
  {:set, :*},
  
  # Concurrency
  {:Thread, :*, :*},
  {:ExecutorService, :*, :*},
  {:CompletableFuture, :*, :*}
]
```

#### Testable Patterns
- Stream API: `map`, `filter`, `reduce`, `flatMap`
- Static utility methods
- Immutable transformations
- Validators
- Serialization/deserialization
- Mathematical operations
- Pure functions in functional-style Java

#### Property Testing Libraries
- **jqwik**: https://jqwik.net/ (most mature)
- **junit-quickcheck**: https://github.com/pholser/junit-quickcheck
- **QuickTheories**: https://github.com/quicktheories/QuickTheories

**Example Output**:
```java
import net.jqwik.api.*;

class MergeTests {
    @Property
    boolean mergeSortedPreservesLength(
        @ForAll List<@IntRange(min = -100, max = 100) Integer> a,
        @ForAll List<@IntRange(min = -100, max = 100) Integer> b
    ) {
        List<Integer> result = Utils.mergeSorted(a, b);
        return result.size() == a.size() + b.size();
    }
    
    @Property
    boolean mergeSortedIsSorted(
        @ForAll List<Integer> a,
        @ForAll List<Integer> b
    ) {
        List<Integer> result = Utils.mergeSorted(a, b);
        for (int i = 0; i < result.size() - 1; i++) {
            if (result.get(i) > result.get(i + 1)) {
                return false;
            }
        }
        return true;
    }
}
```

**Challenges**:
- Verbose AST structure
- Complex type system
- Mutation is common (harder to detect purity)
- OOP paradigm differs from functional
- Need to handle inheritance, interfaces, generics

**Recommendation**: Feasible but requires significant effort

---

### 7. C#

**Difficulty**: Hard (★★★★★)

#### AST Parsing
**Tool**: [Roslyn](https://github.com/dotnet/roslyn) - official .NET compiler platform

```csharp
using Microsoft.CodeAnalysis;
using Microsoft.CodeAnalysis.CSharp;
using Microsoft.CodeAnalysis.CSharp.Syntax;

string code = @"
    public static List<int> MergeSorted(List<int> a, List<int> b)
    {
        var result = new List<int>(a);
        result.AddRange(b);
        result.Sort();
        return result;
    }
";

SyntaxTree tree = CSharpSyntaxTree.ParseText(code);
CompilationUnitSyntax root = tree.GetCompilationUnitRoot();

foreach (var method in root.DescendantNodes().OfType<MethodDeclarationSyntax>())
{
    Console.WriteLine($"Method: {method.Identifier}");
}
```

**Integration**: Create .NET CLI tool, call from Elixir via Port

#### Side Effect Patterns
```elixir
@csharp_side_effects [
  # I/O
  {:Console, :WriteLine, :*},
  {:Console, :Write, :*},
  {:Console, :ReadLine, :*},
  {:File, :*, :*},
  {:StreamReader, :*, :*},
  {:StreamWriter, :*, :*},
  
  # HTTP
  {:HttpClient, :*, :*},
  {:WebClient, :*, :*},
  
  # Database
  {:DbContext, :*, :*},
  {:SqlConnection, :*, :*},
  {:EntityFramework, :*, :*},
  
  # Collections mutations
  {:Add, :*},
  {:Remove, :*},
  {:Insert, :*},
  
  # Async/Threading
  {:Task, :Run, :*},
  {:Thread, :*, :*},
  {:async, :*},
  {:await, :*},
  
  # State
  # Properties with setters
  # Events
]
```

#### Testable Patterns
- LINQ: `Select`, `Where`, `Aggregate`, `SelectMany`
- Pure static methods
- Extension methods
- Immutable transformations
- Validators
- Serialization (JSON.NET, System.Text.Json)
- Mathematical operations
- Records (C# 9+) transformations

#### Property Testing Libraries
- **FsCheck**: https://fscheck.github.io/FsCheck/ (F# library, works with C#)
- **CsCheck**: https://github.com/AnthonyLloyd/CsCheck
- **Hedgehog**: https://github.com/hedgehogqa/fsharp-hedgehog (F#-first)

**Example Output**:
```csharp
using FsCheck;
using FsCheck.Xunit;

public class MergeTests
{
    [Property]
    public Property MergeSortedPreservesLength(List<int> a, List<int> b)
    {
        var result = Utils.MergeSorted(a, b);
        return (result.Count == a.Count + b.Count).ToProperty();
    }
    
    [Property]
    public bool MergeSortedIsSorted(List<int> a, List<int> b)
    {
        var result = Utils.MergeSorted(a, b);
        return result.Zip(result.Skip(1), (x, y) => x <= y).All(x => x);
    }
}
```

**Challenges**:
- Complex .NET ecosystem
- Requires .NET runtime
- Async/await patterns complicate analysis
- Properties with getters/setters
- Events and delegates
- Need to handle generics, interfaces, inheritance

**Recommendation**: Feasible but requires .NET expertise and significant effort

---

## Implementation Strategies

### Option 1: Monolithic (All-in-Elixir with Ports)

Create language-specific parsers as separate CLI tools that output JSON, called via Elixir Ports.

```
PropWise (Elixir)
    ├─ PropWise.Parser.JavaScript (calls node.js tool via Port)
    ├─ PropWise.Parser.Python (calls python tool via Port)
    ├─ PropWise.Parser.Go (calls go binary via Port)
    └─ ... etc
```

**Pros**:
- Keeps core logic in Elixir
- Leverages native language parsers
- Relatively simple integration

**Cons**:
- Requires all language runtimes installed
- Performance overhead from process communication
- Complex error handling

### Option 2: Language-Specific Standalone Tools

Create completely separate tools for each language, sharing only the conceptual design.

```
propwise-js (Node.js/TypeScript)
propwise-py (Python)
propwise-go (Go)
propwise-rs (Rust)
... etc
```

**Pros**:
- Native performance
- Idiomatic to each language
- Can be maintained by language-specific experts
- No runtime dependencies on other languages

**Cons**:
- Code duplication
- Harder to maintain consistency
- More initial work

### Option 3: Hybrid (Core DSL + Language Plugins)

Create a language-agnostic intermediate representation (IR) that each parser produces.

```elixir
# Common IR format
%{
  language: "javascript",
  functions: [
    %{
      module: "utils",
      name: "merge",
      arity: 2,
      body_ast: {...},  # Simplified/normalized AST
      file: "utils.js",
      line: 10,
      type: :public
    }
  ]
}
```

Then use Elixir to process the IR for purity analysis, pattern detection, etc.

**Pros**:
- Best of both worlds
- Shared core logic
- Easier to add new languages

**Cons**:
- Complex IR design
- Translation layer needed
- Potential information loss

**Recommendation**: Start with Option 1 (Ports), migrate to Option 3 if successful

---

## Recommended Phased Rollout

### Phase 1: Proof of Concept (Python)
**Why**: Built-in AST module, easy integration, mature property testing (Hypothesis)

1. Create `propwise_python` subdirectory
2. Build Python CLI tool that:
   - Parses Python files
   - Outputs function metadata as JSON
3. Add `PropWise.Parser.Python` that calls Python tool
4. Add Python-specific side effect patterns
5. Add Python-specific testable patterns
6. Add Hypothesis template generation

**Timeline**: 2-3 weeks for experienced developer

### Phase 2: JavaScript/TypeScript
**Why**: Huge market, excellent tooling (Babel), good property testing (fast-check)

**Timeline**: 3-4 weeks

### Phase 3: Ruby
**Why**: Similar philosophy to Elixir, easy AST parsing

**Timeline**: 2-3 weeks

### Phase 4: Go or Rust
**Why**: Different paradigm, validates architecture flexibility

**Timeline**: 4-6 weeks each

### Phase 5+: Java and C#
**Why**: Enterprise languages, complex but high value

**Timeline**: 6-8 weeks each

---

## Technical Challenges

### 1. Async/Concurrency Patterns
Languages like JavaScript, Python (asyncio), Go, Rust have async patterns that complicate purity analysis.

**Solution**: Treat async functions as potentially impure by default, allow configuration

### 2. Type Systems
Statically typed languages (TypeScript, Go, Rust, Java, C#) provide more information but add complexity.

**Solution**: Use type information when available to improve detection accuracy

### 3. Mutation Detection
Many languages allow mutation. Detecting whether a function mutates its arguments is hard.

**Solution**: 
- Conservative approach: flag any mutation as impure
- Use language-specific idioms (e.g., Java immutable collections)

### 4. Cross-Module Analysis
Current PropWise doesn't track function calls across modules to determine purity.

**Solution**: Future enhancement for all languages

### 5. Language-Specific Idioms
Each language has different conventions for what constitutes "good" candidates.

**Solution**: Extensive research into each language's best practices

---

## Directory Structure Proposal

```
propwise/
├── lib/
│   ├── prop_wise/
│   │   ├── parser.ex              # Generic parser interface
│   │   ├── parser/
│   │   │   ├── elixir.ex          # Current implementation
│   │   │   ├── javascript.ex      # Calls JS parser
│   │   │   ├── python.ex          # Calls Python parser
│   │   │   └── ...
│   │   ├── purity_analyzer.ex     # Core logic
│   │   ├── side_effects/
│   │   │   ├── elixir.ex          # Elixir patterns
│   │   │   ├── javascript.ex      # JS patterns
│   │   │   └── ...
│   │   ├── pattern_detector.ex    # Core logic
│   │   ├── patterns/
│   │   │   ├── elixir.ex
│   │   │   ├── javascript.ex
│   │   │   └── ...
│   │   ├── suggestion_generator.ex
│   │   ├── suggestions/
│   │   │   ├── stream_data.ex     # Elixir
│   │   │   ├── proper.ex          # Elixir
│   │   │   ├── fast_check.ex      # JavaScript
│   │   │   ├── hypothesis.ex      # Python
│   │   │   └── ...
│   │   └── ...
├── parsers/
│   ├── javascript/
│   │   ├── package.json
│   │   ├── parser.js              # AST extraction tool
│   │   └── bin/propwise-parse-js
│   ├── python/
│   │   ├── parser.py
│   │   └── setup.py
│   ├── go/
│   │   ├── parser.go
│   │   └── go.mod
│   └── ...
└── test/
    ├── fixtures/
    │   ├── elixir/
    │   ├── javascript/
    │   ├── python/
    │   └── ...
    └── ...
```

---

## Configuration Example

```elixir
# .propwise.exs
%{
  # Language detection (auto-detect by file extension or explicit)
  language: :auto,  # or :elixir, :javascript, :python, etc.
  
  # Language-specific paths
  analyze_paths: %{
    elixir: ["lib"],
    javascript: ["src", "lib"],
    typescript: ["src"],
    python: ["src", "lib"],
    go: ["pkg", "internal"],
    rust: ["src"],
    java: ["src/main/java"],
    csharp: ["src"],
    ruby: ["lib"]
  },
  
  # Library per language
  library: %{
    elixir: :stream_data,
    javascript: :fast_check,
    python: :hypothesis,
    go: :gopter,
    rust: :proptest,
    java: :jqwik,
    csharp: :fscheck,
    ruby: :rantly
  },
  
  # Minimum score (can be per-language)
  min_score: 4
}
```

---

## API Design

```elixir
# Analyze any language
PropWise.analyze("./my_js_project", language: :javascript)

# Multi-language project
PropWise.analyze_multi("./monorepo", languages: [:elixir, :javascript, :python])

# Custom parser
PropWise.analyze("./project", parser: CustomParser)
```

---

## Estimated Effort

| Language     | Parser | Side Effects | Patterns | Suggestions | Testing | Total |
|--------------|--------|--------------|----------|-------------|---------|-------|
| Python       | 1 week | 3 days       | 1 week   | 1 week      | 1 week  | 4-5 weeks |
| JavaScript   | 2 weeks| 1 week       | 1 week   | 1 week      | 1 week  | 6 weeks |
| TypeScript   | +1 week| +2 days      | +3 days  | same        | +3 days | +2 weeks |
| Ruby         | 1 week | 3 days       | 1 week   | 1 week      | 1 week  | 4-5 weeks |
| Go           | 2 weeks| 1 week       | 2 weeks  | 1 week      | 1 week  | 7 weeks |
| Rust         | 2 weeks| 1 week       | 2 weeks  | 1 week      | 1 week  | 7 weeks |
| Java         | 3 weeks| 2 weeks      | 2 weeks  | 1 week      | 2 weeks | 10 weeks |
| C#           | 3 weeks| 2 weeks      | 2 weeks  | 1 week      | 2 weeks | 10 weeks |

**Total for all languages**: ~50-60 weeks of development time

With a team of 2-3 developers, this could be completed in 6-9 months.

---

## Risks and Mitigation

### Risk 1: Parser Maintenance
Each language evolves, breaking parsers.

**Mitigation**: Use mature, well-maintained parsing libraries

### Risk 2: False Positives/Negatives
Static analysis can't catch everything.

**Mitigation**: 
- Be conservative (better to miss candidates than suggest bad ones)
- Allow user configuration/overrides
- Clear documentation of limitations

### Risk 3: Runtime Dependencies
Users need all language runtimes installed.

**Mitigation**:
- Detect which languages are in the project
- Only require relevant runtimes
- Provide Docker image with all runtimes

### Risk 4: Performance
Parsing large codebases could be slow.

**Mitigation**:
- Parallel processing
- Caching
- Incremental analysis

---

## Success Metrics

1. **Accuracy**: >80% of suggestions are useful
2. **Coverage**: Finds >70% of obvious pure function candidates
3. **Performance**: Analyzes 10k LOC in <30 seconds
4. **Adoption**: Used by >100 projects per language within 6 months
5. **Community**: Contributors from each language community

---

## Conclusion

Extending PropWise to support multiple languages is **definitely feasible** and would provide tremendous value to the broader software development community. The architecture is already well-suited for this expansion.

### Recommended Next Steps

1. **Validate demand**: Survey developer communities for each language
2. **Start with Python**: Easiest implementation, fastest validation
3. **Build core abstractions**: Create language-agnostic interfaces
4. **Iterate quickly**: Get feedback from early users
5. **Community-driven**: Open source and encourage language-specific experts to contribute

### Key Success Factors

- **Modularity**: Keep language-specific logic isolated
- **Documentation**: Clear guides for adding new languages
- **Testing**: Comprehensive test fixtures for each language
- **Performance**: Optimize parser communication
- **Usability**: Simple installation and configuration

The project has excellent potential to become a multi-language static analysis tool for property-based testing, similar to how ESLint works for linting across languages.
