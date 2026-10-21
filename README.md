<p align="center"><img src="docs/logo.png" alt="OrientMe logo" width="320"></p>

# OrientMe

OrientMe is a "where was I?" tool. You point it at the scattered information you already have about
something you are working on (project folders, documents, emails, notes, meeting transcripts and
recordings) and it keeps a one-screen orientation per project: the current position, a timeline, what
is next, what you are waiting for, open questions and action items. You can also ask questions in
plain language and get answers that cite the files they came from. It is aimed at one person or a
small team who attend many meetings and want a fast way back into the context of each project.

It is a local, single-machine app: a Django REST backend with a SQLite database, and a Next.js front
end. Answers use an LLM through an OpenRouter-compatible API (the key is entered in the app and stored
in the local database, never in code); transcription of recordings runs locally with Whisper.

## Features

- **Projects ("topics")** of six types (project, area, process, person, customer, opportunity), each
  with a one-liner, related people and any number of linked local folders.
- **Getting content in:** scan linked folders (top level plus one sub-level, re-scans skip unchanged
  files), upload a file or a whole folder, paste text, import an `.mbox` email export or an `.ics`
  calendar export. Supported files: `.txt`, `.md`, `.eml`, `.msg`, `.docx`, `.pdf`, `.xlsx`/`.xlsm`,
  `.pptx`, and audio/video (`.mp4`, `.mov`, `.webm`, `.wav`, `.mp3`, `.m4a`, `.aac`, `.amr`, `.3gp`,
  `.ogg`, `.flac`).
- **AI Context Brief per project** (current position, next / waiting / open questions, history, risks
  and more) and a per-project and global "Ask" box. Every answer lists the files it drew on. Without an
  API key the app still works and returns the list of ingested files instead of a summary.
- **Deterministic extraction first:** meeting title/date/attendees/agenda, "who said what" speaker
  turns and project routing use plain code; the LLM is only used where judgement is needed (answers,
  action items, content-based document typing, routing of unmatched recordings).
- **Action items, commitments, decisions and risks** per project; clicking an action item shows the
  file and passage it came from.
- **Recordings pipeline:** watch a shared folder for new recordings, transcribe them locally
  (faster-whisper), route each to a matching project, and ask a person to confirm before any new
  project is created. A pluggable "external transcription tool" URL is supported.
- **Document typing and metadata:** rule-based classification (proposal, quotation, meeting
  transcript, scorecard ...) with an optional LLM check of the file content; CSV export/import of file
  metadata, task and brief CSV/Markdown round trips.
- **Cross-project views:** dashboard, transcripts queue, board, calendar, timeline, sources library,
  statistics, action center, and a Ctrl/Cmd+K command palette.
- **One shared login**; changing anything on the Settings page needs an additional settings password.
- **Optional launcher plugins** (Raycast and Wox) in `integrations/`.

For a longer walkthrough of the data model, API and pages, see [`docs/OVERVIEW.md`](docs/OVERVIEW.md).

## Tech stack

| Part | Details |
|---|---|
| Backend | Python, Django `>=6.1,<7` (tested with 6.1.2), Django REST Framework 3.18, django-cors-headers 4.9 |
| File readers | python-docx, pypdf, openpyxl, python-pptx, extract-msg, stdlib `email` / `mailbox` |
| Transcription | faster-whisper 1.2 (CPU, int8), needs `ffmpeg` on the PATH for audio/video |
| Database | SQLite (`backend/db.sqlite3`, created by `migrate`) |
| LLM | Any OpenAI-compatible chat-completions endpoint; OpenRouter by default |
| Optional local LLM | [Ollama](https://ollama.com) with `qwen2.5:3b` for project routing / "Diarize" buttons |
| Front end | Next.js 16.3.5 (App Router), React 19.2.8, Tailwind CSS 4, ESLint 9 |
| Scripts | PowerShell scripts for keeping both servers alive on Windows (optional) |

## Project structure

```
.
├── backend/                  Django project
│   ├── orientme/             settings, urls, wsgi
│   ├── core/                 the one Django app: models, views, serializers, ingestion,
│   │   │                     extraction, llm_brief, recordings, watcher, migrations, tests
│   │   └── management/commands/   create_admin, backfill_* helpers
│   ├── media/                uploaded files and recordings (empty, git-ignored)
│   ├── data/                 optional location for the SQLite file (Docker), git-ignored
│   └── requirements.txt
├── frontend/                 Next.js app (app/ = pages and components, lib/api.js = API client)
├── integrations/
│   ├── raycast/              Raycast extension (TypeScript)
│   └── wox/                  Wox plugin (Python)
├── scripts/                  optional PowerShell run / watchdog scripts (Windows)
├── docs/                     OVERVIEW.md and the logo
├── docker-compose.yml        backend + frontend containers (see "Docker")
└── .env.example              backend environment variables
```

## Prerequisites

- **Python 3.12 or newer** (developed and tested with 3.12.10).
- **Node.js 20.9 or newer** with npm (tested with Node 24; the Dockerfile uses Node 22).
- **ffmpeg** on the PATH, only if you want to transcribe audio/video recordings.
- Internet access on first use of transcription (faster-whisper downloads the model) and for the LLM
  API. Optional: Ollama for the local-LLM features.
- Developed on Windows 11; the code is cross-platform. The Windows PowerShell scripts in `scripts/`
  are the only Windows-only part.

## Setup and run

### Windows (PowerShell)

```powershell
git clone <your-repo-url> orientme
cd orientme

# 1. Configuration: copy the example and set SETTINGS_EDIT_PASSWORD (and DJANGO_SECRET_KEY)
Copy-Item .env.example .env
notepad .env

# 2. Backend
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r backend\requirements.txt
cd backend
python manage.py migrate
python manage.py create_admin --username user --password "choose-a-password"
python manage.py runserver 8010

# 3. Front end (second terminal, from the repository root)
cd frontend
npm ci
npm run dev -- -p 3001
```

### macOS / Linux

```bash
git clone <your-repo-url> orientme
cd orientme

cp .env.example .env          # then edit .env: set SETTINGS_EDIT_PASSWORD (and DJANGO_SECRET_KEY)

python3 -m venv .venv
source .venv/bin/activate
pip install -r backend/requirements.txt
cd backend
python manage.py migrate
python manage.py create_admin --username user --password "choose-a-password"
python manage.py runserver 8010

# second terminal, from the repository root
cd frontend
npm ci
npm run dev -- -p 3001
```

### What you see on first run

Open <http://localhost:3001>. The app redirects to `/login`; sign in as `user` with the password you
chose in `create_admin`. You land on an empty dashboard ("0 active projects"). There is no sample data.
Then:

1. Create a project (Projects > Create Project) and add content: "Manage sources" lets you link a
   folder, upload a file or folder, or paste text.
2. Open **Settings** and press Unlock (the settings password from `.env`), then enter your LLM API key
   and model. Until a key is set, "Ask" returns the list of ingested files instead of an answer.

Notes:

- Only the username `user` can sign in (`SINGLE_LOGIN_USERNAME` in `backend/orientme/settings.py`).
  Other accounts, such as one made with `createsuperuser`, can use the Django admin at
  `http://localhost:8010/admin/` but cannot sign in to the app. To change the login password use the
  Profile page or `python manage.py changepassword user`.
- Run the backend with plain `runserver` (auto-reload on) so the background folder watcher thread
  starts. With `--noreload` the watcher does not start.
- The front end derives the API address from the page's own host (same host, port 8010), so use either
  `localhost` or `127.0.0.1` consistently in the browser. If the backend is on another port, set
  `NEXT_PUBLIC_API_BASE` (see `frontend/.env.example`) and add the front end's origin to
  `CORS_EXTRA_ORIGINS`.

### Production build of the front end

```bash
cd frontend
npm run build
npm run start -- -p 3001
```

### Docker

`docker-compose.yml` builds both services (backend on 8010, front end on 3001). The backend container
runs `migrate` on start and keeps the SQLite file in `backend/data/`. Put `SETTINGS_EDIT_PASSWORD` and
`DJANGO_SECRET_KEY` in a `.env` file next to the compose file, then:

```bash
docker compose up --build
docker compose exec backend python manage.py create_admin --username user --password "choose-a-password"
```

The compose file was checked with `docker compose config` only; the images were **not built or run**
(not verified). The front end container runs the Next.js dev server.

### Optional: keep both servers running on Windows

`scripts/run_backend.ps1` and `scripts/run_frontend.ps1` start each server, `scripts/watchdog.ps1`
restarts whichever port stops listening, and `scripts/setup_background_tasks.ps1` registers both as
Scheduled Tasks. They use paths relative to the scripts folder. Not verified end to end.

## Configuration

### Environment variables (backend)

Read from the real environment, or from a `.env` file in the repository root (or `backend/.env`).
Real environment variables win over the file. See `.env.example`.

| Name | Default | Purpose |
|---|---|---|
| `SETTINGS_EDIT_PASSWORD` | empty | Password required to change anything on the Settings page. If empty (and no `orientme/local_secrets.py`), Settings cannot be changed at all. |
| `DJANGO_SECRET_KEY` | insecure dev value | Django secret key. Set a long random value for any use beyond local development. |
| `DJANGO_DEBUG` | `true` | Set to `false` outside local use. |
| `DJANGO_ALLOWED_HOSTS` | empty | Comma-separated host names (needed when debug is off). |
| `CORS_EXTRA_ORIGINS` | empty | Extra allowed front-end origins, comma-separated. Ports 3000, 3001 and 3010 on `localhost` / `127.0.0.1` are always allowed. |
| `DATABASE_PATH` | `backend/db.sqlite3` | SQLite file location. |
| `WHISPER_MODEL_SIZE` | `base` | faster-whisper model (`tiny`, `base`, `small`, `medium` ...). |
| `FOLDER_WATCH_INTERVAL_SECONDS` | `60` | How often linked folders and the recordings folder are re-scanned. |
| `FRONTEND_URL` | `http://localhost:3001` | Used only to build links in password-reset emails (that feature is switched off). |

Alternative for the settings password: copy `backend/orientme/local_secrets.example.py` to
`backend/orientme/local_secrets.py` (git-ignored) and set the value there.

### Front end

| Name | Default | Purpose |
|---|---|---|
| `NEXT_PUBLIC_API_BASE` | unset (derived from the page host, port 8010) | Full API base URL, e.g. `http://localhost:8000/api`. |

### In-app settings (Settings page, stored in the database)

| Key | Default | Purpose |
|---|---|---|
| `llm_provider` / `llm_base_url` / `llm_model` | `openrouter` / `https://openrouter.ai/api/v1` / `openai/gpt-5.4` | Which OpenAI-compatible endpoint and model are used for answers. |
| `llm_api_key` | empty | The API key. Stored in the local SQLite database, never returned by the API (only a "key is set" flag). |
| `stale_after_days` | `14` | Days without a new brief or file before a project is flagged stale. |
| `recordings_watch_folder` | empty | Shared folder watched for new recordings. |
| `recordings_suggest_new_topics` | `true` | Let the LLM suggest a new project for an unmatched recording (a person always confirms). |
| `manual_drop_folder` | empty | A second watched folder for manually dropped files. |
| `transcription_engine` / `external_transcription_url` | `local_whisper` / empty | Use local Whisper, or POST audio to an external service that returns `{"text": ..., "speakers": [...]}`. |

## Data and storage

- **Database:** `backend/db.sqlite3` (or `DATABASE_PATH`). It is created by `python manage.py migrate`
  and starts empty: no sample data is seeded.
- **Uploaded files and recordings:** `backend/media/` (shipped empty with a `.gitkeep`).
- **Linked folders** are read in place; OrientMe does not copy them.
- **Reset:** stop the server, delete `backend/db.sqlite3` (and the contents of `backend/media/`), then
  run `python manage.py migrate` and `create_admin` again.
- Everything above is git-ignored. Back up the database and `media/` if the content matters.

## Tests and quality checks

```bash
cd backend
python manage.py check
python manage.py makemigrations --check --dry-run    # no pending model changes
python manage.py test                                # 152 tests, no network or real LLM needed

cd ../frontend
npm run build                                        # production build
npm run lint                                         # ESLint (eslint-config-next)

cd ../integrations/raycast && npm install && npx tsc --noEmit    # type check
python -m py_compile integrations/wox/main.py                    # Wox plugin syntax
```

The backend tests use synthetic data and a stubbed LLM. They cover file classification and metadata,
meeting and speaker extraction, action items and their sources, project routing, search, CSV round
trips, the recordings pipeline, the single login and the settings password. Three tests skip by
design: two check the shipped settings password (they run when `SETTINGS_EDIT_PASSWORD` is set) and one
parses a folder of real transcripts when `ORIENTME_TEST_TRANSCRIPTS_DIR` points at one.

As last run: backend 152 tests pass (3 skipped), the front end builds, and `npm run lint` reports
19 errors and 3 warnings from the `react-hooks` rules (for example "setState in effect"). These are
existing findings in the page code, not build failures.

## Notes and limitations

- **Local, single-user design.** Several endpoints are intentionally reachable without a login: the
  public "Orient me" search page and its API (`/api/orient/`, `/api/resolve_only/`,
  `/api/orient_html/`, `/api/topic_names/`, `/api/topics/<id>/brief_html/`), and `/api/files/<id>/open/` and
  `/api/folders/<id>/open/`, which open an ingested file or folder in its native application **on the
  machine running the backend**. Do not expose the backend to the internet or an untrusted network as
  it is.
- **No HTTPS, development settings.** `DEBUG` defaults to on, CORS and CSRF origins are limited to
  local ports, SQLite is the only database, and the server is Django's `runserver`.
- **One shared login**, no per-user data separation or folder-level permissions; sign-up and email
  password reset are switched off.
- **Connectors** (Slack, Outlook, Google Drive ...) on the Settings page only record that access was
  requested; no real integration exists behind them. There is no live SharePoint/Graph/email
  connection: ingestion is local folders, uploads and pasted text only.
- **Transcription** needs `ffmpeg`; recordings are transcribed on CPU, which is slow for long
  meetings. Speaker names come from Teams-style transcripts, or from an LLM grouping step; local Whisper
  cannot identify speakers by voice.
- **LLM content leaves the machine** when you use an API provider: file text is sent to the endpoint you
  configure. The project-routing and "Diarize" features use a local Ollama model instead.
- Code comments mention "the PRD"; that product requirements document is not part of this repository.
- Not verified: Docker image builds, the Windows scheduled-task scripts, the Wox plugin inside Wox, and
  the Raycast extension inside Raycast (only syntax / type checks were run).

## License

Released under the MIT License: see [LICENSE](LICENSE). Replace it with another license if you prefer.
