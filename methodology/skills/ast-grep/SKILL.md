---
name: ast-grep
description: Guide for writing ast-grep rules to perform structural code search and analysis. Use when users need to search codebases using Abstract Syntax Tree (AST) patterns, find specific code structures, or perform complex code queries that go beyond simple text search. This skill should be used when users ask to search for code patterns, find specific language constructs, or locate code with particular structural characteristics.
---

# ast-grep Code Search

## Overview

This skill helps translate natural language queries into ast-grep rules for structural code search. ast-grep uses Abstract Syntax Tree (AST) patterns to match code based on its structure rather than just text, enabling powerful and precise code search across large codebases.

## When to Use This Skill

Use this skill when users:
- Need to search for code patterns using structural matching (e.g., "find all async functions that don't have error handling")
- Want to locate specific language constructs (e.g., "find all function calls with specific parameters")
- Request searches that require understanding code structure rather than just text
- Ask to search for code with particular AST characteristics
- Need to perform complex code queries that traditional text search cannot handle

## General Workflow

Follow this process to help users write effective ast-grep rules:

### Step 1: Understand the Query

Clearly understand what the user wants to find. Ask clarifying questions if needed:
- What specific code pattern or structure are they looking for?
- Which programming language?
- Are there specific edge cases or variations to consider?
- What should be included or excluded from matches?

### Step 2: Create Example Code

Write a simple code snippet that represents what the user wants to match. Save this to a temporary file for testing.

**Example:**
If searching for "async functions that use await", create a test file:

```javascript
// test_example.js
async function example() {
  const result = await fetchData();
  return result;
}
```

### Step 3: Write the ast-grep Rule

Translate the pattern into an ast-grep rule. Start simple and add complexity as needed.

**Key principles:**
- Always use `stopBy: end` for relational rules (`inside`, `has`) to ensure search goes to the end of the direction
- Use `pattern` for simple structures
- Use `kind` with `has`/`inside` for complex structures
- Break complex queries into smaller sub-rules using `all`, `any`, or `not`

**Example rule file (test_rule.yml):**
```yaml
id: async-with-await
language: javascript
rule:
  kind: function_declaration
  has:
    pattern: await $EXPR
    stopBy: end
```

See `references/rule_reference.md` for comprehensive rule documentation.

### Step 4: Test the Rule

Use ast-grep CLI to verify the rule matches the example code. There are two main approaches:

**Option A: Test with inline rules (for quick iterations)**
```bash
echo "async function test() { await fetch(); }" | ast-grep scan --inline-rules "id: test
language: javascript
rule:
  kind: function_declaration
  has:
    pattern: await \$EXPR
    stopBy: end" --stdin
```

**Option B: Test with rule files (recommended for complex rules)**
```bash
ast-grep scan --rule test_rule.yml test_example.js
```

**Debugging if no matches:**
1. Simplify the rule (remove sub-rules)
2. Add `stopBy: end` to relational rules if not present
3. Use `--debug-query` to understand the AST structure (see below)
4. Check if `kind` values are correct for the language

### Step 5: Search the Codebase

Once the rule matches the example code correctly, search the actual codebase:

**For simple pattern searches:**
```bash
ast-grep run --pattern 'console.log($ARG)' --lang javascript /path/to/project
```

**For complex rule-based searches:**
```bash
ast-grep scan --rule my_rule.yml /path/to/project
```

**For inline rules (without creating files):**
```bash
ast-grep scan --inline-rules "id: my-rule
language: javascript
rule:
  pattern: \$PATTERN" /path/to/project
```

## ast-grep CLI Commands

### Inspect Code Structure (--debug-query)

`--debug-query` dumps how ast-grep parses **your pattern string** (not a target file). Pass the code you want to inspect AS the pattern; any file argument is only used for match output and does not affect the Debug block.

```bash
ast-grep run --pattern 'async function example() { await fetch(); }' \
  --lang javascript \
  --debug-query=cst
```

**Available formats:**
- `cst`: Concrete Syntax Tree of the pattern (all nodes including punctuation)
- `ast`: Abstract Syntax Tree of the pattern (named nodes only)
- `pattern`: How ast-grep interprets metavariables in the pattern

**Use this to:**
- Discover the `kind` name of a node by writing a tiny code snippet AS the pattern
- Debug why a pattern isn't matching (e.g. metavariable not detected, structural mismatch)
- Verify that ast-grep parses your pattern the way you think it does

**Example:**
```bash
# Discover the kind name for a class declaration: write the code AS the pattern
ast-grep run --pattern 'class User { constructor() {} }' \
  --lang javascript \
  --debug-query=cst

# See how ast-grep interprets metavariables
ast-grep run --pattern 'class $NAME { $$$BODY }' \
  --lang javascript \
  --debug-query=pattern
```

#### Discovering node `kind` names for a target file

`--debug-query=cst` shows the *pattern's* parse, not a file's. To see a file's full parse tree, use one of:

- **ast-grep playground** (fastest, no install): https://ast-grep.github.io/playground.html — paste code, see the AST live with `kind` names.
- **`tree-sitter parse <file>`** — if `tree-sitter` CLI is installed; dumps the file's tree with named nodes.
- **Reverse approach with `--debug-query`** — pick a small code snippet from the file, paste it AS the `--pattern` (wrapped in valid surrounding context if needed; see "Child-only node gotcha" below), and read the kind names from the Debug output.

#### Child-only node gotcha

Some grammar nodes only exist as children of a specific parent and cannot be pattern-matched bare. Symptom: a pattern like `except $E: $$$BODY` (Python) is rejected by the parser or simply never matches, and `--debug-query=cst` on that pattern shows `ERROR` nodes.

Common examples:
- Python: `except_clause`, `elif_clause`, `else_clause` (children of `try_statement`/`if_statement`)
- JavaScript/TypeScript: `catch_clause`, `finally_clause` (children of `try_statement`)
- Many languages have similar grammar-only-as-child constructs (`case` arms, `when` branches, etc.)

Workarounds:
1. **Use the parent kind with a relational rule:** match `try_statement` with `has: { kind: except_clause }`.
2. **Use the child kind as a relational target on something inside it:** `inside: { kind: except_clause, stopBy: end }` — match what's *inside* an except clause.
3. **To inspect the child node's structure**, parse a complete parent snippet:
   ```bash
   ast-grep run --pattern 'try:
       pass
   except Exception as e:
       handle(e)' --lang python --debug-query=cst
   ```
   The Debug CST will now contain the nested `except_clause` node and reveal its child kind names.

#### Composite rule structure gotcha

Inside `all:`, `any:`, and `not:`, each list item is itself a rule that must contain **exactly one positive matcher** (`kind`, `pattern`, or `regex`). A common error is putting a positive matcher and a relational rule (`has`, `inside`) as siblings inside the same list item:

```yaml
# WRONG — `has` is a sibling of `kind` inside the same `all:` item.
# Error: "Rule must have one positive matcher" or unexpected matches.
rule:
  all:
    - kind: arrow_function
      has:
        regex: "^async$"
```

Two correct forms:

```yaml
# Form A — separate list items (each is a self-contained rule):
rule:
  all:
    - kind: arrow_function
    - has:
        regex: "^async$"
        stopBy: end

# Form B — positive matcher at top of `rule:`, with `all:` as a sibling
# (top-of-rule fields are implicitly AND-conjoined):
rule:
  kind: arrow_function
  all:
    - has:
        regex: "^async$"
        stopBy: end
```

When in doubt, use Form A. The rule-of-thumb is: every node in the rule tree that has structural sub-rules (`has`, `inside`, `precedes`, `follows`) needs its own positive matcher as a sibling — and putting it inline at the same level is the trap. Split into list items under `all:` instead.

### Test Rules (scan with --stdin)

Test a rule against code snippet without creating files:

```bash
echo "const x = await fetch();" | ast-grep scan --inline-rules "id: test
language: javascript
rule:
  pattern: await \$EXPR" --stdin
```

**Add --json for structured output:**
```bash
echo "const x = await fetch();" | ast-grep scan --inline-rules "..." --stdin --json
```

### Search with Patterns (run)

Simple pattern-based search for single AST node matches:

```bash
# Basic pattern search
ast-grep run --pattern 'console.log($ARG)' --lang javascript .

# Search specific files
ast-grep run --pattern 'class $NAME' --lang python /path/to/project

# JSON output for programmatic use
ast-grep run --pattern 'function $NAME($$$)' --lang javascript --json .
```

**When to use:**
- Simple, single-node matches
- Quick searches without complex logic
- When you don't need relational rules (inside/has)

### Search with Rules (scan)

YAML rule-based search for complex structural queries:

```bash
# With rule file
ast-grep scan --rule my_rule.yml /path/to/project

# With inline rules
ast-grep scan --inline-rules "id: find-async
language: javascript
rule:
  kind: function_declaration
  has:
    pattern: await \$EXPR
    stopBy: end" /path/to/project

# JSON output
ast-grep scan --rule my_rule.yml --json /path/to/project
```

**When to use:**
- Complex structural searches
- Relational rules (inside, has, precedes, follows)
- Composite logic (all, any, not)
- When you need the power of full YAML rules

**Tip:** For relational rules (inside/has), always add `stopBy: end` to ensure complete traversal.

## Tips for Writing Effective Rules

### Always Use stopBy: end

For relational rules, always use `stopBy: end` unless there's a specific reason not to:

```yaml
has:
  pattern: await $EXPR
  stopBy: end
```

This ensures the search traverses the entire subtree rather than stopping at the first non-matching node.

**Scope-blindness caveat:** `stopBy: end` is purely structural — it does not respect lexical scope. A `not: { has: { kind: await_expression, stopBy: end } }` on an async arrow will also exclude that arrow if any *nested* async function inside it contains an `await`. ast-grep cannot natively express "no `await` whose nearest enclosing async function is THIS one" without metavariable backreferences across kinds. Pick one of: (a) accept the subtree-scoped semantics and disclose the limitation, (b) post-filter results in code, or (c) match the nested function kinds via `not: { has: { any: [arrow_function, function_declaration, ...], has: { kind: await_expression } } }` as an approximation.

### Start Simple, Then Add Complexity

Begin with the simplest rule that could work:
1. Try a `pattern` first
2. If that doesn't work, try `kind` to match the node type
3. Add relational rules (`has`, `inside`) as needed
4. Combine with composite rules (`all`, `any`, `not`) for complex logic

### Use the Right Rule Type

- **Pattern**: For simple, direct code matching (e.g., `console.log($ARG)`)
- **Kind + Relational**: For complex structures (e.g., "function containing await")
- **Composite**: For logical combinations (e.g., "function with await but not in try-catch")

### Debug with AST Inspection

When rules don't match:
1. Use `--debug-query=cst` to see how ast-grep parsed your **pattern string** (not the target file). To inspect a file's parse tree, use the ast-grep playground or `tree-sitter parse` — see "Discovering node `kind` names for a target file" above.
2. Check if metavariables are being detected correctly (`--debug-query=pattern`)
3. Verify the node `kind` matches what you expect (cross-reference the playground / your pattern's CST)
4. Ensure relational rules are searching in the right direction
5. If a kind name appears in your pattern's CST as `ERROR`, the node is likely child-only — see "Child-only node gotcha"

### Metavariable Forms

Pick the metavariable shape based on how many nodes you want to capture:

- `$NAME` — exactly one node (one identifier, one expression, one argument). Use for required slots.
- `$$$NAME` — zero or more sibling nodes. Use for argument lists, statement bodies, anything variadic. Example: `print($$$ARGS)` matches `print()`, `print(x)`, and `print(x, y, z)`; `print($X)` matches only `print(x)` (one arg) and misses bare `print()`.
- `$_` (anonymous) — match-anything wildcard with no capture.

When in doubt for arguments and bodies, prefer `$$$`. Use `$NAME` only when you specifically want to constrain to a single node.

### Escaping in Inline Rules

When using `--inline-rules`, escape metavariables in shell commands:
- Use `\$VAR` instead of `$VAR` (shell interprets `$` as variable)
- Or use single quotes: `'$VAR'` works in most shells

**Example:**
```bash
# Correct: escaped $
ast-grep scan --inline-rules "rule: {pattern: 'console.log(\$ARG)'}" .

# Or use single quotes
ast-grep scan --inline-rules 'rule: {pattern: "console.log($ARG)"}' .
```

## Common Use Cases

### Find Functions with Specific Content

Find async functions that use await:
```bash
ast-grep scan --inline-rules "id: async-await
language: javascript
rule:
  all:
    - kind: function_declaration
    - has:
        pattern: await \$EXPR
        stopBy: end" /path/to/project
```

### Find Code Inside Specific Contexts

Find console.log inside class methods:
```bash
ast-grep scan --inline-rules "id: console-in-class
language: javascript
rule:
  pattern: console.log(\$\$\$)
  inside:
    kind: method_definition
    stopBy: end" /path/to/project
```

### Find Code Missing Expected Patterns

Find async functions without try-catch:
```bash
ast-grep scan --inline-rules "id: async-no-trycatch
language: javascript
rule:
  all:
    - kind: function_declaration
    - has:
        pattern: await \$EXPR
        stopBy: end
    - not:
        has:
          pattern: try { \$\$\$ } catch (\$E) { \$\$\$ }
          stopBy: end" /path/to/project
```

## Resources

### references/
Contains detailed documentation for ast-grep rule syntax:
- `rule_reference.md`: Comprehensive ast-grep rule documentation covering atomic rules, relational rules, composite rules, and metavariables

Load these references when detailed rule syntax information is needed.
