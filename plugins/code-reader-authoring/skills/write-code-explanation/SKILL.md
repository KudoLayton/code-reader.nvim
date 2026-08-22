---
name: write-code-explanation
description: "Create or revise map-first v2 Code Reader feature walkthrough Markdown that explains a feature as key execution steps, state/ownership bullets, and linked source evidence. Use for code paths, modules, request flows, and implementation explanations."
---

# Write Code Explanation

Read `../../references/code-reader-markdown-format.md` before writing.

1. Inspect the feature entry point, participating modules, data/state, ownership boundaries, error paths, repetitions, and runtime order. Start from the reader question: “How is this feature implemented?”
2. Write `type: code-reader`, `version: 2` Markdown in reader order: execution map, key step, semantic bullets, then source proof. Do not turn source-file order into reading order.
3. In the overview, add an `execution-map` sketch when a map makes the execution space clearer. Its `coverage` lists every stage id; its `text_model` has stable node ids and stable edge ids. For every covered stage, add `map_anchor` selecting the current node and/or edge. Omit it only when exactly one execution map has a node whose id exactly equals the stage id. Aggregate adjacent mechanical operations into three to seven key steps; summarize repetitions with their rule and outcome.
4. For each stage, state the question, trigger, state transition or non-applicability, responsibility owner, failure behavior or non-applicability, then link its numbered evidence in the prose. The renderer turns these into labelled bullet cards; keep each value atomic rather than writing a paragraph in a field.
5. Use source evidence for exact implementation ranges. Split a stage only when its question, state transition, owner, or outcome changes; do not use a broad range merely to cover related code.
6. Use Mermaid for a small, single-owner linear flow. Use a purpose-labelled sketch only when spatial comparison helps show a branch, three or more responsibilities, a state lifecycle, or an ownership handoff. When using a sketch, drive the packaged third-party Excalidraw MCP or its CLI, preserve `.excalidraw` plus SVG, and keep `text_model` equivalent to the scene. Do not add a sketch if its MCP/canvas export cannot be completed.
7. Run the shared validator with `--emit-page-inventory`. Resolve invalid evidence, incomplete execution-map coverage, unresolved stage anchors, missing state/ownership, uncovered code, and asset errors before review.
8. Use one configured read-only `code_reader_document_reviewer` for a whole-document v2 review. Fix every `CHANGES_REQUIRED`, then rerun validation and a fresh review.

Store a new walkthrough under `.code_reader/` unless the user requests another path. Use the user's primary language for explanatory prose. Never invent source ranges, states, or ownership.
