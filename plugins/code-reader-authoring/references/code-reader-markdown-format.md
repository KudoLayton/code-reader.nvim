# Code Reader Markdown v2

Use this reference before authoring or reviewing a Code Reader walkthrough. Markdown is the canonical document. The PDF renderer uses HTML internally, but neither PDF export nor reading a document contacts an MCP server.

## Document contract

Use frontmatter with `type: code-reader` or `type: code-reader-diff`, `version: 2`, and a stable `feature` id. Diff documents also declare `diff: ./change.diff` relative to the Markdown file.

Separate sections with `---`. Each section begins with a `code-reader` fenced YAML block. The first section has `kind: overview`; later sections normally use `kind: stage` or, when necessary, `kind: model`. Every overview, stage, and model has an `id`, a reader-facing `question`, `state`, and `responsibility`. Every stage additionally has a `trigger`, `failure`, and ordered `evidence` list.

Write for the reader route, not source-file order: **execution map → key step → semantic bullets → source or diff proof**. The overview gives the execution space; stages explain the few decisions that change state, ownership, or outcome. A reader must be able to answer “How is this feature implemented?” before opening a source range.

````markdown
---
type: code-reader
version: 2
feature: request-flow
---
# Overview
```code-reader
kind: overview
id: request-flow
question: What happens to a request?
state:
  status: not_applicable
  reason: The overview does not execute.
responsibility:
  status: applicable
  items:
    - owner: app.handle
      action: Coordinate the lifecycle
evidence:
  - id: 1
    kind: sketch
    purpose: execution-map
    target: .code_reader/assets/request-flow.svg
    editable_target: .code_reader/assets/request-flow.excalidraw
    claim: The map aggregates the request lifecycle into its key decisions and outcomes.
    coverage:
      - parse-input
    text_model:
      claim: Raw input becomes either a successful response or an error response.
      nodes:
        - id: raw
          label: Raw request
          owner: app.handle
          state: raw
        - id: response
          label: Response
          owner: response
          state: rendered
      edges:
        - id: parse-and-render
          from: raw
          to: response
          label: parse, validate, and render
```
---
# 1. Parse input
```code-reader
kind: stage
id: parse-input
map_anchor:
  map: 1
  nodes:
    - raw
  edges:
    - parse-and-render
question: How does raw input become a request?
trigger: app.handle receives raw input
state:
  status: applicable
  changes:
    - subject: request
      owner: request.parse
      before: raw
      cause: parser runs
      after: decoded
      invariant: defaults are present
responsibility:
  status: applicable
  items:
    - owner: request.parse
      action: Normalize optional fields
failure:
  status: not_applicable
  reason: Missing optional fields receive defaults.
evidence:
  - id: 1
    kind: source
    target: src/request.lua#L3-L13
    claim: Parsing creates the decoded request.
```
The transition is implemented in [1](code-reader://evidence/1).
````

The prose explains the mechanism, consequence, and reader decision. It must not restate the entire source range. Evidence ids begin at 1 in each section, have no gaps, and every id appears in a `code-reader://evidence/<id>` Markdown link in that section.

## Atomic state transitions

`state.status: applicable` requires a non-empty `changes` list. Each list item is one rendered state card and must name exactly one state bearer, one owner, and that bearer's own `before`, `cause`, `after`, and `invariant`. A stage may contain multiple cards without becoming multiple pages.

Do not merge independently changing data merely because one function touches it or one stage explains it. Split a change when its state bearer, owner, lifecycle, invariant, or evidence rationale can differ. In particular, never use a list or conjunction in `subject` or `owner` to summarize separate transitions.

```yaml
# Invalid: request and validation_cache have independent owners and lifecycles.
changes:
  - subject: request and validation_cache
    owner: parser and cache.store
    before: raw and empty
    cause: parsing stores a result
    after: decoded and populated
    invariant: defaults and cache membership hold

# Valid: both cards can remain on the same explanation page.
changes:
  - subject: request
    owner: parser
    before: raw
    cause: parsing runs
    after: decoded
    invariant: defaults are present
  - subject: validation_cache
    owner: cache.store
    before: empty
    cause: the validation result is stored
    after: populated
    invariant: the entry belongs to the request
```

A domain aggregate remains one valid subject when it has one owner and one lifecycle. Its `before` and `after` may describe several coupled fields, provided they are all state of that aggregate. For example, `subject: request` may move from `raw fields, mode unset` to `decoded and normalized`; it must not conceal a separate cache, response, session, or owner handoff.

Use three to seven stages for the normal path. Aggregate mechanical operations under the decision they serve, but never aggregate independent state cards. For a repeated operation, show its first occurrence, last outcome, and the rule that makes the middle occurrences equivalent; do not spend a stage on each repetition. Split a stage only when the reader question, state transition, owner, or outcome changes.

## Scope reviews and conceptual hierarchy

Code-range splitting is a review signal, not an automatic page break. When a source or diff scope is split, or when one stage contains two or more code evidence entries, decide why the original reader scope was too large before arranging the pages:

- `model_gap`: a short explanation cannot prepare the mental model needed to read every range.
- `explanation_overload`: the necessary explanation itself contains too many independent rules, entities, or branches to scan as one page.
- `implementation_complexity`: the explanation remains one small model, but boilerplate, framework mechanics, or avoidable structure make its code long.

Record the decision in the overview's `scope_reviews`. A `model_gap` or `explanation_overload` diagnosis requires `page_decision: split`. `implementation_complexity` may retain multiple ranges on one stage; label each range's local role rather than replacing the model with a long paraphrase. Every source/diff evidence entry on a multi-range stage must appear in a review member list.

```yaml
scope_reviews:
  - id: request-validation
    signal: split_required # split_required | multiple_scopes
    members:
      - stage: parse-request
        evidence: 1
      - stage: check-policy
        evidence: 1
    diagnoses:
      - model_gap
    page_decision: split # retain | split
    hierarchy: validation-model # none | model id
    rationale: Parsing and policy establish one request contract, but each needs a separate local model.
```

Use a model page only when the separated pages collectively implement one responsibility and the parent gives non-repeated context that a child cannot stand in for. A model page has no required runtime evidence and is not an execution-map stage. It declares its common contract and why its children are separate; every direct child sets the explicit `parent` id. Model parents may nest at most two levels below the overview and need at least two children.

```yaml
kind: model
id: validation-model
question: How do parsing and policy jointly establish a dispatchable request?
state:
  status: not_applicable
  reason: This page summarizes its child stages.
responsibility:
  status: applicable
  items:
    - owner: request validation
      action: Establish the request contract
hierarchy:
  contract: A validated request is safe to dispatch.
  decomposition: Parsing and policy have independent local rules.
```

```yaml
kind: stage
id: parse-request
parent: validation-model
```

Do not introduce a model page solely because steps are sequential (`parse → validate → dispatch`) or because it would only repeat the child summaries. Use `hierarchy: none` for that flat route.

## Evidence and diagrams

- `source` targets one project-relative `path#Lx-Ly` range. Use `cursor` only to select a line inside that range.
- `diff` targets one `path#Hn`, optionally with an `@old` or `@new` focused range. Explain every hunk unless partial coverage is requested.
- `sketch` is for a relationship that prose or a simple Mermaid flow would hide: three or more interacting responsibilities, a non-linear branch, or a state/ownership handoff that needs spatial comparison.

Use a sketch `purpose` to declare the reader question it answers:

- `execution-map`: the overview's key execution steps, branches, and outcomes. It is the default opening evidence. It belongs only in `kind: overview` and requires `coverage` listing every stage id it represents.
- `handoff-map`: an ownership handoff among collaborating modules or data owners.
- `state-map`: a finite lifecycle whose valid transitions matter more than the fields of one transition.
- `structure-map`: a static boundary or dependency relationship needed to orient the reader.

Do not force a diagram into every stage. Use a source/diff range when the relationship is already local and linear. Use a table only for a compact exact comparison; Code Reader renders state and responsibility models as labelled bullet cards rather than wide prose tables.

A sketch keeps an editable Excalidraw scene and a display SVG together:

```yaml
- id: 2
  kind: sketch
  purpose: handoff-map
  target: .code_reader/assets/request-flow.svg
  editable_target: .code_reader/assets/request-flow.excalidraw
  claim: Ownership transfers after validation.
  text_model:
    claim: The validated request moves from parser to dispatcher.
    nodes:
      - id: raw
        label: Raw request
        owner: app.handle
        state: raw
      - id: validated
        label: Validated request
        owner: dispatcher
        state: validated
    edges:
      - from: raw
        to: validated
        label: validate
```

`target` and `editable_target` are project-root-relative paths. `target` is an SVG preview used by Neovim and PDF. `editable_target` is a JSON `.excalidraw` scene. `text_model` is mandatory even when the SVG is visible; it is the accessible text equivalent and the fallback reader view.

For an execution map, add stage coverage:

```yaml
purpose: execution-map
coverage:
  - parse-input
  - validate-request
```

Coverage identifies explained stages, not necessarily one SVG node per stage. The map may aggregate adjacent operations, but it must make the branch or outcome that distinguishes them readable.

### Stage position anchors

An execution map also gives every runtime stage a stable reader position. Its `text_model.nodes[].id` and `text_model.edges[].id` are the anchor namespace: execution-map edge ids are required and must be unique. A covered stage declares the map evidence id plus the node and/or edge ids that describe its current scope. A model page is conceptual rather than runtime: it is excluded from execution-map coverage and instead shows its conceptual path, direct child scopes, and common contract.

```yaml
map_anchor:
  map: 1
  nodes:
    - validated-request
  edges:
    - validation-result
```

The Neovim explanation pane renders this as a compact text minimap below the page title. The PDF renders a derived semantic minimap in the same place: only nodes named directly in `map_anchor.nodes` are high-contrast; selected edges are high-contrast transitions; their endpoints plus immediate incoming handoffs and outgoing outcomes are secondary. The rest of the execution graph stays muted for context. The original SVG remains unchanged and still appears as overview evidence.

When one execution map exists and a stage id exactly equals one map node id, the anchor may be omitted and is inferred. Otherwise `map_anchor` is required for every covered stage. With multiple execution maps, always set `map`; the selected map must list that stage in `coverage`. Validation rejects unknown map, node, or edge ids and execution maps whose combined coverage misses a runtime stage.

Use Mermaid for a compact, single-owner linear flow. Prefer a labelled spatial sketch for ownership transfer, an alternate branch, a state lifecycle, or a static boundary. Do not create a sketch solely to decorate a document.

## Excalidraw MCP workflow

When a sketch is needed, use the packaged `excalidraw` MCP server or `npx -y mcp-excalidraw-server@2.0.0`. Work locally; do not use a share/upload command unless the user explicitly asks.

1. Create or import the `.excalidraw` scene under `.code_reader/assets/`.
2. Inspect the scene with the MCP description and, with a local canvas tab open, inspect a screenshot for overlap, clipped labels, arrow direction, state labels, and ownership labels.
3. Export the unchanged scene as the `.excalidraw` editable target and export a SVG screenshot as the `target` preview.
4. Update `text_model` so its claim, nodes, owners, states, and edges agree with the scene.
5. Run the validator. If the MCP or a canvas tab is unavailable, use Mermaid or labelled bullet cards instead of adding incomplete sketch evidence.

## Whole-document review

After validation, use one read-only `code_reader_document_reviewer` configured from `code-reader-document-reviewer.toml`. Supply the Markdown file, inventory, referenced source/diff material, and sketch assets. The reviewer returns one fenced YAML report with this shape:

```yaml
schema: code-reader-document-review/v2
document: .code_reader/walkthrough.md
overall_verdict: PASS # PASS | CHANGES_REQUIRED
stages:
  - id: parse-input
    question_answered: true
    state_and_ownership: PASS
    evidence_alignment: PASS
    cognitive_load: PASS
    scope_structure: PASS
    required_action: null
document_flow: PASS
sketch_accessibility: PASS
```

Review the whole runtime narrative: entry to outcome, whether the execution map covers every runtime stage, whether each stage anchor resolves to the intended current scope and immediate handoffs, key-step aggregation, repetition abbreviation, state transitions, ownership handoffs, errors or non-applicability, evidence order, source/diff coverage, and whether a sketch agrees with its text model. Review every scope decision against the code: A/B diagnoses must have been split, C must preserve a compact model, and a model parent must add a shared contract rather than repeat child prose. Fix every `CHANGES_REQUIRED`, revalidate, then obtain a fresh whole-document report.

## Validation

```powershell
uv run --no-project plugins/code-reader-authoring/scripts/validate_code_reader_markdown.py --project-root <repo-root> --emit-page-inventory <inventory.json> <markdown-file>
```

Use `--allow-partial-diff` only when the user explicitly requests partial diff coverage. The validator checks the v2 contract, evidence links, source scopes, diff hunk coverage, scope-review decisions, explicit model hierarchy, SVG preview, Excalidraw scene, sketch text model, execution-map coverage, and stage anchors.
