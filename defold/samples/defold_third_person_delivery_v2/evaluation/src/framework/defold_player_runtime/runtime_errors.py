"""Classify candidate-owned fatal diagnostics in Defold runtime logs."""

from __future__ import annotations


CANDIDATE_FATAL_PREFIXES = (
    "ERROR:SCRIPT:",
    "ERROR:GUI:",
    "ERROR:RESOURCE:",
    "ERROR:GAMESYS:",
    "ERROR:GAMEOBJECT:",
    "ERROR:CRASH:",
    "FATAL:",
)


def candidate_runtime_error_line(line: str) -> str | None:
    """Return a fatal Defold diagnostic line, excluding generic engine noise."""
    stripped = line.strip()
    if stripped.startswith(CANDIDATE_FATAL_PREFIXES):
        return stripped
    return None
