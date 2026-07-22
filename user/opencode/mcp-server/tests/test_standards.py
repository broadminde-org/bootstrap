"""Tests for the standards index."""

import json
import tempfile
from pathlib import Path

import pytest
from host_standards.tools.standards import StandardsIndex


@pytest.fixture
def standards_dir():
    with tempfile.TemporaryDirectory() as tmp:
        d = Path(tmp)
        (d / "test-one.md").write_text("# Test One\n\n## Scope\nTesting purposes.\n\nSome content here.")
        (d / "test-two.md").write_text("# Test Two\n\n## Scope\nMore testing.\n\nDifferent content.")
        sub = d / "python"
        sub.mkdir()
        (sub / "style.md").write_text("# Python Style\n\n## Scope\nPython rules.\n\nUse uv and ruff.")
        yield str(d)


def test_index_loads_all_md_files(standards_dir):
    idx = StandardsIndex(standards_dir)
    assert len(idx.list_all()) == 3


def test_index_extracts_titles(standards_dir):
    idx = StandardsIndex(standards_dir)
    titles = {e["title"] for e in idx.list_all()}
    assert "Test One" in titles
    assert "Test Two" in titles
    assert "Python Style" in titles


def test_subdir_id_uses_dash(standards_dir):
    idx = StandardsIndex(standards_dir)
    ids = {e["id"] for e in idx.list_all()}
    assert "python-style" in ids


def test_search_finds_title_match(standards_dir):
    idx = StandardsIndex(standards_dir)
    results = idx.search("python")
    assert len(results) >= 1
    assert any(r["title"] == "Python Style" for r in results)


def test_search_finds_content_match(standards_dir):
    idx = StandardsIndex(standards_dir)
    results = idx.search("ruff")
    assert len(results) >= 1
    assert any("Python Style" == r["title"] for r in results)


def test_get_returns_content(standards_dir):
    idx = StandardsIndex(standards_dir)
    content = idx.get("test-one")
    assert content is not None
    assert "# Test One" in content


def test_get_missing_returns_none(standards_dir):
    idx = StandardsIndex(standards_dir)
    assert idx.get("nonexistent") is None


def test_reload_picks_up_new_files(standards_dir):
    idx = StandardsIndex(standards_dir)
    Path(standards_dir, "new-file.md").write_text("# New File\n\n## Scope\nFresh.\n\nNew content.")
    idx.reload()
    assert len(idx.list_all()) == 4


def test_list_all_includes_summary(standards_dir):
    idx = StandardsIndex(standards_dir)
    entries = idx.list_all()
    for e in entries:
        assert "id" in e
        assert "title" in e
        assert "summary" in e
        assert "line_count" in e
