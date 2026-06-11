SHELL := /usr/bin/env bash

.PHONY: setup doctor teardown up up-api up-client-api down logs reset restart ps

setup:
	./scripts/setup.sh

doctor:
	./scripts/setup.sh --doctor

teardown:
	./scripts/teardown.sh

up:
	docker compose up --build -d
	docker compose logs -f

up-api:
	docker compose up --build -d api
	docker compose logs -f api

up-client-api:
	docker compose up --build -d api client
	docker compose logs -f api client

down:
	docker compose down

logs:
	docker compose logs -f

restart:
	docker compose down
	docker compose up --build -d
	docker compose logs -f

ps:
	docker compose ps

reset:
	docker compose down -v --remove-orphans
