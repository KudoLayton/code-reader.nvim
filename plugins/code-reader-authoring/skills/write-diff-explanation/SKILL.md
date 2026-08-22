---
name: write-diff-explanation
description: "Create or revise map-first v2 Code Reader diff walkthrough Markdown that explains behavioral changes as key execution steps, state/ownership bullets, and linked diff evidence. Use for unified diffs and patch explanations."
---

# Write Diff Explanation

Read `../../references/code-reader-markdown-format.md` before writing. Before running a plugin Python script, read and follow `../../references/uv-runtime.md`.

1. Inspect the complete unified diff and affected code before drafting. Identify changed behavior, state/ownership changes, failures, repetitions, all file-local hunk ids, and runtime order.
2. Write `type: code-reader-diff`, `version: 2`, `feature`, and `diff`. Begin with an overview; then create stages in behavioral order rather than patch order.
3. When the changed execution space is not obvious, add an overview `execution-map` sketch with `coverage` for every stage. Give its text-model nodes and edges stable ids, then anchor every covered stage with `map_anchor` to its current node and/or edge (except exact stage-id-to-node inference for a single map). Aggregate related hunks into the reader's key decisions and abbreviate repeated edits with their shared rule.
4. Give every stage a question, trigger, state model, responsibility owner, failure model, and numbered diff evidence. The renderer presents state and responsibility as labelled bullets; use short field values. Use one `path#Hn` target per evidence item; use `@old` or `@new` focused ranges only when that side is the stage's primary story.
5. Cover every changed hunk unless the user explicitly asks for partial coverage. When a hunk scope is split or a stage contains multiple diff/source evidence entries, record the A/B/C diagnosis in overview `scope_reviews`: `model_gap` and `explanation_overload` require page splits; `implementation_complexity` may retain a compact common explanation.
6. Use a model parent only when split child stages jointly implement one responsibility and require a non-repeated shared contract. Declare `kind: model`, `hierarchy.contract`, and `hierarchy.decomposition`, then give every child an explicit `parent`. Keep merely sequential patch steps flat and limit model nesting to two levels below the overview.
7. Use Mermaid for a compact, single-owner linear flow. Use a purpose-labelled sketch only for a branch, ownership handoff, lifecycle, or static boundary that spatial comparison makes clearer. Build and verify it through the packaged third-party Excalidraw MCP workflow, then retain `.excalidraw`, SVG, and matching `text_model`.
8. Run the shared validator with `--emit-page-inventory`. Fix missing hunk coverage, incomplete execution-map coverage, unresolved stage anchors, invalid evidence links, invalid scope reviews or model hierarchy, and model/asset errors before review.
9. Use one configured read-only `code_reader_document_reviewer` for a whole-document v2 review. Fix every `CHANGES_REQUIRED`, validate again, and obtain a fresh report.

Store new diff explanations and their patches under `.code_reader/diffs/` unless the user requests another location. Do not guess hunk ids or claim behavior not supported by the patch.
