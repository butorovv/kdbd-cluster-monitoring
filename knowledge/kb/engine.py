"""Build question contexts and resolve declarative production rules."""
from collections import Counter
import csv
from decimal import Decimal
import json
from operator import ge, gt
from pathlib import Path


HERE = Path(__file__).resolve().parent
LIMIT_OPERATORS = {">=": ge, ">": gt}
QUESTIONS = tuple(f"Q{number:02d}" for number in range(1, 11))


def load(name):
    return json.loads((HERE / name).read_text(encoding="utf-8"))


def resolve(rules, question, facts):
    applicable = [rule for rule in rules if "*" in rule["questions"] or question in rule["questions"]]
    evaluated = []
    for rule in sorted(applicable, key=lambda rule: (-rule["priority"], rule["id"])):
        checks = [
            {"fact": key, "expected": expectation, "actual": facts.get(key),
             "passed": facts.get(key) == expectation}
            for key, expectation in rule["when"].items()
        ]
        evaluated.append((rule, checks))
    matches = [
        (rule, checks) for rule, checks in evaluated if all(check["passed"] for check in checks)
    ]
    winner, checks = matches[0]
    suppressed = [
        {"rule_id": rule["id"], "priority": rule["priority"],
         "reason": "lower_priority" if rule["priority"] < winner["priority"] else "rule_id_order"}
        for rule, _ in matches[1:]
    ]
    return winner, checks, suppressed


def context(data, question, policy):
    facts = {"node_found": data["node"] is not None}
    if not facts["node_found"]:
        return facts, None, {}
    if question == "Q01":
        rows = data["topology"]
        answer = [row["code"] for row in rows] + [data["node"]["hostname"]]
        complete = bool(rows) and rows[0]["group_type"] == "cluster"
        return {**facts, "available": complete}, answer if complete else None, {"node_group": rows}
    if question == "Q02":
        rows = data["components"]
        counts = Counter(row["kind"] for row in rows)
        answer = {kind: counts[kind] for kind in ("cpu", "gpu", "psu")}
        return {**facts, "available": bool(rows)}, answer, {"component": rows}
    if question == "Q03":
        rows = data["metrics"]
        return {**facts, "available": bool(rows)}, rows, {"metric_type": rows}
    if question == "Q05":
        rows = data["snapshot"]
        gaps = [row for row in rows if row["telemetry_id"] is None]
        return {**facts, "available": bool(rows), "gaps_found": bool(gaps)}, gaps, {"snapshot": rows}
    if question == "Q06":
        rows = data["events"]
        return {**facts, "available": bool(rows)}, rows, {"event": rows}
    if question == "Q07":
        rows = {"maintenance": data["maintenance"], "maintenance_resource": data["resources"],
                "document_by_node": data["documents"]}
        return {**facts, "available": any(rows.values())}, rows, rows

    index = 5 if question == "Q10" else 0
    metric = "GPU_CORE_TEMP"
    row = next(
        (item for item in data["snapshot"]
         if (item["kind"], item["local_index"], item["code"]) == ("gpu", index, metric)),
        {},
    )
    value = row.get("value")
    usable = isinstance(value, Decimal) and value.is_finite() and row.get("unit") == "degC"
    limit_known = bool(policy and row.get("source_id") is not None and
                       (row["code"], row["unit"]) == (policy["metric"], policy["unit"]))
    threshold = Decimal(policy["threshold"]) if limit_known else None
    operator = policy["operator"] if limit_known else None
    reached = LIMIT_OPERATORS[operator](value, threshold) if usable and limit_known else None
    flags = {"available": usable, "source_found": row.get("source_id") is not None,
             "sample_found": row.get("telemetry_id") is not None, "usable": usable,
             "limit_known": limit_known, "reached": reached, "limit_operator": operator}
    answer = {"kind": "gpu", "local_index": index, "metric": metric,
              "value": value, "unit": row.get("unit"), "threshold": threshold}
    return {**facts, **flags}, answer, {"snapshot": row or None}


def evaluate(data, questions, timestamp, demo=False, hostname=None):
    rules = load("rules.json")
    policy = load("policy.json")["demo"] if demo else None
    with (HERE.parent / "knowledge.csv").open(encoding="utf-8-sig", newline="") as stream:
        entries = {row["id"]: row for row in csv.DictReader(stream)}
    concepts = load("concepts.json")["concepts"]
    answers = []
    for question in questions:
        facts, result, evidence = context(data, question, policy)
        winner, checks, suppressed = resolve(rules, question, facts)
        relevant = [concept for concept in concepts if question in concept["questions"]]
        knowledge_ids = dict.fromkeys(winner["knowledge"])
        for concept in relevant:
            knowledge_ids.update(dict.fromkeys(concept["knowledge_ids"]))
        answers.append({
            "question": question, "hostname": hostname or (data["node"] or {}).get("hostname"),
            "timestamp": timestamp, "status": winner["status"], "message": winner["message"],
            "profile": policy["label"] if policy else "Обычный",
            "answer": result, "explanation": {
                "rule_id": winner["id"], "priority": winner["priority"], "conditions": checks,
                "suppressed": suppressed, "facts": facts, "node": data["node"], "rows": evidence,
                "rule_knowledge_ids": winner["knowledge"],
                "concept_ids": [concept["id"] for concept in relevant],
                "knowledge": [entries[identifier] for identifier in knowledge_ids],
            },
        })
    return answers
