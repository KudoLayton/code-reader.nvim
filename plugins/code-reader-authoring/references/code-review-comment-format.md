# Code Reader review comment format

Code Reader stores review comments separately from walkthrough Markdown. A walkthrough at:

```text
.code_reader/flow.md
```

has an append-only JSON Lines sidecar at:

```text
.code_reader/flow.reviews.jsonl
```

For a diff walkthrough, use the same replacement beside the Markdown file, for example `.code_reader/diffs/change.md` becomes `.code_reader/diffs/change.reviews.jsonl`.

Each non-empty line is one JSON object:

```json
{
  "version": 1,
  "walkthrough": ".code_reader/flow.md",
  "stage_id": "validate-request",
  "evidence_id": 2,
  "kind": "source",
  "reference": "src/request.lua#L18-L31",
  "comment": "Explain why this branch owns normalization.",
  "created_at": "2026-08-22T10:15:30Z"
}
```

`evidence_id` is optional when the visible source or diff range does not correspond to a declared evidence item. All other fields are required.

- `kind` is `source` or `diff`.
- Source references use `path#Lx` or `path#Lx-Ly`.
- Diff references use `path#Hn@old|new` with an optional `:Lx` or `:Lx-Ly` focused range.
- `walkthrough` is relative to the Code Reader project root; `reference` is also relative to that root.
- `comment` is the exact user-entered Markdown text. Preserve its meaning and line breaks when reporting or acting on it.

Do not place comments in walkthrough metadata, evidence claims, or source files. A review sidecar records feedback; it does not assert that the walkthrough or code has been changed to resolve it.

When reading comments, load the matching walkthrough, resolve its stage/evidence context, then inspect the referenced current source or diff range. Report malformed JSON lines and unresolved paths, ranges, or hunks rather than silently dropping them.
