#!/usr/bin/env python
"""Probe one isolated Tree-sitter runtime and grammar package for ABI compatibility."""

from __future__ import annotations

import argparse
import importlib
import json
import sys
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--site-packages", required=True)
    parser.add_argument("--grammar-module", required=True)
    parser.add_argument("--grammar-symbol", default="language")
    args = parser.parse_args()

    sys.path.insert(0, str(Path(args.site_packages)))
    try:
        import tree_sitter
        from tree_sitter import Language

        grammar = importlib.import_module(args.grammar_module)
        language = Language(getattr(grammar, args.grammar_symbol)())
        grammar_abi = getattr(language, "abi_version", getattr(language, "version", None))
        minimum = getattr(tree_sitter, "MIN_COMPATIBLE_LANGUAGE_VERSION", None)
        maximum = getattr(tree_sitter, "LANGUAGE_VERSION", None)
        if not all(isinstance(value, int) for value in (grammar_abi, minimum, maximum)):
            raise RuntimeError("Tree-sitter bindings do not expose language ABI metadata")
    except Exception as error:
        print(json.dumps({"status": "NOT_AVAILABLE", "reason": str(error)}, ensure_ascii=False))
        return 0

    print(
        json.dumps(
            {
                "status": "READY",
                "runtime_abi": {"minimum": minimum, "maximum": maximum},
                "grammar_abi": grammar_abi,
            },
            ensure_ascii=False,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
