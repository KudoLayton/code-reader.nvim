---
type: code-reader-diff
version: 1
diff: ./request-update.diff
---

<!-- code-reader: front-page -->
# Diff Demo Overview

This diff walkthrough explains a small API behavior change. The patch removes unused request context metadata, preserves a request path while moving it closer to the returned data, adds a request id, allows `PUT`, and changes successful responses to report a created status.

Use this demo to inspect the side-by-side diff view, gutter markers, inline modified spans, moved-line detection, and changed-line coverage.

---
# 1. Remove unused context metadata

Diff: `src/app.lua#H1`

The context no longer stores the fixed demo timestamp. This is a pure deletion, so the before side is marked with `-` and the after side has a filler line.

---
# 2. Preserve request path with request id

Diff: `src/request.lua#H1`

The `path` assignment is moved below `user`, and a new `request_id` field is added. The side-by-side view should mark the moved `path` line with `>` and the new request id lines with `+`.

---
# 3. Allow PUT requests

Diff: `src/request.lua#H2`

The validation condition keeps the existing `GET` and `POST` behavior, then adds `PUT` as another accepted method. This is a single-line modification, so both sides are marked with `~` and the changed span is highlighted inline.

---
# 4. Return created status

Diff: `src/response.lua#H1`

The success response changes from `200` to `201`, matching the new write-style request that the validation step now accepts.
