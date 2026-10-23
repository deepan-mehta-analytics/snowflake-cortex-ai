"""Read money amounts out of an agent answer — shared by check B (eval/native_eval.py) and check C (run_agent.py).

Answers mix prose ("USD 469,300.00", "$469,300", "**EUR 101,450.50**") with
[table] ```json {...}``` [/table] blocks whose amount cells are plain numbers
and whose currency sits in a CURRENCY_CODE column. Both are read here.
Dates, invoice numbers, counts and percentages are not amounts.
"""

# ── Imports ───────────────────────────────────────────────────
import json                                   # parse embedded [table] JSON blocks
import re                                     # find number tokens and currency markers
from decimal import Decimal, InvalidOperation  # exact amounts, no float rounding
from typing import NamedTuple                 # small immutable record

# ── Patterns ──────────────────────────────────────────────────
CURRENCIES = ("USD", "EUR", "GBP")                                       # the three source currencies
SYMBOLS = {"$": "USD", "€": "EUR", "£": "GBP"}                           # symbol → currency code
NUMBER = re.compile(r"\d{1,3}(?:,\d{3})+(?:\.\d+)?|\d+(?:\.\d+)?")      # 469,300.00 · 469300 · 30600.00
TABLE = re.compile(r"\[table\]\s*```json\s*(\{.*?\})\s*```\s*\[/table\]", re.DOTALL)  # embedded result table
CODE = re.compile(r"\b(USD|EUR|GBP)\b")                                  # a currency code mentioned in text
AMOUNT_COLUMN = re.compile(r"AMOUNT|TOTAL|SPEND")                        # column names that hold money
DECORATION = " *:\t"                                                    # markdown bold, spaces, colons between marker and number

# ── Record ────────────────────────────────────────────────────
class Amount(NamedTuple):
    currency: str | None                       # USD / EUR / GBP, or None when the text does not say
    value: Decimal                             # the amount, exact
    span: tuple[int, int]                      # where it was found in the text (a table's whole block for cells)

# ── Prose ─────────────────────────────────────────────────────
def marker_before(text, start):
    """Currency named right before a number ('USD ', '$', '**EUR:** '), else None."""
    head = text[max(0, start - 12):start].rstrip(DECORATION)            # text just before, decoration stripped
    if head and head[-1] in SYMBOLS:                                     # $469,300
        return SYMBOLS[head[-1]]                                         # symbol's currency
    for code in CURRENCIES:                                              # USD 469,300
        if head.endswith(code):                                          # code directly before
            return code                                                  # that currency
    return None                                                          # nothing directly before

def marker_after(text, end):
    """Currency code right after a number ('469,300.00 USD'), else None."""
    tail = text[end:end + 8].lstrip(DECORATION)                          # text just after, decoration stripped
    for code in CURRENCIES:                                              # 469,300.00 USD
        if tail.startswith(code):                                        # code directly after
            return code                                                  # that currency
    return None                                                          # nothing directly after

def currency_on_line(text, start):
    """Nearest currency marker earlier on the same line ('USD 14 invoices totalling 469,300.00')."""
    line_start = text.rfind("\n", 0, start) + 1                          # beginning of this line
    markers = [(m.start(), m.group(1)) for m in CODE.finditer(text, line_start, start)]  # codes before the number
    markers += [(i, SYMBOLS[text[i]]) for i in range(line_start, start) if text[i] in SYMBOLS]  # symbols before it
    return max(markers)[1] if markers else None                          # the nearest one wins

def prose_amounts(text):
    """Amounts written in sentences, bullets or markdown tables."""
    found = []                                                           # results in text order
    for match in NUMBER.finditer(text):                                  # every number token
        start, end = match.span()                                        # its position
        before = text[start - 1] if start else " "                       # character before
        after = text[end] if end < len(text) else " "                    # character after
        if before.isalnum() or before in "-_./" or after.isalnum() or after in "-_%/":  # 2025-04-30, INV-2025-0010, q11, 25%
            continue                                                     # part of a date, id or percentage
        token = match.group(0)                                           # the number as written
        currency = marker_before(text, start) or marker_after(text, end)  # explicit marker next to it
        bare = "," not in token and "." not in token                     # whole number without separators
        if bare and currency is None:                                    # no marker: a count or a year
            continue                                                     # 22 invoices, 2025
        if bare and text[end:end + 2].strip()[:1].isalpha():             # followed by a word: '**USD:** 14 invoices'
            continue                                                     # a count after a currency label
        if currency is None:                                             # formatted like money but unmarked
            currency = currency_on_line(text, start)                     # take the line's currency, if any
        found.append(Amount(currency, Decimal(token.replace(",", "")), (start, end)))  # record it
    return found                                                         # prose amounts

# ── Tables ────────────────────────────────────────────────────
def table_amounts(block, span):
    """Money cells of one [table] JSON block, with each row's currency."""
    try:
        table = json.loads(block)                                        # {"columns": [...], "data": [[...], ...]}
    except ValueError:                                                   # not valid JSON: nothing to read
        return []                                                        # skip the block
    columns = [str(c).upper() for c in table.get("columns", [])]         # column names
    currency_col = next((i for i, c in enumerate(columns) if c.startswith("CURRENCY")), None)  # CURRENCY_CODE
    money_cols = [i for i, c in enumerate(columns) if AMOUNT_COLUMN.search(c) and "COUNT" not in c]  # amount columns
    found = []                                                           # results in row order
    for row in table.get("data", []):                                    # every row
        currency = str(row[currency_col]).upper() if currency_col is not None else None  # row currency
        currency = currency if currency in CURRENCIES else None          # only known codes
        for i in money_cols:                                             # every money cell
            try:
                found.append(Amount(currency, Decimal(str(row[i]).replace(",", "")), span))  # record it
            except (InvalidOperation, IndexError):                       # empty or non-numeric cell
                continue                                                 # skip it
    return found                                                         # table amounts

# ── Public API ────────────────────────────────────────────────
def extract_amounts(text):
    """Every amount in an answer (prose and [table] blocks), in text order."""
    found = []                                                           # all amounts
    masked = list(text)                                                  # copy where table blocks are blanked
    for match in TABLE.finditer(text):                                   # each embedded table
        found += table_amounts(match.group(1), match.span())             # its money cells
        masked[match.start():match.end()] = " " * (match.end() - match.start())  # hide it from the prose scan
    found += prose_amounts("".join(masked))                              # amounts in the remaining text
    return sorted(found, key=lambda a: a.span[0])                        # text order

def check_expected_totals(answer, expected_totals):
    """Check B: per currency, PASS if the expected total appears, MISMATCH if other amounts do, NOT-FOUND if none."""
    amounts = extract_amounts(answer)                                    # what the answer says
    verdicts = {}                                                        # currency → verdict
    for currency, total in (expected_totals or {}).items():             # each expected total
        expected = Decimal(total["amount"])                              # the key's amount
        same_currency = [a for a in amounts if a.currency == currency]   # amounts in that currency
        unmarked = [a for a in amounts if a.currency is None]            # amounts with no currency stated
        if any(a.value == expected for a in same_currency + unmarked):   # the right figure is there
            verdicts[currency] = "PASS"                                  # quoted correctly
        elif same_currency:                                              # that currency appears, wrong figure
            verdicts[currency] = "MISMATCH"                              # a wrong total
        else:                                                            # that currency never appears
            verdicts[currency] = "NOT-FOUND"                             # total missing
    return verdicts                                                      # empty when nothing was expected
