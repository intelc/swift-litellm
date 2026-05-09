#!/usr/bin/env python3
"""Sync LiteLLM model/provider metadata into Swift package resources."""

from __future__ import annotations

import argparse
import json
import subprocess
import urllib.request
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
RESOURCE_DIR = ROOT / "Sources" / "LiteLLM" / "Resources" / "metadata"
FILES = ["model_prices_and_context_window.json", "provider_endpoints_support.json"]


def read_from_clone(litellm_dir: Path, name: str) -> str:
    return (litellm_dir / name).read_text(encoding="utf-8")


def read_from_github(ref: str, name: str) -> str:
    url = f"https://raw.githubusercontent.com/BerriAI/litellm/{ref}/{name}"
    with urllib.request.urlopen(url, timeout=30) as response:
        return response.read().decode("utf-8")


def commit_for_clone(litellm_dir: Path) -> str:
    return subprocess.check_output(
        ["git", "-C", str(litellm_dir), "rev-parse", "HEAD"],
        text=True,
    ).strip()


def normalize_json(raw: str) -> str:
    return json.dumps(json.loads(raw), indent=2, sort_keys=True) + "\n"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--litellm-dir", type=Path, help="Existing LiteLLM checkout to read from")
    parser.add_argument("--ref", default="main", help="GitHub ref to fetch when --litellm-dir is omitted")
    parser.add_argument("--check", action="store_true", help="Validate generated resources without rewriting them")
    args = parser.parse_args()

    RESOURCE_DIR.mkdir(parents=True, exist_ok=True)
    source = {}
    generated = {}
    if args.litellm_dir:
        commit = commit_for_clone(args.litellm_dir)
        source = {"source": "local-clone", "commit": commit}
        for name in FILES:
            generated[name] = normalize_json(read_from_clone(args.litellm_dir, name))
    else:
        ref = args.ref
        if args.check and (RESOURCE_DIR / "litellm-upstream.json").exists():
            current_source = json.loads((RESOURCE_DIR / "litellm-upstream.json").read_text(encoding="utf-8"))
            ref = current_source.get("commit") or current_source.get("ref") or ref
            source = current_source
        else:
            source = {"source": "github", "ref": ref}
        for name in FILES:
            generated[name] = normalize_json(read_from_github(ref, name))

    upstream = json.dumps(source, indent=2, sort_keys=True) + "\n"
    if args.check:
        mismatches = []
        for name, content in generated.items():
            if (RESOURCE_DIR / name).read_text(encoding="utf-8") != content:
                mismatches.append(name)
        if (RESOURCE_DIR / "litellm-upstream.json").read_text(encoding="utf-8") != upstream:
            mismatches.append("litellm-upstream.json")
        if mismatches:
            raise SystemExit("Generated LiteLLM metadata is stale: " + ", ".join(mismatches))
        return

    for name, content in generated.items():
        (RESOURCE_DIR / name).write_text(content, encoding="utf-8")
    (RESOURCE_DIR / "litellm-upstream.json").write_text(upstream, encoding="utf-8")


if __name__ == "__main__":
    main()
