# learn-ops-api: AI-Assisted Exploration

## 1. Top-level folders in `learn-ops-api`

| Folder | Why does this folder need to exist? |
|--------|-------------------------------------|
| `LearningAPI/` | The main Django app — all business logic, models, views, and tests live here |
| `LearningPlatform/` | The Django project wrapper — holds global `settings.py`, root `urls.py`, and `wsgi.py`. The entry point that wires everything together |
| `LogViewer/` | A small secondary Django app that provides a UI to browse server logs from within the platform |
| `config/` | Infrastructure config files — an API spec (`learn-ops-api.yaml`) and Nginx configs for routing traffic to the API and the React client |
| `logs/` | Runtime log output written by the running server; not committed source code |
| `static/` | Source static assets (CSS, JS, images) used during development |
| `staticfiles/` | Django's `collectstatic` output — what gets served in production |
| `templates/` | Django HTML templates, currently just the admin interface |

## 2. Folders inside `LearningAPI`

| Folder | What responsibility does it own and why? |
|--------|------------------------------------------|
| `models/` | Database schema definitions, split into three sub-groups: `coursework/`, `people/`, and `skill/` |
| `models/coursework/` | Everything curriculum-shaped: books, courses, projects, capstones, learning objectives, foundation exercises |
| `models/people/` | Everyone in the system: students (`NssUser`), cohorts, teams, assessments, notes, GitHub links, mentor relationships |
| `models/skill/` | Skill tracking: core skills, learning records, assessment weights — the "how is this student progressing" layer |
| `views/` | API endpoint handlers — one file per resource (e.g. `cohort_view.py`, `student_view.py`). Also sub-folders for GitHub and OAuth2 integrations |
| `serializers/` | Django REST Framework serializers — control how model data is converted to/from JSON for the API |
| `migrations/` | Auto-generated database migration files tracking every schema change over time |
| `fixtures/` | Seed data files (JSON) for every model — used to populate a dev/test database with realistic starting data |
| `tests/` | Automated tests covering cohorts, courses, and team-maker functionality |

## 3. What is the Pipfile?

The Pipfile is the dependency declaration file used by **Pipenv**. It records which external libraries the project needs, splits them into `[packages]` (needed in production) and `[dev-packages]` (linting, testing, debugger — never installed on the server), and pins the Python version under `[requires]`. The companion `Pipfile.lock` is auto-generated and records exact resolved versions of every package, making builds fully reproducible across machines.

## 4. Key packages

| Package | What functionality does it provide and why? |
|---------|---------------------------------------------|
| django | The core web framework. Provides the ORM (Python classes → database tables), URL routing, request/response cycle, admin interface, and management commands like `migrate`. Everything else in the project sits on top of it. |
| djangorestframework | Extends Django to build JSON APIs instead of HTML pages. Adds `APIView`/`ViewSet` classes, serializers, and built-in handling for GET/POST/PUT/DELETE. This project is a pure API backend serving a React frontend, so DRF is what makes that possible. |
| django-allauth | Handles OAuth2 social authentication — specifically the GitHub login flow. Manages the redirect to GitHub, receives the token back, and creates or links a local user account. Pinned to `0.54.0` because its API changed significantly across versions and the code in `views/github/` and `views/oauth2/` depends on a stable interface. |

## 5. What does `decorators.py` do?

A decorator is a Python feature that wraps a function with extra behaviour without changing the function's own code. You apply one by placing `@decorator_name` directly above a function definition. When that function is called, the decorator's wrapper runs first and decides whether to continue or stop.

`decorators.py` defines two: `@is_instructor()` and `@is_staff()`. Both follow the same pattern:

1. Check whether the currently logged-in user belongs to a specific Django group (`Instructors` or `Staff`)
2. If yes — call through to the original view function normally
3. If no — immediately return a `401 Unauthorized` response, and the view never runs

This is the project's lightweight role-based access control. Instead of copy-pasting the same group-check into every view, a single `@is_instructor()` line at the top of a function handles it.

## 6. What is a serializer, and how does it fit the request/response cycle?

A Django model is a Python object. An HTTP response must be JSON text. A serializer is the translator between the two.

- **Request → model** (deserializing): the serializer takes raw JSON from the request body, validates it (correct types? required fields present?), and converts it into a model instance that can be saved to the database.
- **Model → response** (serializing): the serializer takes a model object and converts it to a Python dictionary, which DRF renders as JSON back to the client.

`NssUserSerializer` in `serializers/nssuser_serializer.py` is a `ModelSerializer`. Its inner `Meta` class declares which model to use (`NssUser`) and which fields to expose (`slack_handle`, `github_handle`, `mentor`, `user`). Fields not listed are never sent to the client — an important security boundary that prevents accidentally leaking sensitive data.

## 7. One model and what it represents

**`NssUserCohort`** (`models/people/nssuser_cohort.py`) represents the real-world fact that *a student has been enrolled in a cohort*. It has:

- `nss_user` — a foreign key to the student
- `cohort` — a foreign key to the cohort
- `is_github_org_member` — a boolean tracking whether the student has been added to the GitHub organisation for that cohort

The `unique_together = ("nss_user", "cohort")` constraint means the database will reject any attempt to enrol the same student in the same cohort twice.

The API needs to track this because a student can move through multiple cohorts over time, and instructors need to know exactly which cohort a student currently belongs to in order to show them the right curriculum, assessments, and team assignments.


## 8. Views vs. viewsets

| Type | Example class | When to use it |
|------|--------------|----------------|
| Plain view (`@api_view`) | `notify` in `views/notify.py` | The endpoint does one specific thing that doesn't fit a resource pattern — sending a notification, triggering a job, returning a computed result. You define the URL manually. |
| ViewSet | `CohortViewSet` in `views/cohort_view.py` | You're exposing a resource (cohort, student, book) that needs standard CRUD operations. Groups `create`, `list`, `retrieve`, `update`, and `destroy` in one class. DRF's router generates the URLs automatically. |

A plain view is just a Python function decorated with `@api_view`. It handles exactly one HTTP method and does one job. A ViewSet is a class that groups all the related actions for a resource together so the router can wire them to the right URLs and HTTP verbs without manual configuration.

## 9. What replaces templates and why?

In the classic Django MTV pattern, the Template layer decides how data is presented — it takes a model object and renders it into HTML.

This project has no HTML templates because it has no browser UI of its own. The React frontend is a completely separate application. Instead of templates rendering HTML, **DRF serializers render JSON**. The serializer takes a model object and produces a structured JSON response, and the React app decides how to display that data on screen.

This makes sense because:
- The same JSON endpoint can serve a web app, a mobile app, or any other client without the server caring which
- Rendering HTML server-side would couple the backend to one specific presentation, defeating the purpose of a separate frontend
- JSON is a neutral data format — the "template" responsibility (layout, styling, interactivity) belongs entirely to the client