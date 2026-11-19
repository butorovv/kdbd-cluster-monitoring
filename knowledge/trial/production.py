"""Independent production model for the shared synthetic scenarios."""
from collections import Counter
import json
from pathlib import Path


HERE = Path(__file__).resolve().parent
KINDS = ("cpu", "gpu", "psu")
RULES = (
    (90, {"registered": False}, {"status": "unknown_source", "reason": "source_registration"}),
    (80, {"registered": True, "measured": False},
     {"status": "missing_sample", "reason": "missing", "action": "check_source"}),
    (50, {"reached": True}, {"status": "threshold_reached", "reason": "limit"}),
    (50, {"reached": False}, {"status": "below_threshold", "reason": "limit"}),
)


def topology(data):
    groups = {group["code"]: group for group in data["groups"]}
    path = [data["node"]]
    code = data["node_group"]
    while code is not None:
        group = groups[code]
        assert (group["kind"] == "cluster") == (group["parent"] is None)
        path.append(code)
        code = group["parent"]
    return list(reversed(path))


def diagnose(data, scenario, source):
    metric = data["metric"]
    assert (metric["kind"], metric["code"], metric["unit"]) == ("gpu", "GPU_CORE_TEMP", "degC")
    samples = {row["source"]: row["value"] for row in scenario["samples"]}
    assert len(samples) == len(scenario["samples"])
    value = samples.get(source)
    facts = {
        "registered": source in scenario["sources"],
        "measured": value is not None,
        "reached": value >= data["threshold"] if value is not None else None,
    }
    matches = [(priority, result) for priority, conditions, result in RULES
               if all(facts[name] == value for name, value in conditions.items())]
    conclusion = max(matches, key=lambda match: match[0])[1]
    return {key: data["knowledge"].get(value, value) for key, value in conclusion.items()}


def run(data):
    counts = Counter(data["components"])
    assert counts.keys() <= set(KINDS)
    scenarios = {scenario["id"]: scenario for scenario in data["scenarios"]}
    knowledge = data["knowledge"]
    return {
        "basis": {
            "topology": [knowledge[key] for key in
                         ("node_membership", "root_without_parent", "topological_parent")],
            "components": [knowledge["component_kinds"]],
            "telemetry": [knowledge[key] for key in
                          ("gpu_temperature", "source_registration", "sample_uniqueness")],
        },
        "topology": topology(data),
        "components": {kind: counts[kind] for kind in KINDS},
        "missing_gpu5": diagnose(data, scenarios["stock"], 5),
        "diagnoses": {key: diagnose(data, scenario, 0) for key, scenario in scenarios.items()},
    }


if __name__ == "__main__":
    data = json.loads((HERE / "scenarios.json").read_text(encoding="utf-8"))
    print(json.dumps(run(data), indent=2))
