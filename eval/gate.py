"""Regression gate for native Cortex Agent Evaluation scores.

Pure functions only (no network): compare a run's per-question judge scores
(0.0–1.0) with the committed baseline and render a markdown summary.
"""

# ── Imports ───────────────────────────────────────────────────
from dataclasses import dataclass, field       # small result record

# ── Rules (spec §3, decision 6) ───────────────────────────────
METRICS = ("answer_correctness", "logical_consistency")   # metrics the gate checks
TOLERANCE = 0.10                                           # allowed drop of a metric's mean vs baseline
WARN_DROP = 0.5                                            # per-question drop that is reported (never fails)

# ── Result record ─────────────────────────────────────────────
@dataclass
class GateResult:
    passed: bool                                           # True when no mean dropped beyond TOLERANCE
    reasons: list = field(default_factory=list)            # why it failed (empty when passed)
    warnings: list = field(default_factory=list)           # per-question notes (never fail the run)
    run_means: dict = field(default_factory=dict)          # this run's mean per metric

# ── Means ─────────────────────────────────────────────────────
def means(scores):
    """Mean of each metric across all questions in the run."""
    result = {}                                            # metric → mean
    for metric in METRICS:                                 # each gated metric
        values = [q[metric] for q in scores.values()]      # every question's score for it
        result[metric] = round(sum(values) / len(values), 4) if values else 0.0  # empty run → 0.0
    return result                                          # metric → mean

# ── Gate ──────────────────────────────────────────────────────
def evaluate_gate(scores, baseline):
    """Compare a run with the baseline; fail only on a mean drop beyond TOLERANCE."""
    run_means = means(scores)                              # this run's means
    reasons, warnings = [], []                             # collected messages
    for metric in METRICS:                                 # check each metric's mean
        floor = round(baseline["means"][metric] - TOLERANCE, 4)  # lowest acceptable mean
        if run_means[metric] < floor:                      # strictly below → regression
            reasons.append(f"{metric} mean {run_means[metric]:.2f} < baseline {baseline['means'][metric]:.2f} − {TOLERANCE:.2f}")
    for qid in sorted(scores):                             # per-question notes
        base_q = baseline["per_question"].get(qid)         # this question's baseline scores, if any
        if base_q is None:                                 # question added after the baseline
            warnings.append(f"{qid}: new question, no baseline")
            continue                                       # nothing to compare against
        for metric in METRICS:                             # big single-question drops
            drop = round(base_q[metric] - scores[qid][metric], 4)  # positive = got worse (rounded: float noise)
            if drop >= WARN_DROP:                          # report, don't fail
                warnings.append(f"{qid}: {metric} {base_q[metric]:.2f} → {scores[qid][metric]:.2f}")
    for qid in sorted(set(baseline["per_question"]) - set(scores)):  # baseline questions absent from this run
        warnings.append(f"{qid}: missing from this run")
    return GateResult(passed=not reasons, reasons=reasons, warnings=warnings, run_means=run_means)

# ── Markdown summary ──────────────────────────────────────────
def plain_cell(text):
    """Make untrusted agent/judge text safe inside one markdown table cell: one line, no pipes, no markup."""
    flat = " ".join(str(text).split())                     # newlines/tabs → single spaces (no new rows or headings)
    for char in "\\|[]()<>*_`#!":                          # characters that build tables, links, HTML or emphasis
        flat = flat.replace(char, "\\" + char if char != "|" else "¦")  # pipe → broken bar; others backslash-escaped
    return flat[:200]                                      # keep cells short

def render_summary(scores, baseline, result, categories, errors):
    """Markdown for the GitHub step summary: verdict, means, per-question table, warnings."""
    verdict = "✅ PASS" if result.passed else "❌ FAIL"     # headline
    lines = [f"## Native agent evaluation — {verdict}", ""]  # title
    lines += ["| Metric | Baseline | This run |", "|---|---|---|"]  # means table header
    for metric in METRICS:                                 # one row per metric
        lines.append(f"| {metric} | {baseline['means'][metric]:.2f} | {result.run_means[metric]:.2f} |")
    lines += ["", "| Question | Category | answer_correctness | logical_consistency | Note |", "|---|---|---|---|---|"]  # per-question header
    for qid in sorted(scores):                             # one row per question
        s = scores[qid]                                    # its scores
        lines.append(f"| {qid} | {categories.get(qid, '')} | {s['answer_correctness']:.2f} | {s['logical_consistency']:.2f} | {plain_cell(errors.get(qid, ''))} |")
    if result.reasons:                                     # failure reasons
        lines += ["", "**Why it failed**"] + [f"- {r}" for r in result.reasons]
    if result.warnings:                                    # per-question notes
        lines += ["", "**Warnings (do not fail the run)**"] + [f"- {w}" for w in result.warnings]
    return "\n".join(lines) + "\n"                          # trailing newline for appending
