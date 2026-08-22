---
name: provision-code-reader-parser
description: "Propose and, after explicit approval, provision a user-local Tree-sitter parser profile for a Code Reader walkthrough language that is not registered."
---

# Provision a Code Reader Parser Profile

Use this skill only when Code Reader reports `PROVISION_REQUIRED` for an unregistered language, or when the user asks to add a parser profile. Do not use it to update a built-in profile.

Before running a plugin Python script, read and follow `../../references/uv-runtime.md`.

## Workflow

1. Read `<plugin-root>/scripts/static_analysis_parser_catalog.json`. It is a checked-in review snapshot of the Tree-sitter parser list and supports grammar ABI 13 through 15. Do not fetch the Wiki during PDF generation or select packages dynamically from it.
2. Inspect the target language grammar and form a candidate JSON document using `code-reader-static-analysis-profile-candidate/v1`. Include the exact PyPI package and version, Python module, grammar symbol when needed, extensions, all static-metric node lists, function/type target-definition nodes, and the expected grammar ABI.
3. Present the candidate's parser source, package/version, expected ABI, and requested extension ownership to the user. Do not install a package, write a profile, or modify the explained project before the user explicitly approves this candidate.
4. After approval, place the candidate JSON in a temporary location outside the explained project and run:

```text
uv run --no-project <plugin-root>/scripts/provision_static_analysis_profile.py --candidate <candidate.json> --approve
```

5. The command installs an isolated runtime plus exactly one grammar package into the user static-analysis cache, probes the wheel ABI, and saves the profile only when its observed ABI matches the approved candidate and is within 13 through 15. It never changes the project or plugin profile files.
6. Rerun the Markdown validator or PDF renderer. If provisioning fails, report the structured reason and offer the existing manual `Target:` label override; never invent a target definition label.

## Candidate Rules

- Use only a pinned `tree-sitter-*` PyPI grammar package; do not pass a VCS URL, local path, or unpinned version to the provisioning command.
- One candidate owns one language id and non-overlapping file extensions. A profile must declare function and type target definition nodes as well as the metric node lists.
- The installed wheel's measured ABI is authoritative. A Wiki entry, grammar repository revision, or package name is not sufficient evidence by itself.
- To revise an already provisioned language, prepare a replacement candidate and ask the user before changing its user-local profile.
