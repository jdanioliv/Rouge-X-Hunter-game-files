#!/usr/bin/env python
"""Builds the project knowledge graph with graphify and publishes it into the vault.

Run through `npm run vault:graph`, which finds the right Python. One graph covers the game code,
the tooling and the vault notes, so a note connects to the code it describes. It uses graphify's
local extractors only: tree-sitter for code, and links and code mentions for markdown. It makes
no AI calls and costs no tokens.

Output goes to GameNotes/Graph/: GRAPH_REPORT.md, graph.json, graph.html and wiki/. A semantic
layer can be added later with graphify's own /graphify skill.
"""
import json
import shutil
import subprocess
import sys
from pathlib import Path

from graphify.analyze import god_nodes, suggest_questions, surprising_connections
from graphify.build import build_from_json
from graphify.cluster import cluster, label_communities_by_hub, score_all
from graphify.export import to_html, to_json
from graphify.extract import extract
from graphify.report import generate
from graphify.wiki import to_wiki

REPO = Path(__file__).resolve().parent.parent
VAULT = REPO / "GameNotes"
OUT = VAULT / "Graph"
CACHE = REPO / "graphify-out"

CODE_DIRS = ["src", "scripts", "server"]
CODE_SUFFIXES = {".luau", ".js", ".py"}
NOTE_SKIP = {"Templates", "Graph", ".obsidian", ".git", ".trash"}


def collect():
    code = [
        p
        for d in CODE_DIRS
        for p in sorted((REPO / d).rglob("*"))
        if p.is_file() and p.suffix in CODE_SUFFIXES
    ]
    notes = [
        p
        for p in sorted(VAULT.rglob("*.md"))
        if not NOTE_SKIP.intersection(p.relative_to(VAULT).parts)
    ]
    return code, notes


def commit():
    r = subprocess.run(["git", "rev-parse", "HEAD"], cwd=REPO, capture_output=True, text=True)
    return r.stdout.strip() if r.returncode == 0 else None


def main():
    code, notes = collect()
    print(f"[vault-graph] {len(code)} code files, {len(notes)} notes")
    extraction = extract(code + notes, cache_root=CACHE, root=REPO)
    G = build_from_json(extraction, root=str(REPO), directed=False)
    if G.number_of_nodes() == 0:
        sys.exit("[vault-graph] extraction produced no nodes, nothing written")

    communities = cluster(G)
    cohesion = score_all(G, communities)
    labels = label_communities_by_hub(G, communities)
    gods = god_nodes(G)
    surprises = surprising_connections(G, communities)
    questions = suggest_questions(G, communities, labels)

    if (OUT / "wiki").exists():
        shutil.rmtree(OUT / "wiki")
    OUT.mkdir(parents=True, exist_ok=True)

    head = commit()
    to_json(G, communities, str(OUT / "graph.json"), force=True, built_at_commit=head, community_labels=labels)
    to_html(G, communities, str(OUT / "graph.html"), community_labels=labels)
    articles = to_wiki(G, communities, OUT / "wiki", community_labels=labels, cohesion=cohesion, god_nodes_data=gods)

    words = sum(len(p.read_text(encoding="utf-8", errors="ignore").split()) for p in code + notes)
    detection = {
        "total_files": len(code) + len(notes),
        "total_words": words,
        "files": {"code": [str(p) for p in code], "document": [str(p) for p in notes], "paper": [], "image": []},
        "needs_graph": True,
        "warning": None,
    }
    tokens = {"input": 0, "output": 0}
    report = generate(
        G, communities, cohesion, labels, gods, surprises, detection, tokens, "RougeXHunter",
        suggested_questions=questions, built_at_commit=head,
    )
    (OUT / "GRAPH_REPORT.md").write_text(report, encoding="utf-8")
    print(
        f"[vault-graph] {G.number_of_nodes()} nodes, {G.number_of_edges()} edges, "
        f"{len(communities)} communities, {articles} wiki articles -> {OUT.relative_to(REPO).as_posix()}"
    )


if __name__ == "__main__":
    main()
