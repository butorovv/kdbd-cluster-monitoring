COMPOSE = docker compose -p cluster-kb-demo -f compose.yml
NODE = a01n01
AT = 2026-10-01T09:01:00Z
MIGRATIONS = ../seminar02/migrations
PSQL = $(COMPOSE) exec -T postgres psql -U kb -d cluster_kb_demo -v ON_ERROR_STOP=1
PYTHON ?= python3

.PHONY: prepare demo test test-db

prepare:
	$(COMPOSE) up -d --wait postgres
	PSQL="$(PSQL) -q" bash ../scripts/migrate.sh $(MIGRATIONS)
	$(COMPOSE) build app

demo: prepare
	$(COMPOSE) run --rm --no-deps app python -m kb all --node $(NODE) --at $(AT) --demo-profile

test:
	$(PYTHON) -m unittest discover -s kb -p 'test_*.py' -v

test-db: prepare
	$(COMPOSE) run --rm --no-deps -e KB_TEST_MUTATE_DEMO=1 app python -m unittest discover -s kb -p 'test_*.py' -v

.PHONY: demo-local test-db-local

demo-local:
	PYTHON="$(PYTHON)" bash local-demo.sh

test-db-local:
	PYTHON="$(PYTHON)" bash local-demo.sh test
