"""Rule tests and PostgreSQL integration tests for the disposable demo database."""
import csv
from datetime import datetime, timedelta, timezone
from decimal import Decimal
import json
import os
from pathlib import Path
import subprocess
import sys
import unittest

import psycopg

from kb.db import read_snapshot
from kb.engine import QUESTIONS, evaluate, load, resolve


AT = datetime(2026, 10, 1, 9, 1, tzinfo=timezone.utc)
NODE = "a01n01"


class RulesTest(unittest.TestCase):
    def diagnose(self, value, demo=True, source=1, sample=1, unit="degC"):
        data = {
            "node": {"hostname": NODE},
            "snapshot": [{"kind": "gpu", "local_index": 0, "code": "GPU_CORE_TEMP",
                          "value": value, "source_id": source, "telemetry_id": sample, "unit": unit}],
        }
        return evaluate(data, ["Q09"], AT.isoformat(), demo)[0]

    def test_below(self):
        self.assertEqual(self.diagnose(Decimal("79.999"))["status"], "below_threshold")

    def test_equal(self):
        self.assertEqual(self.diagnose(Decimal("80"))["status"], "threshold_reached")

    def test_above(self):
        self.assertEqual(self.diagnose(Decimal("80.001"))["status"], "threshold_reached")

    def test_no_policy(self):
        self.assertEqual(self.diagnose(Decimal("90"), demo=False)["status"], "unknown_limit")

    def test_missing_sample_excludes_threshold(self):
        result = self.diagnose(None, sample=None)
        self.assertEqual(result["status"], "missing_sample")
        self.assertEqual(result["explanation"]["rule_id"], "R-MISSING")
        self.assertTrue(result["explanation"]["suppressed"])

    def test_no_source_has_priority_over_limit(self):
        result = self.diagnose(None, source=None, sample=None)
        self.assertEqual(result["status"], "unknown_source")
        self.assertIn("R-NO-LIMIT", [r["rule_id"] for r in result["explanation"]["suppressed"]])

    def test_invalid_nan(self):
        self.assertEqual(self.diagnose(Decimal("NaN"))["status"], "invalid_value")

    def test_wrong_unit(self):
        self.assertEqual(self.diagnose(Decimal("81"), unit="K")["status"], "invalid_value")

    def test_unknown_node(self):
        answers = evaluate({"node": None}, QUESTIONS, AT.isoformat(), hostname="unknown")
        self.assertTrue(all(a["status"] == "unknown_node" for a in answers))

    def test_tied_priority_uses_rule_id(self):
        rule = next(r for r in load("rules.json") if r["id"] == "R-HOT")
        winner, _, suppressed = resolve(
            [{**rule, "id": "B"}, {**rule, "id": "A"}], "Q09", rule["when"]
        )
        self.assertEqual(winner["id"], "A")
        self.assertEqual(suppressed[0]["reason"], "rule_id_order")

    def test_catalog_maps_all_ids_and_questions(self):
        with (Path(__file__).resolve().parents[1] / "knowledge.csv").open(
            encoding="utf-8-sig", newline=""
        ) as stream:
            ids = [row["id"] for row in csv.DictReader(stream)]
        concepts = load("concepts.json")["concepts"]
        concept_ids = {identifier for concept in concepts for identifier in concept["knowledge_ids"]}
        rule_ids = {identifier for rule in load("rules.json") for identifier in rule["knowledge"]}
        self.assertEqual(len(ids), len(set(ids)))
        self.assertGreaterEqual(sum(identifier.startswith("K") for identifier in ids), 30)
        self.assertEqual(concept_ids | rule_ids, set(ids))
        self.assertEqual({q for concept in concepts for q in concept["questions"]}, set(QUESTIONS))

    def test_explanation_has_conditions_values_and_sources(self):
        result = self.diagnose(Decimal("80"))
        evidence = result["explanation"]
        self.assertEqual(evidence["rule_id"], "R-HOT")
        self.assertTrue(all(check["passed"] for check in evidence["conditions"]))
        self.assertEqual(evidence["rows"]["snapshot"]["value"], Decimal("80"))
        self.assertGreaterEqual(len(evidence["knowledge"]), 2)


@unittest.skipUnless(os.environ.get("DATABASE_URL"), "DATABASE_URL отсутствует")
class PostgreSQLTest(unittest.TestCase):
    def setUp(self):
        self.dsn = os.environ["DATABASE_URL"]

    def cli(self, question, *flags):
        command = [sys.executable, "-m", "kb", question, "--node", NODE,
                   "--at", AT.isoformat(), *flags]
        completed = subprocess.run(command, cwd=Path(__file__).resolve().parents[1],
                                   text=True, capture_output=True)
        self.assertEqual(completed.returncode, 0, completed.stderr)
        return json.loads(completed.stdout)

    def test_all_ten_answers(self):
        answers = self.cli("all", "--demo-profile")
        self.assertEqual([a["question"] for a in answers], list(QUESTIONS))
        self.assertEqual([a["status"] for a in answers], [
            "found", "found", "found", "found", "gaps_found", "found", "found",
            "demo_limit", "below_threshold", "missing_sample",
        ])
        self.assertEqual(answers[0]["answer"], ["SUMMIT", "a01", NODE])
        self.assertEqual(answers[1]["answer"], {"cpu": 2, "gpu": 6, "psu": 2})
        self.assertEqual({r["code"]: r["unit"] for r in answers[2]["answer"]}, {
            "CPU_MEAN_TEMP": "degC", "CPU_POWER": "W", "GPU_CORE_TEMP": "degC",
            "GPU_POWER": "W", "PSU_INPUT_POWER": "W",
        })
        self.assertEqual(Decimal(answers[3]["answer"]["value"]), Decimal("61"))
        self.assertIsNotNone(answers[3]["explanation"]["rows"]["snapshot"]["telemetry_id"])
        self.assertEqual([(r["kind"], r["local_index"], r["code"]) for r in answers[4]["answer"]],
                         [("gpu", 5, "GPU_CORE_TEMP")])
        self.assertEqual(answers[5]["answer"][0]["event_type"], "maintenance")
        history = answers[6]["answer"]
        self.assertEqual(history["maintenance"][0]["tab_no"], "DEMO-001")
        self.assertEqual(Decimal(history["maintenance_resource"][0]["qty"]), Decimal("2"))
        self.assertEqual(history["document_by_node"][0]["document_type"], "maintenance_report")
        self.assertEqual(answers[7]["answer"]["threshold"], "80")
        self.assertEqual(answers[9]["explanation"]["rule_id"], "R-MISSING")

    def test_exact_timestamp_without_fallback(self):
        data = read_snapshot(self.dsn, NODE, AT + timedelta(seconds=1))
        self.assertEqual(len(data["snapshot"]), 18)
        self.assertTrue(all(row["telemetry_id"] is None for row in data["snapshot"]))

    @unittest.skipUnless(os.environ.get("KB_TEST_MUTATE_DEMO") == "1", "Требуется KB_TEST_MUTATE_DEMO=1")
    def test_live_measurement_changes_cli_diagnosis(self):
        with psycopg.connect(self.dsn, autocommit=True) as connection:
            database = connection.execute("SELECT current_database()").fetchone()[0]
            if database != "cluster_kb_demo":
                self.skipTest("Изменение измерения допускается только в cluster_kb_demo")
            before = self.cli("Q09", "--demo-profile")
            node = before["explanation"]["node"]
            has_demo_marker = connection.execute(
                "SELECT EXISTS (SELECT 1 FROM project.event "
                "WHERE node_id = %s AND message = %s)",
                (node["id"], "DEMO: учебный осмотр, не реальное событие Summit"),
            ).fetchone()[0]
            self.assertEqual(node["description"], "DEMO: пример узла")
            self.assertTrue(has_demo_marker, "Требуется точная демонстрационная фикстура")
            row = before["explanation"]["rows"]["snapshot"]
            self.assertEqual(before["status"], "below_threshold")
            self.assertEqual(Decimal(row["value"]), Decimal("61"))
            statement = "UPDATE project.telemetry SET value = %s WHERE id = %s"
            try:
                changed = connection.execute(statement, (Decimal("80"), row["telemetry_id"]))
                self.assertEqual(changed.rowcount, 1)
                after = self.cli("Q09", "--demo-profile")
                self.assertEqual(after["status"], "threshold_reached")
                self.assertEqual(after["explanation"]["rule_id"], "R-HOT")
            finally:
                connection.execute(statement, (Decimal(row["value"]), row["telemetry_id"]))
            restored = self.cli("Q09", "--demo-profile")
            self.assertEqual(restored["status"], "below_threshold")
            for answer in (before, after, restored):
                print(f'Q09: {answer["answer"]["value"]} °C → {answer["explanation"]["rule_id"]}')
