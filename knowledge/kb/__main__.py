"""Command-line interface for the cluster knowledge base."""
import argparse
from datetime import datetime, timezone
import json
import os
import sys

import psycopg

from .db import read_snapshot
from .engine import QUESTIONS, evaluate


def utc_timestamp(raw):
    try:
        parsed = datetime.fromisoformat(raw.replace("Z", "+00:00"))
        if parsed.utcoffset() is None:
            raise ValueError
        return parsed.astimezone(timezone.utc)
    except ValueError as exc:
        raise argparse.ArgumentTypeError("Укажите ISO 8601 с часовым поясом.") from exc


def main():
    parser = argparse.ArgumentParser(description="База знаний мониторинга кластера")
    parser.add_argument("question", choices=(*QUESTIONS, "all"))
    parser.add_argument("--node", required=True, help="hostname узла")
    parser.add_argument("--at", required=True, type=utc_timestamp, help="момент снимка ISO 8601")
    parser.add_argument("--demo-profile", action="store_true", help="явно включить учебный предел")
    args = parser.parse_args()

    dsn = os.environ.get("DATABASE_URL")
    if not dsn:
        parser.error("Задайте DATABASE_URL для подключения к PostgreSQL.")
    try:
        data = read_snapshot(dsn, args.node, args.at)
    except psycopg.OperationalError:
        print("Ошибка подключения к PostgreSQL. Проверьте DATABASE_URL и доступность сервера.", file=sys.stderr)
        return 2
    except psycopg.Error as exc:
        print(f"Ошибка чтения схемы project (SQLSTATE {exc.sqlstate or 'unknown'}).", file=sys.stderr)
        return 2
    questions = QUESTIONS if args.question == "all" else [args.question]
    answers = evaluate(data, questions, args.at.isoformat(), args.demo_profile, args.node)
    print(json.dumps(answers if args.question == "all" else answers[0],
                     ensure_ascii=False, indent=2, default=str))
    return 0


if __name__ == "__main__":
    sys.exit(main())
