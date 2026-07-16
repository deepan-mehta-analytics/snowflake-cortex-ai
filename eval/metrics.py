"""Scoring functions for the AP invoice agent evaluation harness.

Each function takes the agent's raw text answer and the golden dataset row
it was answering, and returns True/False plus a short note explaining the
verdict. These are intentionally simple heuristics, not semantic scoring —
good enough to catch obvious regressions, not a substitute for human review.
"""

# ── Imports ───────────────────────────────────────────────────
import re                                    # regex used to detect numbers and simple patterns

# ── Individual checks ─────────────────────────────────────────
def numeric_present(answer: str, row: dict) -> tuple[bool, str]:
    """Pass if the answer contains at least one number (a total, count, etc.)."""
    has_number = bool(re.search(r"\d", answer))  # look for any digit in the answer text
    note = "found a number" if has_number else "no number found in answer"  # explain the verdict
    return has_number, note                       # return pass/fail plus the note

def contains_vendor_list(answer: str, row: dict) -> tuple[bool, str]:
    """Pass if the answer looks like it enumerates one or more vendor names."""
    looks_like_list = bool(re.search(r"(-|\d\.|,)", answer))  # crude check for list-like punctuation
    note = "answer looks list-shaped" if looks_like_list else "answer has no list markers"
    return looks_like_list, note

def contains_all_sources(answer: str, row: dict) -> tuple[bool, str]:
    """Pass if the answer mentions all three known source systems."""
    required = ["ERP", "VENDOR_PORTAL", "OCR"]                # the three source_system tags in the pipeline
    missing = [s for s in required if s.upper() not in answer.upper()]  # find any source not mentioned
    passed = not missing                                       # pass only if nothing is missing
    note = "all sources mentioned" if passed else f"missing: {', '.join(missing)}"
    return passed, note

def no_hallucinated_certainty(answer: str, row: dict) -> tuple[bool, str]:
    """Fail if the answer asserts a fact with no hedge and no source grounding language."""
    hedge_words = ["no matching", "not found", "did not find", "based on", "according to", "retrieved"]
    has_hedge_or_grounding = any(w in answer.lower() for w in hedge_words)  # look for grounding/hedge language
    note = "answer is grounded or appropriately hedged" if has_hedge_or_grounding else "answer asserts without grounding language"
    return has_hedge_or_grounding, note

def contains_invoice_id(answer: str, row: dict) -> tuple[bool, str]:
    """Pass if the answer echoes back the invoice_id referenced in the question."""
    match = re.search(r"INV-\d+", row["question"])              # find the invoice id pattern in the question
    invoice_id = match.group(0) if match else None              # extract it if present
    passed = bool(invoice_id and invoice_id in answer)           # answer must repeat the same invoice id
    note = f"echoes {invoice_id}" if passed else f"does not echo {invoice_id}"
    return passed, note

# ── Dispatch table ────────────────────────────────────────────
CHECKS = {
    "numeric_present": numeric_present,               # maps golden-dataset "check" field to its scoring function
    "contains_vendor_list": contains_vendor_list,
    "contains_all_sources": contains_all_sources,
    "no_hallucinated_certainty": no_hallucinated_certainty,
    "contains_invoice_id": contains_invoice_id,
}

def score(answer: str, row: dict) -> tuple[bool, str]:
    """Look up and run the check named in row['check'] against the given answer."""
    check_fn = CHECKS[row["check"]]                    # resolve the named check to its function
    return check_fn(answer, row)                        # run it and return (passed, note)
