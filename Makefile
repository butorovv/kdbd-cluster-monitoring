# Короткие команды для работы со стеком курса. Запуск: make <цель>
SEM ?= 01
PSQL = docker compose exec -T postgres psql -U student -d plant -v ON_ERROR_STOP=1

.PHONY: up down reset psql run setup logs migrate migrate-reset

up:              ## поднять стек
	docker compose up -d

down:            ## остановить стек (данные сохраняются)
	docker compose down

reset:           ## снести том и перезагрузить учебный датасет с нуля
	docker compose down -v
	docker compose up -d

psql:            ## консоль psql
	docker compose exec postgres psql -U student -d plant

logs:            ## логи PostgreSQL
	docker compose logs -f postgres

run:             ## прогнать seminarNN/seminarNN.sql:  make run SEM=01
	docker compose exec -T postgres psql -U student -d plant -v ON_ERROR_STOP=0 < seminar$(SEM)/seminar$(SEM).sql

setup:           ## загрузить дополнительные таблицы семинара:  make setup SEM=03
	docker compose exec -T postgres psql -U student -d plant -v ON_ERROR_STOP=1 < seminar$(SEM)/setup.sql

migrate:         ## применить новые миграции seminar02/migrations/V*.sql в схему project
	bash scripts/migrate.sh seminar02/migrations

migrate-reset:   ## снести схему project и применить все миграции заново (только на семинаре!)
	$(PSQL) -c "drop schema if exists project cascade;"
	bash scripts/migrate.sh seminar02/migrations
