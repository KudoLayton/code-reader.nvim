---
type: code-reader
version: 2
feature: request-flow
---
# Overview
```code-reader
kind: overview
id: request-flow
question: How does a raw request become a success or error response?
state:
  status: not_applicable
  reason: The overview introduces the runtime model.
responsibility:
  status: applicable
  items:
    - owner: app.handle
      action: Coordinate parsing, validation, and response rendering.
evidence:
  - id: 1
    kind: sketch
    purpose: execution-map
    target: .code_reader/assets/request-flow.svg
    editable_target: .code_reader/assets/request-flow.excalidraw
    claim: The map aggregates request handling into parsing followed by validation and response rendering.
    coverage:
      - coordinate-lifecycle
      - parse-request
      - validate-request
      - render-success
      - render-error
    text_model:
      claim: app.handle passes a raw request to parsing, then the normalized request reaches response rendering after validation.
      nodes:
        - id: raw-request
          label: Raw request
          owner: app.handle
          state: raw
        - id: parsed-request
          label: Parsed request
          owner: request.parse_request
          state: decoded
        - id: response
          label: Response
          owner: response module
          state: rendered
      edges:
        - id: parse
          from: raw-request
          to: parsed-request
          label: parse
        - id: validate-and-render
          from: parsed-request
          to: response
          label: validate + render
```

The execution map [1](code-reader://evidence/1) first shows the ownership path. The following stages unpack its five reader decisions: coordinate, normalize, validate, then render one of two outcomes.

---
# 1. Coordinate the request lifecycle
```code-reader
kind: stage
id: coordinate-lifecycle
map_anchor:
  map: 1
  edges:
    - parse
    - validate-and-render
question: Where is the complete request process coordinated?
trigger: app.handle receives raw_request.
state:
  status: not_applicable
  reason: app.handle coordinates parsing and validation; their separately owned state transitions are explained by the following stages.
responsibility:
  status: applicable
  items:
    - owner: app.handle
      action: Sequence collaborators and choose the success or error branch.
failure:
  status: applicable
  outcomes:
    - cause: validation returns false
      result: render_error receives the validation problem.
evidence:
  - id: 1
    kind: source
    target: src/app.lua#L13-L23
    claim: app.handle creates the parsed request, branches on validation, and selects the response renderer.
```

The lifecycle coordinator is [1](code-reader://evidence/1). The overview map remains the high-level ownership reference, so this stage can focus on the source-level branch.

---
# 2. Normalize optional request data
```code-reader
kind: stage
id: parse-request
map_anchor:
  map: 1
  nodes:
    - parsed-request
  edges:
    - parse
question: How do optional raw fields become a predictable request value?
trigger: app.handle passes context.raw_request to request.parse_request.
state:
  status: applicable
  changes:
    - subject: request
      owner: request.parse_request
      before: method, path, and user may be absent
      cause: fallback values are applied
      after: decoded table contains all three fields
      invariant: later stages can read method, path, and user without nil checks.
responsibility:
  status: applicable
  items:
    - owner: request.parse_request
      action: Define the normalized request contract.
failure:
  status: not_applicable
  reason: Missing optional fields receive defaults instead of failing parsing.
evidence:
  - id: 1
    kind: source
    target: src/request.lua#L3-L13
    claim: parse_request supplies defaults and returns the normalized table.
```

The normalization contract is implemented in [1](code-reader://evidence/1).

---
# 3. Reject unsupported or incomplete requests
```code-reader
kind: stage
id: validate-request
map_anchor:
  map: 1
  nodes:
    - parsed-request
  edges:
    - validate-and-render
question: Which conditions decide whether rendering may continue?
trigger: request.validate_request receives the normalized request.
state:
  status: applicable
  changes:
    - subject: validation result
      owner: request.validate_request
      before: decoded request is unclassified
      cause: method and path guards execute
      after: true or false with an optional problem
      invariant: false always carries a human-readable reason.
responsibility:
  status: applicable
  items:
    - owner: request.validate_request
      action: Enforce supported methods and non-empty paths.
failure:
  status: applicable
  outcomes:
    - cause: method is unsupported or path is empty
      result: return false and a problem for app.handle.
evidence:
  - id: 1
    kind: source
    target: src/request.lua#L15-L25
    claim: validate_request turns boundary violations into a boolean and problem pair.
```

The guard conditions and failure result are [1](code-reader://evidence/1).

---
# 4. Render the valid response
```code-reader
kind: stage
id: render-success
map_anchor:
  map: 1
  nodes:
    - response
  edges:
    - validate-and-render
question: How is a validated request exposed as a successful response?
trigger: app.handle receives ok equal to true.
state:
  status: applicable
  changes:
    - subject: response
      owner: response.render_response
      before: parsed request is validated but unrendered
      cause: render_response formats status and body
      after: HTTP 200 greeting response
      invariant: status formatting is delegated to status_line.
responsibility:
  status: applicable
  items:
    - owner: response.render_response
      action: Build the success response from normalized request data.
failure:
  status: not_applicable
  reason: Validation has already selected the success branch.
evidence:
  - id: 1
    kind: source
    target: src/response.lua#L7-L12
    claim: render_response builds a shared-format 200 response from parsed fields.
```

The success response construction is [1](code-reader://evidence/1).

---
# 5. Render the validation error
```code-reader
kind: stage
id: render-error
map_anchor:
  map: 1
  nodes:
    - response
  edges:
    - validate-and-render
question: How does a failed validation become an observable error response?
trigger: app.handle receives ok equal to false and a problem.
state:
  status: applicable
  changes:
    - subject: response
      owner: response.render_error
      before: validation problem has no transport representation
      cause: render_error formats status and body
      after: HTTP 400 error response
      invariant: the original problem remains visible in the body.
responsibility:
  status: applicable
  items:
    - owner: response.render_error
      action: Translate the validation problem into the error response shape.
failure:
  status: not_applicable
  reason: This stage is the selected alternate outcome.
evidence:
  - id: 1
    kind: source
    target: src/response.lua#L14-L19
    claim: render_error preserves the problem while producing the shared-format 400 response.
```

The alternate response construction is [1](code-reader://evidence/1).
