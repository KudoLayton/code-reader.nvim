---
name: read-code-review-comments
description: "Read Code Reader review-comment sidecars, connect each comment to its walkthrough stage and exact source or diff range, and use the feedback for requested review or resolution work."
---

# Read Code Reader Review Comments

Use this skill when the user asks to inspect, summarize, address, or resolve review comments collected through Code Reader. Do not use it to author a walkthrough that has no review comments.

Read `../../references/code-review-comment-format.md` before locating or interpreting comment files.

1. If a walkthrough Markdown path is given, replace its `.md` suffix with `.reviews.jsonl` and read that sidecar. If the request is project-wide, discover `.code_reader/**/*.reviews.jsonl` files.
2. Parse every non-empty JSONL line independently. Keep the original comment text intact. Report malformed lines with their file and line number; do not invent a replacement record.
3. For each valid record, open its `walkthrough`, locate `stage_id` and `evidence_id` when present, then inspect the referenced current source range or diff hunk. Distinguish a comment that still maps cleanly from a missing, moved, or ambiguous reference.
4. Present comments grouped by walkthrough and stage. For each comment, show its code reference, the user feedback, the relevant implementation context, and whether the reference is still resolvable.
5. Reading or summarizing comments does not authorize edits. When the user asks to resolve comments, treat each resolvable record as the user-provided review requirement; explain any interpretation that is not explicit in the comment before changing code or walkthrough content.

The sidecar is append-only feedback, not walkthrough evidence. Never rewrite, delete, or mark entries resolved unless the user explicitly asks for that record-management operation.
