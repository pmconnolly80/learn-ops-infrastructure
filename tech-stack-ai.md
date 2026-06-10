# Tech Stack Manual

## 1. Run Questions

### 1a. Config Files

| Config File | Location | Config Value | What it's for | How it's used |
|---|---|---|---|---|
| `.env.template` | `learn-ops-api/` | `LEARN_OPS_DJANGO_SECRET_KEY` | Django's cryptographic secret | Signs cookies, sessions, and security tokens |
| `.env.template` | `learn-ops-api/` | `LEARNING_GITHUB_CALLBACK` | GitHub OAuth redirect URL | Tells GitHub where to send users after login |
| `.env.template` | `learn-ops-api/` | `LEARN_OPS_DB` | Postgres database name | Tells Django which database to connect to |
| `.env.template` | `learn-ops-api/` | `VALKEY_HOST` | Hostname for Valkey (cache) | Points Django at the cache/session store |
| `.env.template` | `learn-ops-api/` | `SLACK_BOT_TOKEN` | Slack bot credentials | Authenticates outbound Slack notifications |
| `.env.template` | `learn-ops-api/` | `GITHUB_TOKEN` | GitHub API auth token | Authenticates requests to the GitHub API |
| `.env.template` | `learn-ops-api/` | `DEBUG` | Django debug mode toggle | Enables verbose errors and the debug toolbar |
| `.env` | `learn-ops-client/` | `REACT_APP_API_URI` | Backend API base URL | All React API calls are prefixed with this URL |
| `.env` | `learn-ops-client/` | `REACT_APP_ENV` | Current environment name | Conditionally enables dev-only features |
| `.env` | `learn-ops-client/` | `CHOKIDAR_USEPOLLING` | File-change polling mode | Required for hot reload to work inside Docker |
| `.env` | `learn-ops-client/` | `GENERATE_SOURCEMAP` | Source map generation flag | Disabled to speed up builds |
| `.env` | `learn-ops-infrastructure/` | `POSTGRES_DB` | Postgres database name | Passed to the `postgres` container at startup |
| `.env` | `learn-ops-infrastructure/` | `POSTGRES_USER` | Postgres username | Authenticates Django and the exporter to the DB |
| `.env` | `learn-ops-infrastructure/` | `DATA_SOURCE_NAME` | Full DB connection string | Used by `postgres_exporter` for Prometheus scraping |
| `docker-compose.yml` | `learn-ops-infrastructure/` | `container_name` | Human-readable container name | Used to identify containers in logs and networking |
| `docker-compose.yml` | `learn-ops-infrastructure/` | `ports` | Host-to-container port mappings | Exposes each service on the host using ports defined by `POSTGRES_PORT`, `LEARN_OPS_PORT`, and `VALKEY_PORT` |
| `docker-compose.yml` | `learn-ops-infrastructure/` | `depends_on` | Service startup order | Ensures the database is healthy before the API starts |
| `docker-compose.yml` | `learn-ops-infrastructure/valkey/` | `image` | Valkey container image | Pins the version of Valkey used |
| `docker-compose.yml` | `learn-ops-infrastructure/valkey/` | `ports` | Port mapping for Valkey | Exposes Valkey on the port defined by `VALKEY_PORT` |
| `docker-compose.yml` | `learn-ops-infrastructure/valkey/` | `restart` | Container restart policy | Keeps Valkey running unless explicitly stopped |
| `pytest.ini` | `learn-ops-api/` | `DJANGO_SETTINGS_MODULE` | Which Django settings file to load | Tells pytest/Django which config to use during tests |
| `pytest.ini` | `learn-ops-api/` | `testpaths` | Directory to scan for tests | Points pytest to `LearningAPI/tests` |
| `pytest.ini` | `learn-ops-api/` | `addopts` | Default pytest flags | Enables `--reuse-db` and `--nomigrations` to speed up test runs |
| `pytest.ini` | `learn-ops-api/` | `markers` | Custom test categories | Lets you run only `unit`, `integration`, or `slow` tests |

### 1b. How to Start It

The Makefile lives at `learn-ops-infrastructure/Makefile`. Run all `make` commands from that directory.

| Target | Command | What it does | When to use it |
|---|---|---|---|
| `setup` | `./scripts/setup.sh` | First-time setup — creates the Docker network, `.env` files, etc. | Run once before anything else on a fresh clone |
| `up` | `docker compose up --build -d` | Builds and starts **all** services in the background | Normal full-stack start |
| `up-api` | `docker compose up --build -d api` | Builds and starts the **API only** | When you only need the backend (e.g. running API tests) |
| `up-client-api` | `docker compose up --build -d api client` | Builds and starts the **API + React client** (no DB, Prometheus, Grafana) | When you're doing frontend work and don't need observability services |
| `restart` | `down` then `up --build -d` | Tears everything down and rebuilds from scratch | When you need a clean restart after config changes |

**How the startup targets differ:**
- `up` brings up the entire stack (DB, API, client, Prometheus, Grafana, postgres_exporter).
- `up-api` brings up only the API container — it still depends on the database being healthy (via `depends_on`), so the DB must already be running.
- `up-client-api` is the middle ground: API + client, no observability services.
- `restart` is equivalent to `down` + `up` — useful when a container is in a bad state.
- `setup` is a prerequisite for any of the above on a fresh machine; `up` will fail without the Docker network it creates.


### 1c. Where to Access It

| Service | Port | URL |
|---|---|---|
| React client | 3000 | http://localhost:3000 |
| Django API | 8000 | http://localhost:8000 |
| Postgres | 5432 | n/a (database port, not a web UI) |
| Valkey (cache) | 6379 | n/a (TCP port, not a web UI) |
| Prometheus | 9090 | http://localhost:9090 |
| Grafana | 3001 | http://localhost:3001 |
| Postgres exporter | 9187 | http://localhost:9187/metrics |

### 1d. Service Dependencies

| Service | Depends On | Why |
|---|---|---|
| `api` | `database` | Django reads and writes all application data to Postgres; Docker enforces a health check so the DB is ready before the API starts |
| `api` | `valkey` | Django uses Valkey for session storage and caching (`VALKEY_HOST`); must be reachable at startup |
| `client` | `api` | All React data fetching hits the Django API (`REACT_APP_API_URI`); the client is a blank screen without it |
| `prometheus` | `api` | Prometheus is configured to scrape metrics from the Django API; no API means no metrics to collect |
| `grafana` | `prometheus` | Grafana's dashboards are fed by Prometheus as their data source; no Prometheus means no graphs |
| `postgres_exporter` | `database` | Its sole job is to query Postgres and expose DB metrics to Prometheus; it has no purpose without the database |
| `valkey-monitor` | `valkey` | Runs `valkey-cli monitor` against the Valkey instance; can't connect until Valkey is up |
| `database` | — | No dependencies; starts first |
| `valkey` | — | No dependencies; starts independently |

### 1e. Main Entry Points

| Service | Startup File | Routes / URL Config File |
|---|---|---|
| Django API | `learn-ops-api/manage.py` — launched with `python3 manage.py runserver` (see Dockerfile CMD) | `learn-ops-api/LearningPlatform/urls.py` — registers all DRF viewsets via a `DefaultRouter` and maps auth, admin, metrics, and log endpoints |
| React client | `learn-ops-client/src/index.js` — mounts the React app into the DOM and wraps it in `<Router>` | `learn-ops-client/src/components/LearnOps.js` — top-level auth guard that routes to one of three view sets based on role: `ApplicationViews.js` (instructors), `StaffViews.js` (staff), `StudentViews.js` (students) |
| Prometheus | Docker image entrypoint | `learn-ops-infrastructure/prometheus.yml` — defines scrape targets (Django API at `/metrics/metrics` and `postgres_exporter`) |

---

## 2. Services

| Service Name | Tech Stack (including version) | Purpose |
|---|---|---|
| Django API | Python 3.11.11, Django, Django REST Framework, dj-rest-auth 4.0.1, django-allauth 0.54.0 | REST API — handles all business logic, GitHub OAuth login, and data persistence |
| React client | Node.js 22.13.0, React 16.13.1, React Router 5.2.0, Radix UI, Chart.js 4 | Browser UI — role-based SPA for instructors, staff, and students |
| Postgres | postgres:16 | Primary relational database — stores all application data |
| Valkey | valkey/valkey:latest | In-memory cache and session store (Redis-compatible) |
| Prometheus | prom/prometheus:latest | Metrics collection — scrapes the Django API and postgres_exporter on a 15s interval |
| Grafana | grafana/grafana:latest | Metrics dashboards — visualises data pulled from Prometheus |
| postgres_exporter | quay.io/prometheuscommunity/postgres-exporter:latest | Exposes Postgres database metrics to Prometheus |

---

## 3. System Overview

LearnOps is a learning management system for a coding bootcamp. It tracks students through cohorts, courses, projects, and assessments, and gives instructors and staff tools to monitor progress and give feedback.

**How the pieces fit together:**

Users log in via **GitHub OAuth** — the React client redirects to GitHub, which sends the user back to the Django API, which issues a session token stored in **Valkey**. After that, all API calls from the client carry that token.

The **React client** is role-aware: instructors see a full management UI (cohorts, courses, assessments, student records), staff see a reduced view, and students see their own progress dashboard. All data is fetched from the **Django REST API**.

The **Django API** owns all business logic — it reads and writes application data to **Postgres**, uses **Valkey** for session storage and caching, calls the **GitHub API** to pull student repo data, and sends notifications via **Slack**.

The **observability stack** sits alongside the application: **Prometheus** scrapes metrics from the Django API (`/metrics/metrics`) and from **postgres_exporter** (`/metrics`) every 15 seconds. **Grafana** connects to Prometheus to display dashboards. None of this is in the request path — it's purely a side channel for monitoring.

```
Browser
  │
  ▼
React client (port 3000)
  │  REST + auth token
  ▼
Django API (port 8000) ──── Postgres (port 5432)
  │                    ──── Valkey (port 6379)
  │                    ──── GitHub API (OAuth + repo data)
  │                    ──── Slack API (notifications)
  │
  │ /metrics/metrics
  ▼
Prometheus (port 9090) ◄─── postgres_exporter (port 9187)
  │
  ▼
Grafana (port 3001)
```
