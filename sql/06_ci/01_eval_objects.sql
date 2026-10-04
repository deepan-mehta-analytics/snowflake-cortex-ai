-- ══════════════════════════════════════════════════════════════════
-- 06_ci / 01 — objects the native Cortex Agent Evaluation reads
-- ══════════════════════════════════════════════════════════════════
USE ROLE SYSADMIN;                                                    -- owner of the coco schemas (CREATE SCHEMA granted in 05_guardrails/00)
CREATE SCHEMA IF NOT EXISTS coco.eval;                                -- evaluation dataset table + config stage
CREATE TABLE IF NOT EXISTS coco.eval.golden_questions (               -- golden questions with ground truth (loaded by eval/native_eval.py)
    question_id  VARCHAR,                                             -- q01..q15, from eval/golden_dataset.jsonl
    category     VARCHAR,                                             -- core / variation / edge_case / ambiguous / data_validation
    query_text   VARCHAR,                                             -- the question sent to the agent
    ground_truth VARIANT                                              -- {"ground_truth_output": "..."}
);
CREATE STAGE IF NOT EXISTS coco.eval.config_stage;                    -- internal stage holding the rendered evaluation YAML
