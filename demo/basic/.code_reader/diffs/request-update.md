---
type: code-reader-diff
version: 2
feature: request-update
diff: ./request-update.diff
---
# Overview
```code-reader
kind: overview
id: request-update
question: How does the patch turn a previously rejected PUT request into a created response?
state:
  status: not_applicable
  reason: The overview summarizes the patch narrative.
responsibility:
  status: applicable
  items:
    - owner: request lifecycle
      action: Preserve request identity, accept PUT, and report creation.
```

The patch removes unused context metadata, keeps request identity in the parsed data, extends the accepted-method policy, and changes the successful status to 201. Read the stages in runtime order rather than file order.

---
# 1. Remove unused context state
```code-reader
kind: stage
id: remove-context-metadata
question: Which lifecycle state stops being owned by app.handle?
trigger: app.handle builds its context for a request.
state:
  status: applicable
  changes:
    - subject: received_at metadata
      owner: app.handle
      before: fixed demo timestamp is stored in context
      cause: the field is deleted
      after: context contains only raw_request
      invariant: parsing still receives the same raw request.
responsibility:
  status: applicable
  items:
    - owner: app.handle
      action: Keep only context needed by downstream parsing.
failure:
  status: not_applicable
  reason: This deletion does not alter the branch or error contract.
evidence:
  - id: 1
    kind: diff
    target: src/app.lua#H1
    claim: The patch removes the unused received_at field without changing raw_request ownership.
```

The context reduction is shown in [1](code-reader://evidence/1).

---
# 2. Preserve request identity in parsed state
```code-reader
kind: stage
id: add-request-id
question: How does parsing retain the request identifier for later owners?
trigger: request.parse_request normalizes raw input.
state:
  status: applicable
  changes:
    - subject: parsed request
      owner: request.parse_request
      before: method, path, and user are retained
      cause: request_id default and return field are added
      after: parsed request also retains request_id
      invariant: path and user remain part of the returned request.
responsibility:
  status: applicable
  items:
    - owner: request.parse_request
      action: Preserve the request identity alongside normalized fields.
failure:
  status: not_applicable
  reason: request_id receives a deterministic default when absent.
evidence:
  - id: 1
    kind: diff
    target: src/request.lua#H1
    claim: The parsed request gains request_id while retaining the normalized path and user fields.
```

The parsed-state extension is [1](code-reader://evidence/1).

---
# 3. Accept PUT as a valid method
```code-reader
kind: stage
id: accept-put
question: Which validation policy allows the write-style request to proceed?
trigger: request.validate_request evaluates parsed.method.
state:
  status: applicable
  changes:
    - subject: validation result for PUT
      owner: request.validate_request
      before: PUT produces unsupported method failure
      cause: PUT is added to the accepted-method condition
      after: PUT reaches the success branch
      invariant: unsupported methods still produce the existing problem.
responsibility:
  status: applicable
  items:
    - owner: request.validate_request
      action: Define which request methods may reach response rendering.
failure:
  status: applicable
  outcomes:
    - cause: method remains outside GET, POST, and PUT
      result: return false with unsupported method.
evidence:
  - id: 1
    kind: diff
    target: src/request.lua#H2
    claim: PUT joins the accepted methods while the rejection path remains intact.
```

The policy change is [1](code-reader://evidence/1).

---
# 4. Report creation at the response boundary
```code-reader
kind: stage
id: return-created
question: How does the successful response represent the accepted write-style request?
trigger: app.handle selects response.render_response after validation succeeds.
state:
  status: applicable
  changes:
    - subject: success response status
      owner: response.render_response
      before: successful requests report HTTP 200
      cause: status_line receives 201
      after: successful requests report HTTP 201
      invariant: body construction and shared status formatting stay unchanged.
responsibility:
  status: applicable
  items:
    - owner: response.render_response
      action: Expose the created outcome at the transport boundary.
failure:
  status: not_applicable
  reason: Validation selected the success response before this stage.
evidence:
  - id: 1
    kind: diff
    target: src/response.lua#H1
    claim: The response status changes to 201 without changing the response body contract.
```

The created response evidence is [1](code-reader://evidence/1).
