# Tech Stack (AI)

## 1. Run Questions

### 1a. Config Files

| Config File | Location | Config Value | What it's for | How it's used |
|---|---|---|---|---|
| `.env` | `/.env` | `POSTGRES_DB` | Name of the PostgreSQL database | Passed to the `database` and `postgres_exporter` containers so they know which DB to connect to |
| `.env` | `/.env` | `POSTGRES_USER` | Username for the PostgreSQL database | Used in the DB connection, health check (`pg_isready -U`), and by the exporter |
| `.env` | `/.env` | `DATA_SOURCE_NAME` | Full PostgreSQL connection string for the exporter | Read by `postgres_exporter` to scrape DB metrics and expose them to Prometheus |
| `docker-compose.yml` | `/docker-compose.yml` | `env_file` | Path(s) to `.env` files for each service | Injects environment variables into the `database`, `api`, `client`, and `postgres_exporter` containers at startup |
| `docker-compose.yml` | `/docker-compose.yml` | `healthcheck` | Liveness check for the `database` service | Runs `pg_isready` on an interval; dependent services (`api`) only start once this passes |
| `docker-compose.yml` | `/docker-compose.yml` | `networks` | Shared Docker network (`learningplatform`) | All services join this network so they can reach each other by container name (e.g. `database`, `api`) |
| `prometheus.yml` | `/prometheus.yml` | `scrape_interval` | How often Prometheus polls each target for metrics | Controls the frequency (15 s) at which time-series data is collected from Django and PostgreSQL |
| `prometheus.yml` | `/prometheus.yml` | `job_name` | Label applied to a group of scrape targets | Distinguishes Django API metrics (`django`) from PostgreSQL metrics (`postgresql`) in dashboards |
| `prometheus.yml` | `/prometheus.yml` | `metrics_path` | URL path Prometheus requests to collect metrics | Points Prometheus at `/metrics/metrics` on the `api` service instead of the default `/metrics` |
| `valkey/docker-compose.yml` | `/valkey/docker-compose.yml` | `--save` | Valkey (Redis-compatible) persistence trigger | Tells Valkey to write a snapshot to disk after 900 s if at least 1 key changed |
| `valkey/docker-compose.yml` | `/valkey/docker-compose.yml` | `--loglevel` | Verbosity of Valkey server logs | Set to `notice` so only important events are logged, reducing noise |
| `valkey/docker-compose.yml` | `/valkey/docker-compose.yml` | `restart` | Container restart policy | Set to `unless-stopped` so Valkey and its monitor sidecar restart automatically after crashes |

### 1b. How to Start It

The Makefile at the repo root wraps Docker Compose commands. The relevant targets for starting the system are:

| Target | Command | What it does | When to use it |
|---|---|---|---|
| `make setup` | `./scripts/setup.sh` | First-time setup: creates the Docker network, `.env` files, and any other prerequisites before containers are started | Run once before your first `make up` on a new machine |
| `make up` | `docker compose up --build -d` | Builds images (if needed) and starts **all** services in the background | Normal full-stack startup — database, API, client, Prometheus, Grafana, and postgres_exporter all come up together |
| `make up-api` | `docker compose up --build -d api` | Builds and starts **only** the `api` service (database still needs to be running separately) | When you only need the backend, e.g. testing API changes without the frontend |
| `make up-client-api` | `docker compose up --build -d api client` | Builds and starts **only** the `api` and `client` services | When you need the frontend + backend but not the observability stack (Prometheus/Grafana) |
| `make restart` | `docker compose down` then `docker compose up --build -d` | Stops all containers, then rebuilds and restarts everything | When you need a clean restart after config or dependency changes |

**Key difference between the `up` variants:** `make up` brings the entire stack online including monitoring. `make up-api` and `make up-client-api` start subsets of services for faster iteration when you don't need the full stack.

### 1c. Where to Access It

| Service | Port | URL |
|---|---|---|
| Client (React frontend) | 3000 | http://localhost:3000 |
| API (Django backend) | 8000 | http://localhost:8000 |
| API debugger (debugpy) | 5678 | n/a — attach a Python debugger, not a browser |
| Grafana (dashboards) | 3001 | http://localhost:3001 |
| Prometheus (metrics store) | 9090 | http://localhost:9090 |
| postgres_exporter (DB metrics) | 9187 | http://localhost:9187/metrics |
| PostgreSQL (database) | 5432 | n/a — connect with a DB client, not a browser |
| Valkey (cache) | 6379 | n/a — connect with a Redis-compatible client, not a browser |

### 1d. Service Dependencies

| Service | Depends On | Why |
|---|---|---|
| `api` | `database` (must pass healthcheck) | Django runs migrations and loads fixtures against PostgreSQL on startup — the DB must be ready and accepting connections first |
| `client` | `api` (runtime, not declared in compose) | The React frontend makes HTTP requests to the API for all data; the API must be running or those requests will fail |
| `prometheus` | `api` | Prometheus scrapes the `/metrics/metrics` endpoint on the `api` container every 15 s to collect Django application metrics |
| `prometheus` | `postgres_exporter` | Prometheus also scrapes `postgres_exporter:9187` to collect PostgreSQL database metrics |
| `grafana` | `prometheus` | Grafana queries Prometheus as its data source to power dashboards; Prometheus must be running first |
| `postgres_exporter` | `database` | The exporter connects to PostgreSQL using `DATA_SOURCE_NAME` to read internal DB stats and expose them as Prometheus metrics |
| `valkey-monitor` | `valkey` | The monitor sidecar runs `valkey-cli monitor` against the Valkey server; the server must be up before the monitor can connect |

### 1e. Main Entry Points

| Service | Startup File | Routes / URL Config File |
|---|---|---|
| API (Django) | `learn-ops-api/entrypoint.sh` — runs migrations and fixtures, then hands off to `manage.py runserver` (or `debugpy` in debug mode) | `learn-ops-api/LearningPlatform/urls.py` — registers every REST router and URL pattern |
| Client (React) | `learn-ops-client/src/index.js` — mounts the React app into the DOM and wraps it in `<BrowserRouter>` | `learn-ops-client/src/components/LearnOps.js` — top-level route guards; splits traffic to `ApplicationViews`, `StaffViews`, or `StudentViews` based on the logged-in user's role |
| Prometheus | `docker-compose.yml` (`command: --config.file=/etc/prometheus/prometheus.yml`) — starts the Prometheus server process | `prometheus.yml` — defines what to scrape, how often, and from which targets (`api:8000` and `postgres_exporter:9187`) |
| Grafana | `docker-compose.yml` (`image: grafana/grafana:latest`) — starts Grafana with default settings | No custom routes file in this repo — Grafana's web UI and API routing is built into the image |
| postgres_exporter | `docker-compose.yml` (`image: quay.io/prometheuscommunity/postgres-exporter`) — starts the exporter process | No custom routes file — the exporter automatically exposes a single `/metrics` HTTP endpoint |
| Valkey | `valkey/docker-compose.yml` (`command: valkey-server ...`) — starts the Valkey server with persistence and log settings | No routes file — Valkey speaks the Redis protocol over TCP, not HTTP, so there are no URL routes |

## 2. Services

| Service Name | Tech Stack (including version) | Purpose |
|---|---|---|
| `database` | PostgreSQL 16 | Relational database that stores all application data |
| `api` | Python 3.11.11, Django 5.2.13, Django REST Framework | Backend REST API that serves data to the React client |
| `client` | Node.js 22.13.0, React 16.13.1 | React frontend web application served to users in the browser |
| `prometheus` | prom/prometheus:latest | Collects and stores time-series metrics scraped from the `api` and `postgres_exporter` |
| `grafana` | grafana/grafana:latest | Visualization layer that queries Prometheus and displays metrics as dashboards |
| `postgres_exporter` | quay.io/prometheuscommunity/postgres-exporter:latest | Reads internal PostgreSQL stats and exposes them as Prometheus-compatible metrics |
| `valkey` | valkey/valkey:latest (Redis-compatible) | In-memory cache and session store used by the Django API |
| `valkey-monitor` | valkey/valkey:latest (Redis-compatible) | Sidecar that streams all Valkey commands via `valkey-cli monitor` for observability |

## 3. System Overview

LearnOps is a learning management system (LMS) built for Nashville Software School, a coding bootcamp. The problem it solves is keeping track of where every student stands across the full arc of a multi-month program — which projects they have completed, which assessments they have passed, what feedback they have received, and how they are progressing toward graduation. Without a tool like this, instructors would have to piece that picture together from spreadsheets, GitHub repos, and Slack messages; LearnOps centralises all of it in one place.

From the perspective of someone using the system, the application surfaces a dashboard as its home screen. Students can view their personal dashboard showing their current learning goals, assessment status, and upcoming cohort calendar. They can update their Slack member ID so the system can connect their account to team communications, and they can navigate to project requirements (both client-side and server-side) and README templates for their work. Instructors have a richer set of views: they can browse and manage cohorts, create or edit courses (organised into books and projects), run assessments, manage weekly teams, and record feedback about individual students.

There are three distinct roles in the system, each routed to a different set of views. Students land on `StudentViews`, where they can follow their own progress but cannot see or modify other students' data. Instructors land on `ApplicationViews`, the full-featured interface for managing people, cohorts, courses, and assessments. A third role — staff who are not full instructors — lands on `StaffViews`, a narrower view currently focused on the Foundations exercise dashboard. The React client enforces this split at the top-level route guard in `LearnOps.js`, redirecting each logged-in user to the appropriate view based on their role.