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
    """Pass if the answer looks like it enumerates one or more vendors with amounts."""
    looks_like_list = bool(re.search(r"(-|\d\.|,)", answer))  # crude check for list-like punctuation
    has_number = bool(re.search(r"\d", answer))                 # a vendor breakdown should carry amounts too
    passed = looks_like_list and has_number
    note = "answer looks list-shaped with numbers" if passed else "answer is missing list structure or numbers"
    return passed, note

def mentions_source_system(answer: str, row: dict) -> tuple[bool, str]:
    """Pass if the answer names at least one of the four known source systems."""
    systems = ["SAP", "ORACLE", "BAAN", "WORKDAY"]              # the four source_system values in the pipeline
    mentioned = [s for s in systems if s in answer.upper()]      # find which ones are named
    passed = bool(mentioned)
    note = f"mentions {', '.join(mentioned)}" if passed else "no source system named"
    return passed, note

def mentions_currency_codes(answer: str, row: dict) -> tuple[bool, str]:
    """Pass if the answer names at least one ISO currency code present in the data."""
    currencies = ["USD", "EUR", "GBP"]                           # currencies observed across the 4 bronze sources
    mentioned = [c for c in currencies if c in answer.upper()]    # find which ones are named
    passed = bool(mentioned)
    note = f"mentions {', '.join(mentioned)}" if passed else "no currency code named"
    return passed, note

def mentions_approval_status(answer: str, row: dict) -> tuple[bool, str]:
    """Pass if the answer names the normalized approval_status values."""
    statuses = ["APPROVED", "PENDING"]                            # BR-001 normalized status values
    mentioned = [s for s in statuses if s in answer.upper()]       # find which ones are named
    passed = bool(mentioned)
    note = f"mentions {', '.join(mentioned)}" if passed else "no approval status named"
    return passed, note

def mentions_time_period(answer: str, row: dict) -> tuple[bool, str]:
    """Pass if the answer references a month/date, indicating a time breakdown happened."""
    has_month_name = bool(re.search(r"jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec", answer.lower()))
    has_date_pattern = bool(re.search(r"\d{4}-\d{2}(-\d{2})?", answer))  # YYYY-MM or YYYY-MM-DD
    passed = has_month_name or has_date_pattern
    note = "answer references a time period" if passed else "no month or date found in answer"
    return passed, note

def mentions_acme(answer: str, row: dict) -> tuple[bool, str]:
    """Pass if the answer echoes the vendor named in the question (Acme)."""
    passed = "acme" in answer.lower()                              # the question filters to Acme Industrial Supply
    note = "echoes Acme" if passed else "does not echo the vendor named in the question"
    return passed, note

def mentions_overdue(answer: str, row: dict) -> tuple[bool, str]:
    """Pass if the answer engages with the concept of overdue/due-date filtering."""
    passed = bool(re.search(r"overdue|due date|past due", answer.lower()))
    note = "engages with overdue/due-date concept" if passed else "answer does not mention overdue or due date"
    return passed, note

def mentions_threshold(answer: str, row: dict) -> tuple[bool, str]:
    """Pass if the answer reflects the $100,000 threshold from the question."""
    passed = bool(re.search(r"100[,]?000|100k", answer.lower()))
    note = "reflects the $100,000 threshold" if passed else "answer does not reference the threshold"
    return passed, note

def no_hallucinated_certainty(answer: str, row: dict) -> tuple[bool, str]:
    """Fail if the answer asserts a fact with no hedge and no source grounding language."""
    hedge_words = ["clarify", "which", "what time", "what do you mean", "could you specify",
                   "no matching", "not found", "did not find", "based on", "according to", "retrieved"]
    has_hedge_or_grounding = any(w in answer.lower() for w in hedge_words)  # look for grounding/hedge language
    note = "answer is grounded or appropriately hedged" if has_hedge_or_grounding else "answer asserts without grounding or asking for clarification"
    return has_hedge_or_grounding, note

# ── Dispatch table ────────────────────────────────────────────
CHECKS = {
    "numeric_present": numeric_present,               # maps golden-dataset "check" field to its scoring function
    "contains_vendor_list": contains_vendor_list,
    "mentions_source_system": mentions_source_system,
    "mentions_currency_codes": mentions_currency_codes,
    "mentions_approval_status": mentions_approval_status,
    "mentions_time_period": mentions_time_period,
    "mentions_acme": mentions_acme,
    "mentions_overdue": mentions_overdue,
    "mentions_threshold": mentions_threshold,
    "no_hallucinated_certainty": no_hallucinated_certainty,
}

def score(answer: str, row: dict) -> tuple[bool, str]:
    """Look up and run the check named in row['check'] against the given answer."""
    check_fn = CHECKS[row["check"]]                    # resolve the named check to its function
    return check_fn(answer, row)                        # run it and return (passed, note)
