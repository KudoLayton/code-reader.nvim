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
# 2. Preserve request path near user data

Diff: `src/request.lua#H1@new:L(-1)-L8`

The `path` assignment is moved below `user`, keeping the returned path close to the user data that appears with it. This step uses a partial range inside a larger hunk so the explanation stays focused.

---
# 3. Add request id with padding

Diff: `src/request.lua#H1@new:padding=1`

The same hunk also adds `request_id` to the parsed request and returned table. The padding range focuses one line around the hunk while the side-by-side view keeps the comparable file visible.

---
# 4. Allow PUT requests

Diff: `src/request.lua#H2`

The validation condition keeps the existing `GET` and `POST` behavior, then adds `PUT` as another accepted method. This is a single-line modification, so both sides are marked with `~` and the changed span is highlighted inline.

---
# 5. Return created status

Diff: `src/response.lua#H1`

The success response changes from `200` to `201`, matching the new write-style request that the validation step now accepts.
