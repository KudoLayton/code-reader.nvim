# Code Reader Markdown Format

Use this reference before writing any `code-reader.nvim` explanation markdown.

## Shared Rules

- Write explanation prose in the language the user primarily uses. If the user explicitly requests a language, use that language.
- Keep code identifiers, file paths, source ranges, diff refs, link targets, and protocol URLs exactly as they appear in the project.
- Users may provide references copied from code-reader.nvim with `:CodeReaderCopyRef`. Treat `path#Lx`, `path#Lx-Ly`, `path#Hn`, and `path#Hn@old/new:Lx-Ly` values as direct targets for the explanation unless the user asks to broaden or narrow the scope.
- Use YAML frontmatter at the top:

```markdown
---
type: code-reader
version: 1
---
```

- Separate every page or step with a line containing only `---`.
- Put `<!-- code-reader: front-page -->` as the first non-empty line of the first section.
- The front page must explain the problem, expected reader outcome, a concrete representative example, high-level structure, main module roles, and the reading flow before the detailed steps.
- Use Mermaid diagrams on the front page or individual steps when they clarify structure, control flow, data flow, or hunk impact.
- Prefer plain prose or lists instead of Mermaid when the user disabled Mermaid rendering or `:checkhealth code_reader` reports that Node, npm, or `beautiful-mermaid` is unavailable.
- Do not put `Source:` or `Diff:` references on the front page. Put references on concrete explanation pages.
- Use numeric heading ids for top-level and nested steps, such as `# 1. Request lifecycle`, `## 1.1. Parse request`, and `### 1.1.1. Validate method`.
- Heading depth on the first heading of each `---`-separated page drives TOC nesting. A numeric heading that follows the opening heading in the same page is invalid: give it its own `---` page. A non-numeric child heading is allowed only as conceptual organization for the same target code.
- Use `[[step-id]]` or `[[step-id|label]]` only for links to existing steps in the same explanation.
- Order pages by runtime execution flow, not source-file or diff order. When a scope contains a long routine or subroutine, use nested pages instead of making one broad page.
- A page's scope must contain only the code or change needed by that page's prose, diagrams, and links. Do not broaden a scope merely to make coverage look higher.

## Page Reference Preamble

Every concrete page has a metadata preamble immediately after its opening heading and before prose, diagrams, or child headings.

- A `type: code-reader` page has exactly one continuous `Source:` reference in that preamble. Its optional `Cursor:` reference must name the same path and stay inside that Source range.
- A `type: code-reader-diff` page has one or more `Diff:` references in that preamble. Multiple hunks are allowed only when every resolved range belongs to one logical definition. A rename is allowed only when the old and new ranges identify that same definition.
- A page must not contain an additional `Source:` or `Diff:` reference after the preamble, and a document type must not use the other reference kind.
- A page may explain a function, method, type, class, named declaration, or one top-level declaration or statement. It must not combine sibling definitions, multiple class members, or multiple top-level statements. A class container page is allowed only for its declaration or contract, not to explain several members.

## Code Explanation

- Use `type: code-reader`.
- Write the one source reference as `Source: path#Lx` or `Source: path#Lx-Ly`.
- Use optional `Cursor: path#Lx` when the explanation starts inside the Source range.
- Keep paths project-root relative and use `/` separators.
- Optional symbol links must include the source path:

```markdown
[handle](<treesitter://src/app.lua?query=(identifier) @code_reader.symbol>)
```

## Diff Explanation

- Use `type: code-reader-diff`.
- Add `diff: ./change.diff` in frontmatter. Resolve it relative to the markdown file.
- The front page should summarize the change set: purpose, behavioral impact, affected files or modules, and suggested review flow.
- Explain individual hunks in step pages, not on the front page.
- Use step-level Mermaid diagrams only when they make a specific hunk or cross-file relationship easier to review.
- Write references as `Diff: path#Hn`, where `Hn` is the file-local hunk number from the unified diff. A page may have more than one such reference only under the single-definition rule above.
- For large hunks or whole-file additions, split the explanation with side-specific focus ranges:
  - `Diff: path#Hn@old:L10-L18`
  - `Diff: path#Hn@new:L20-L40`
  - `@a` means old/before and `@b` means new/after.
- A side modifier declares the page's primary explanation target: use `@new` for post-change behavior and `@old` for removed or replaced pre-change behavior. Do not choose a side merely to make the displayed range smaller.
- When the page's central purpose is to compare the two versions rather than walk through one version, omit the side modifier (`Diff: path#Hn`) and describe the comparison explicitly.
- To include hunk-adjacent lines, prefer explicit hunk-relative bounds:
  - `Diff: path#Hn@new:L(-1)-L(+2)` means from one line before the new-side hunk start through two lines after the new-side hunk end.
  - `Diff: path#Hn@old:L(-1)-L22` mixes a relative start with an absolute end line.
  - `L-1-L22` is accepted as shorthand, but write `L(-1)-L22` by default.
- Use `padding=N` or `pad=N` when the same number of lines should be focused before and after the hunk: `Diff: path#Hn@new:padding=2`.
- Prefer covering every hunk in the diff unless the user asks for a partial explanation. When only part of a hunk belongs on a page, use a side-specific range and cover the remaining meaningful change in another page; do not claim whole-hunk coverage with an unnecessarily broad page.

## Static Page Metrics

Run the registered static-analysis bootstrap before asking a reviewer. It may install only dependencies named in the repository's language profile and lock; it must reject an unregistered dependency or a version that does not match the lock. Do not select, install, or upgrade a parser or analyzer ad hoc.

The page inventory records the analysis result for each resolved Source range and for both resolvable old/new Diff sides:

- `V(G)` is the deterministic cyclomatic complexity of the selected definition or structurally complete SESE subregion. The inventory includes its decision nodes and locations.
- `peak_live_bindings` is a deterministic local-binding proxy. Python and Lua profiles use backward lexical liveness; Tree-sitter profiles use profile-bound backward token liveness. It includes its peak location and binding names, but excludes heap/object fields, globals, aliases, and dynamic calls and may over- or under-count the reader's actual working-memory load. The static threshold is therefore a conservative split gate, not evidence that a lower value is safe.
- A Diff resolver first uses the old/new blob revision and path, then verifies hunk lines and context. For an unresolved side, the inventory records `hunk_fallback`, the attempted revision, and the reason instead of inventing a source range.

The writing agent must split and re-run static validation without requesting a reviewer when either of these conditions is true:

- `V(G) >= 12` or `peak_live_bindings >= 9`.
- Both `V(G) >= 11` and `peak_live_bindings >= 8`.

An unavailable profile, parser failure, unresolved Diff source, or a lone non-extreme static warning is not a pass. It is input to Page Scope Review.

## Page Scope Review v1

After static validation passes without an immediate split, ask one read-only subagent to perform Page Scope Review. Give it the project root, Markdown path, document type, page inventory, related source files or revisions, and the diff path with its complete `path#Hn` list when applicable. The subagent must not edit files.

The reviewer must inspect pages in document order and return exactly one YAML report in a fenced `yaml` block with this shape:

```yaml
schema: code-reader-page-scope-review/v1
document: relative/path/to/walkthrough.md
overall_verdict: PASS # PASS | CHANGES_REQUIRED
pages:
  - page_id: "1"
    refs: ["src/example.py#L10-L34"]
    resolution: source # source | diff_resolved | hunk_fallback
    definition:
      name: parse_request
      kind: function
      evidence: ["src/example.py#L10-L34"]
      single_definition: true
    headings:
      - text: "Input normalization"
        classification: conceptual # conceptual | scope_expanding
        counterfactual: "Removing this section would not narrow the Source range."
    focus_alignment: null # Required for Diff pages only.
    metrics:
      static:
        cyclomatic_complexity: 4
        peak_live_bindings: 3
      semantic:
        independent_concepts:
          count: 2
          items:
            - name: normalize request fields
              evidence: ["src/example.py#L12-L18"]
              rationale: "Defines the input contract before parsing."
        variable_value_pairs:
          count: 3
          peak_location: "src/example.py#L22"
          bindings:
            - name: method
              role: normalized input
              evidence: ["src/example.py#L12-L22"]
    triggered_rules: []
    verdict: PASS # PASS | SPLIT_REQUIRED | CHANGES_REQUIRED
    required_action: null
```

For every page, apply the following measurement procedure and record evidence in the report.

### Definition and child-heading scope

1. Verify that all resolved references lie inside one allowed definition. A hunk that crosses definitions must use a focused old/new range or become separate pages.
2. Evaluate every H2+ heading by removing that heading and its explanation hypothetically. If doing so allows the page's Source or resolved Diff scope to become smaller, classify it as `scope_expanding` and require a new `---` page. Headings that explain the same range's input, output, invariant, or control order are `conceptual`.
3. An unresolved Diff uses `hunk_fallback`: inspect the hunk body, context, and header only. If these do not establish one definition with sufficient confidence, return `CHANGES_REQUIRED`, never PASS.

### Diff focus-side alignment

For every Diff page, add this field to the page report:

```yaml
focus_alignment:
  declared_side: new # old | new | none
  described_side: new # old | new | comparison | undetermined
  evidence:
    - "The page walks through the newly added guard and its return value."
    - "The `@new` range contains the guard discussed in the central claim."
  verdict: MATCH # MATCH | MISMATCH | INSUFFICIENT_EVIDENCE
```

Determine `described_side` from the page's central explanatory claims, not from incidental comparison text. A page can mention the other version as context while still describing `new` or `old` as its primary target.

- `@new` matches only when the central walkthrough explains the post-change code, behavior, or state.
- `@old` matches only when the central walkthrough explains removed or replaced pre-change code or behavior.
- `none` matches only when the central walkthrough is a balanced old/new comparison. If a page is actually centered on one side, it must use that side's modifier instead.
- If focused references on one page declare conflicting sides, or the prose does not establish a primary target, return `INSUFFICIENT_EVIDENCE` rather than guessing. Split the page or make the comparison explicit with an unmodified hunk reference.

Set `MISMATCH` when `@old` is used to support a new-side walkthrough, `@new` is used to support an old-side walkthrough, or a side modifier is used for a genuinely comparative page. Set `INSUFFICIENT_EVIDENCE` when the central claim cannot be identified or the focused range does not contain the code needed to support it. Either result requires `CHANGES_REQUIRED`: change the modifier, clarify the prose, or split the page. This check is semantic review; it does not replace source-resolution or definition-boundary checks.

Review acceptance examples:

- A page centered on a newly added guard uses `@new` and may briefly contrast the old path: `MATCH`.
- A page explains the removed retry loop with `@old`: `MATCH`.
- A page explains a before/after behavioral difference with an unmodified `Diff: path#Hn`: `MATCH`.
- A page explains the new guard but declares `@old`: `MISMATCH` and `CHANGES_REQUIRED`.
- A page contains both sides but never states whether it explains a new behavior, old behavior, or comparison: `INSUFFICIENT_EVIDENCE` and `CHANGES_REQUIRED`.

### Independent concepts

Count one concept for each separate responsibility with its own answer to “what or why must the reader understand?” Record its name, code evidence, and why it is separate. Typical concepts include validation, state creation or mutation, transformation algorithm, branch policy, error/retry policy, I/O or persistence, protocol/integration, and concurrency/lifecycle.

- Do not count syntax, a helper calculation serving the same responsibility, or a sequence of calls that implements one state transition separately.
- Count `independent_concepts >= 5` as a normal violation and `>= 6` as an extreme violation.

### Variable--value pairs

At each cognitively demanding execution point--immediately before a branch, output, or side effect--list the bindings a reader must retain to predict what happens next. Use the highest count.

- Include parameters, locals, independently compared fields or keys, loop accumulators, and branch conditions.
- Count a plainly forwarded object once; count aliases separately when their distinct names must be tracked. Exclude clear constants, values irrelevant to the current result, and values fully externalized in a state table or diagram on the page.
- Record the peak location and, for every counted binding, its name, role, and source evidence. Report both the static proxy and semantic count; apply the larger value for the split policy so a static warning cannot be rationalized away.
- Count `variable_value_pairs >= 8` as a normal violation and `>= 9` as an extreme violation.

### Verdict rules

`SPLIT_REQUIRED` is mandatory when any one of the following applies:

- The page crosses a definition boundary or has a `scope_expanding` child heading.
- `V(G) >= 12`, independent concepts `>= 6`, or variable--value pairs `>= 9`.
- At least two normal violations: `V(G) >= 11`, independent concepts `>= 5`, and variable--value pairs `>= 8`.

For a resolved Diff, use the more demanding old/new measurement. For `hunk_fallback`, count only supported lower bounds; if a lower bound triggers a rule, require a split. A Diff `focus_alignment` verdict other than `MATCH`, an unknown safe definition boundary, or an unknown cognitive load requires `CHANGES_REQUIRED`. The writing agent fixes every non-PASS page, then re-runs the static validator and a fresh Page Scope Review until the report is `overall_verdict: PASS`.

For diff documents, the report must also include a `hunk_coverage` table and list uncovered hunks. All hunks remain required unless the user explicitly requested a partial explanation.

## Validation

Run the shared validator and emit an inventory after writing or editing a document. This command performs the registered, locked dependency bootstrap before collecting static metrics:

```powershell
python plugins/code-reader-authoring/scripts/validate_code_reader_markdown.py --project-root <repo-root> --emit-page-inventory <inventory.json> <markdown-file>
```

Use `--allow-partial-diff` only when the user explicitly wants a partial diff explanation.
