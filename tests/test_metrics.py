"""Offline tests for heuristic checks added to eval/metrics.py."""

# ── Imports ───────────────────────────────────────────────────
import os                                    # build the import path to eval/
import sys                                   # extend sys.path so metrics can be imported

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "eval"))  # make eval/ importable
from metrics import mentions_hydraulic                                     # noqa: E402 — check under test

# ── Tests ─────────────────────────────────────────────────────
def test_mentions_hydraulic_passes_on_search_hit():
    """The live search answer named 'Hydraulic pumps Q1 order' — that passes."""
    assert mentions_hydraulic("- **Hydraulic pumps Q1 order**", {})[0]   # search result surfaced

def test_mentions_hydraulic_fails_without_it():
    """An answer that never mentions hydraulic items fails."""
    assert not mentions_hydraulic("No matching invoices were found.", {})[0]  # search found nothing
