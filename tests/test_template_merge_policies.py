from pathlib import Path


def normalize_line(line: str) -> str:
    """Collapse internal whitespace to compare merge rules reliably."""
    return " ".join(line.split())


def test_docs_local_merge_policy_rule_is_present_and_unique():
    repo_root = Path(__file__).resolve().parent.parent
    gitattributes_path = repo_root / ".gitattributes"

    assert gitattributes_path.exists(), \
        "Expected to find .gitattributes at the repository root, but the file is missing."

    raw_lines = gitattributes_path.read_text(encoding="utf-8").splitlines()
    normalized_lines = [normalize_line(line) for line in raw_lines if line.strip() and not line.strip().startswith("#")]

    expected_rule = "docs/local/** merge=ours"
    occurrences = [line for line in normalized_lines if line == expected_rule]

    assert occurrences, (
        "Expected .gitattributes to contain the merge rule 'docs/local/** merge=ours', "
        f"but it was not found. Normalized contents: {normalized_lines!r}"
    )

    assert len(occurrences) == 1, (
        "Expected exactly one 'docs/local/** merge=ours' rule in .gitattributes, "
        f"but found {len(occurrences)} occurrences. Normalized contents: {normalized_lines!r}"
    )

