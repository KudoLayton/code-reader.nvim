---
type: code-reader-diff
version: 1
diff: ./request-update.diff
---

<!-- code-reader: front-page -->
# Diff Demo Overview

This diff walkthrough explains a small API behavior change. The patch allows `PUT` requests through validation and changes successful responses to report a created status.

Use this demo to inspect the side-by-side diff view, automatic full-file expansion, hunk navigation, and changed-line coverage.

---
# 1. Allow PUT requests

Diff: `src/request.lua#H1`

The validation condition keeps the existing `GET` and `POST` behavior, then adds `PUT` as another accepted method. Unsupported methods still return the same error string.

---
# 2. Return created status

Diff: `src/response.lua#H1`

The success response changes from `200` to `201`, matching the new write-style request that the validation step now accepts.
