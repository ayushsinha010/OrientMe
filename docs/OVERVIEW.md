# OrientMe — How It Works

This document is a walkthrough of the OrientMe application: what it is, why it exists, how every
piece fits together, and how each feature actually behaves. It's written for someone who has never
seen this codebase before. For setup and run instructions, see the top-level `README.md`.

---

## 1. What OrientMe is, in one paragraph

OrientMe answers one question: **"help me get oriented on this."** You point it at the scattered
information you already have about something you're working on — meeting recordings, documents,
emails, notes — and it reads all of it, keeps it organized, and can tell you at a glance where things
stand, what you're waiting on, what was decided, and what to do next. It doesn't replace your files;
it reads them, understands them, and gives you a fast way back into the context you'd otherwise have
to reconstruct from memory every time.

It was built in response to a very specific real-world trigger: too many meetings happen, too many small
decisions and action items get made in them, and almost none of it gets written down anywhere
durable. OrientMe exists to close that gap automatically.

## 2. The core idea: everything is a "Topic"

Whatever you're trying to stay oriented on — a client project, a department, a recurring process,
a person you work with, a customer account, a sales opportunity — is modeled the same way: a
**Topic**. Every Topic has:

- a **name** and a **type** (`project`, `area`, `process`, `person`, `customer`, or `opportunity`)
- a **one-liner** description
- a list of **related people**
- one or more **local folders** it reads files from (optional — a Topic can also have zero folders
  and only ever receive uploaded/pasted content)

Six types might sound restrictive, but the type is just a label plus a badge color right now — the
underlying behavior (ingestion, chat, tasks, commitments, decisions, risks) is identical across all
six, and the codebase is deliberately built so a seventh type would be a config-table addition, not
a rewrite.

## 3. Architecture at a glance

```
orientme/
  backend/        Django 6.1 + Django REST Framework, SQLite database
    core/         everything lives in this one Django app
      models.py       every database table (see §5)
      views.py        every API endpoint (2700+ lines — see §9 for the map)
      serializers.py  DRF serializers (what JSON shape each model sends to the frontend)
      urls.py         URL routing
      ingestion.py    turns a file on disk into plain text (§6)
      extraction.py   pulls structured facts out of that text — no LLM (§7)
      llm_brief.py    the LLM-powered "Ask" / brief-generation logic (§7)
      recordings.py   the central Recordings-folder auto-pipeline (§8)
      watcher.py      the background thread that polls folders every ~60s (§8)
      corrections.py  chat-typed data corrections ("remove Tanvi") — no LLM (§7)
      mbox_import.py, ics_import.py   email/calendar file parsers
      apps.py         starts the watcher thread when the server starts
    orientme/       Django project settings/urls/wsgi
  frontend/       Next.js 16 (App Router) + React 19 + Tailwind v4, no other UI library
    app/          every page and component (see §10 for the full page-by-page tour)
  scripts/        optional Windows keep-alive scripts (PowerShell)
```

**Stack:** Next.js (front end) + Django REST Framework (back end), as two separate processes.

**Database:** SQLite (`backend/db.sqlite3`, created on first `migrate`), explicitly a "development,
not production" choice.

## 4. Running it locally

See the top-level `README.md` for the full steps. In short:

```bash
# Backend (from backend/)
python manage.py migrate      # first time only, or after a new model change
python manage.py create_admin --username user --password <choose one>
python manage.py runserver 8010

# Frontend (from frontend/, separate terminal)
npm run dev -- -p 3001
```

Then open `http://localhost:3001`. On Windows, `scripts/watchdog.ps1` can keep both servers alive
(it checks every 30 seconds whether ports 8010/3001 are listening and restarts whichever isn't).

A first-time setup also needs an OpenRouter (or compatible) API key entered on the Settings page for
the "Ask" feature to give real answers instead of a raw file list (see §7).

## 5. The data model — every table and what it's for

| Model | Purpose |
|---|---|
| `Topic` | The core entity (§2). `auto_created=True` marks one spun up automatically by the recordings pipeline (§8) rather than by a person. |
| `SourceFolder` | One local folder path a Topic reads files from. A Topic can have several. |
| `IngestedFile` | One piece of content that's been read in — from a folder scan, a direct upload, pasted text, an email, a calendar event, or an auto-transcribed recording. Stores the extracted plain text, a content hash (for cheap re-scan skipping), and `first_added_at` (when it was *first* seen — never changes) vs. `last_ingested_at` (most recent refresh). Its document type (`doc_type`: proposal, meeting transcript, opportunity scorecard, ...) is decided by rules first (structure, title, file name). Since 8 Oct, when the rules cannot trust the name and an LLM key is set, an LLM reads the file's *content* and decides (`doc_type_source = "llm"`, shown as "Read by AI"); a person's own choice is never overridden. Lists show the type/template name first ("Proposal V2") and the real file name second. |
| `ExtractedMeta` | Structured facts pulled out of one `IngestedFile` — meeting title/date/time/attendees/agenda/achieved, plus any "Name: NN hours" entries — via pure Python regex, no LLM (§7). One-to-one with `IngestedFile`. |
| `Task` | An action item (the `status` field still exists in the database but is no longer shown or changed in the UI since 8 Oct). Created automatically from a meeting's action items (LLM-extracted, `source_file` set) or manually by a person (`source_file` null). This is the **Action Items** tab (renamed from "Work" on 29 Sep, since it captures meeting action items, not general work). Since 8 Oct an action item is just the action plus the date it was added — no status dropdown (Backlog / In Progress / Completed) and no due date is shown or editable (the `due_date` column is kept only for the CSV round-trip) — and clicking one shows where it came from (`GET /api/tasks/<id>/source/`: the file, by template name then real name, and the closest-matching passage). |
| `Commitment` | A person's *promise*, not a task — "Sofia will provide the architecture proposal by Friday" is a Commitment; the actual work item it produces is a Task. A Commitment can optionally point at the Task it produced (`linked_task`), but the two are independent — closing one never auto-closes the other. |
| `Decision` | A structured, persistent decision record — distinct from the AI's own free-text `decisions_made` field on a brief, which gets rewritten every time the brief regenerates. This is the thing a person maintains directly, that keeps its own identity over time. |
| `Risk` | Same idea as `Decision`, for tracked risks/blockers — distinct from the AI's own free-text `risks_and_gaps` read. |
| `CaseSummary` | One generated "AI Context Brief" — the structured answer to a question, split into up to 12 possible sections (why now, current state, history, customer thoughts, etc. — see §7). **Append-only**: every generation is a new row, never edited in place, so the Timeline can show how the understood situation changed over time. |
| `ProjectState` | The *other* kind of "current position" — a person's own direct, explicit statement of where things stand, edited in place (not append-only). Takes priority over the AI's own read when the two conflict, and the brief prompt says so explicitly. |
| `Workflow` | Currently only one type: `payroll_approval` — a computed, ready-to-approve view of everyone's hours this month, pulled from every ingested file's `ExtractedMeta.employee_hours`. Fresh row per computation, one-click approve. |
| `ChatMessage` / `GlobalChatMessage` | Every question and answer, per-Topic or across every Topic ("Ask OrientMe" globally). Each assistant message stores exactly which files it cited. |
| `Loop` | A saved free-text question you can re-run with one click later — no scheduler behind it yet, "recurring" today just means "one click away," not "runs automatically." |
| `ScanJob` | Tracks one background bulk-ingest run (folder scan, folder upload, mbox import, ics import) so the frontend can show a real progress bar instead of one long blocking request. |
| `Settings` | A flat key/value store — the LLM provider/key/model, the default directory reminder, the stale-after-days threshold, and everything the recordings pipeline needs (§8, §12). |
| `ConnectorStatus` | Whether someone has clicked "Request Access" for an external connector (Slack, Outlook, Google Drive). **This never grants real access** — no OAuth flow exists. It only gives IT/security a reviewable record of what's been asked for. |
| `RecordingEvent` | One row per recording the auto-watch pipeline has ever found — the full activity/review trail for §8. |
| `Profile` | Extends Django's own `User` with one field: `role` (`admin` or `user`). Since 8 Oct the role no longer gates anything: there is one shared login (`SINGLE_LOGIN_USERNAME` in `settings.py`) and changing Settings/Connectors needs the settings password instead (§9, §10). |

## 6. Getting data in — six ways, all converging on `IngestedFile`

Every way of adding content to a Topic ends up as one or more `IngestedFile` rows with the exact
same downstream treatment (extraction, tasks, brief) — none of these are second-class:

1. **Lookup folder** — point a Topic at one or more real folder paths. "Scan folder now" (or the
   automatic background watcher, see §8) walks each one (top level + one subfolder deep), reads
   every supported file, and skips anything whose content hash hasn't changed since last time.
2. **Upload file** — one file, no folder needed.
3. **Upload folder** — pick a whole folder via the browser's folder picker; every file uploads in
   one action with relative paths preserved.
4. **Paste text** — paste an email body or note directly, with an optional label.
5. **Email export (`.mbox`)** — one `IngestedFile` per message.
6. **Calendar export (`.ics`)** — one `IngestedFile` per event, with `ExtractedMeta` populated
   directly from the event's own real fields (title/date/attendees) instead of being guessed.

**Supported file types** (via `core/ingestion.py`, each gated on an optional dependency being
installed — a machine missing one just quietly doesn't offer that type rather than crashing):
`.txt`, `.md`, `.eml` (built-in), `.msg`, `.docx`, `.pdf`, `.xlsx`/`.xlsm`, `.pptx`, and audio/video
(`.mp4`, `.mov`, `.webm`, `.wav`, `.mp3`, `.m4a`, `.aac`, `.amr`, `.3gp`, `.ogg`, `.flac` — see §8).

Large batches (a folder scan, a bulk upload, an mbox/ics import) never block the request — they run
in a background thread (`_start_scan_job` in `views.py`) and the frontend polls a job-status endpoint
every 1.2 seconds until it's done, showing a real progress bar.

## 7. The intelligence layer — what's LLM, what isn't, and why

A repeated, deliberate design principle throughout this codebase: **use plain Python wherever it can
reliably do the job, and reserve the LLM call for the one thing that genuinely needs judgment.**

**Fully non-LLM (fast, free, deterministic, offline):**
- `looks_like_meeting_transcript(text)` — gates whether a file even looks like a real meeting
  (a real transcript speaker-line pattern, or an explicit "Attendees:" header) before anything else
  runs on it, so a random document never gets a fabricated "meeting title."
- `extract_meeting_metadata(text)` — pulls title/date/time/attendees/agenda/achieved out of a
  transcript via regex.
- `extract_employee_hours(text)` — pulls "Name: NN hours" entries the same way, feeding the payroll
  workflow.
- `resolve_topic(request_text, topics)` — the chat-first home page's routing logic. Scores every
  Topic by keyword overlap against the typed request (Topic name/one-liner weighted far above
  incidental content like task titles, whole-word matching with typo tolerance via `difflib`), and
  returns `matched` / `ambiguous` / `no_match`. No network call at all.
- `detect_correction(question)` (`corrections.py`) — recognizes "remove X" / "rename X to Y" typed
  into a Topic's chat and applies it directly (mutating `ExtractedMeta.attendees`) instead of
  generating a brief for that turn.

**LLM-powered (via OpenRouter, or any OpenAI-compatible endpoint you configure in Settings):**
- **"Ask"** (`llm_brief.generate_brief`) — the actual chat-answer/brief generator. Given a question
  and every ingested file's text, it returns a structured response across up to 12 possible sections
  (why now, current state, history, customer thoughts, customer need, proposed solution, latest
  updates, decisions made, meeting prep, promises made, next step, risks & gaps) — but it's
  instructed to only fill in the sections the *specific question* actually calls for, never pad out
  all 12 by default. Every section that gets filled in also gets its own `_sources` list, so the
  brief page can show exactly which file backs which paragraph. If nothing in the ingested files
  covers part of the question, it says so plainly rather than inventing an answer.
- **Action-item extraction** (`llm_brief.extract_action_items_llm`) — the one remaining LLM call in
  the extraction pipeline, and only for files the non-LLM gate above already confirmed look like a
  real meeting. Everything else about a meeting (title/date/attendees/etc.) is regex; only "what
  did people actually commit to doing" needs real language understanding.
- **Task draft generation** (`llm_brief.generate_task_draft`) — the Action Center's "AI Execute": a
  ready-to-edit draft (a status email, an agenda line, whatever the task's own wording calls for).
  Never sent anywhere itself — only ever returned for a person to review, edit, and copy.
- **Recording auto-routing** (`recordings._suggest_topic_via_llm`, see §8) — decides whether a
  transcribed recording belongs to an existing Topic or describes a new one.

**Graceful no-key fallback, everywhere:** if no LLM key is configured (or a call fails), "Ask" never
blocks — it returns the raw list of ingested files instead of a summary, clearly labeled
(`is_llm: false` + a visible note in the UI), never a silent failure.

## 8. The recordings pipeline — automatic meeting transcription (added 29 Sep 2026)

This is the newest, most involved piece of the system, built to close a real, named gap: too many
meetings, not enough of their action items and decisions ever get captured. It replaces needing a
separate meeting-recorder tool with a native, always-on feature.

### 8a. Two independent background watchers, one shared thread

`core/watcher.py` starts a single background thread when the Django server starts (guarded so it
only runs once, even under the dev server's auto-reloader) that ticks every
`FOLDER_WATCH_INTERVAL_SECONDS` (default 60s, a Django setting) and does two unrelated things each
tick:

1. **Per-Topic folder watch** — re-scans every Topic's own linked `SourceFolder`s automatically, the
   same as clicking "Scan folder now," just without anyone clicking anything. Content-hash dedup
   means a quiet folder costs one cheap `os.walk`, not repeated work.
2. **Central Recordings-folder watch** (`core/recordings.py`) — the actual auto-transcription
   pipeline, described below.

### 8b. What happens to one new recording

A shared folder (configured on the Settings page, `recordings_watch_folder` — empty by default; point it at e.g. a
synced OneDrive folder where Teams cloud recordings and phone recordings get dropped) is watched for any new audio/video file. When one is found:

1. **Transcribe it.** Locally, via `faster-whisper` (no cloud, no API key) — or, if configured, hand
   it off to an external tool instead (see §8d). A small honest header is generated either way
   (`Title: / Date: / Time: / Attendees: ...`), with the title/date recovered from Teams' own
   auto-recording filename convention (`<Title>-<YYYYMMDD>_<HHMMSS>UTC-Meeting Recording.<ext>`)
   when present, falling back to the file's own modified time otherwise.
2. **Try a confident direct match first.** If exactly one existing Topic's *own name* appears as a
   whole word/phrase in the transcript, route straight there — fast, free, no LLM call needed.
3. **Otherwise, ask the LLM to route it** (only if `recordings_suggest_new_topics` is on in
   Settings): does this belong to one of the existing Topics, describe a genuinely new one, or is it
   not really a project at all (a hiring interview, a one-off call)?
4. Depending on the answer:
   - **Matches an existing Topic** → ingested there immediately, `RecordingEvent.status = "routed"`.
   - **Looks like a new project** → **never created automatically.** It's recorded as
     `status = "pending_new_project"` with the LLM's suggested name/one-liner/type held, and shows
     up on the Transcripts page as a card a person must explicitly **confirm** (optionally editing
     the suggested name/type first) or **reject** before any Topic gets created. This human-in-the-
     loop gate was added specifically because the first version auto-created projects silently,
     and that was corrected: the user must always be able to accept or reject a project creation.
   - **Neither** → `status = "needs_review"`, shown under "Other meetings" with a manual
     assign-to-project picker.
   - **Transcription/read failure** → `status = "error"`, with the reason recorded.
5. **When a recording lands in a real Topic** (routed automatically, or confirmed as a new project,
   or manually assigned), the transcript is written as a real `.txt` file **into that Topic's own
   folder** (its first linked `SourceFolder`, or — for a brand-new confirmed project — a fresh
   folder created under `OrientMe Auto-Created Projects/` right next to the watched Recordings
   folder, which is then registered as that Topic's own `SourceFolder`). This means opening the
   project's real folder in Explorer/OneDrive shows the transcript sitting right there, not just
   inside OrientMe's own database — and it flows through the exact same extraction/brief pipeline
   as any other ingested file, no separate code path.

Every one of these outcomes produces exactly one `RecordingEvent` row — nothing happens invisibly.

### 8c. The Transcripts page (`/transcripts`)

Grouped, not a flat list:
- **"Needs your decision"** — pending new-project suggestions, shown first, each an editable
  name/type/one-liner plus **Create project** / **Not a new project** buttons.
- **One box per project** — every recording already routed there, sorted newest-first, with each
  project box itself ordered by its most recent activity.
- **"Other meetings"** — anything with no project match, plus a collapsible count of recordings that
  existed *before* auto-watch was ever turned on (seeded as `pre_existing` on first activation
  specifically so the pipeline doesn't try to bulk-transcribe a whole historical backlog — including
  old hiring-interview recordings, which would be actively wrong to auto-classify as "projects" —
  the moment it goes live).

### 8d. Pluggable transcription engine

The Settings page has an engine selector: **Local Whisper** (default, built-in) or **External
tool**. External mode POSTs the audio file to any URL you configure and expects back
`{"text": "...", "speakers": [...]?}` JSON — this is the integration point for a separate
transcript-diarizer tool (or anything else): point Settings at its endpoint,
no code change needed, and it falls back to Local Whisper automatically if that URL is ever
unreachable. A real speaker list (`speakers`) from an external tool replaces the local engine's
honest "not captured" disclaimer — genuine speaker diarization is the one thing local Whisper can't
do on its own.

### 8e. Settings for this pipeline (all on the main `/settings` page)

| Setting | Meaning |
|---|---|
| `recordings_watch_folder` | The one shared folder being watched. |
| `recordings_suggest_new_topics` | Whether the pipeline tries the LLM-routing step at all for an unmatched recording. When off, an unmatched recording just goes straight to "needs review" — never suggests a new project. |
| `transcription_engine` | `local_whisper` or `external`. |
| `external_transcription_url` | Where to send the audio file when `transcription_engine` is `external`. |

## 9. Backend API map (`core/views.py`, `core/urls.py`)

Everything is a Django REST Framework `APIView` or `ModelViewSet`, routed under `/api/`:

- **`/api/topics/`** (`TopicViewSet`) — full CRUD, plus per-Topic actions: `add_folder`, `ingest`
  (scan), `scan_status`, `upload_file`, `upload_folder`, `paste_text`, `import_mbox`, `import_ics`,
  `ask`, `clear_chat`, `latest_summary`, `summary_history`, `workflow_history`, `export_brief_md`,
  `export_tasks_csv` / `import_tasks_csv`, `export_summary_csv` / `import_summary_csv`,
  `refresh_summary`, `state` (Project Intelligence, GET/PATCH), `meeting_metadata`,
  `compute_payroll`, and `workflows/<id>/approve`.
- **`/api/tasks/`**, **`/api/commitments/`**, **`/api/decisions/`**, **`/api/risks/`**,
  **`/api/loops/`**, **`/api/recording_events/`** — one `ModelViewSet` each, all filterable by
  `?topic=<id>` where relevant. `RecordingEventViewSet` additionally has `assign_topic`,
  `confirm_new_project`, `reject_new_project`.
- **`/api/topics/auto_create/`** (`AutoCreateTopicView`) — collapses "create a Topic, add a folder,
  scan, wait, generate a brief" into one call: give it a folder path (or several), get back a Topic
  that's already being scanned in the background.
- **`/api/orient/`** (`OrientView`) — the public, no-login chat-first resolver: free text in,
  `resolve_topic` decides `matched` (answers immediately) / `ambiguous` / `no_match`.
- **`/api/resolve_only/`** — the same resolution *without* the slow LLM answer call, built
  specifically for a Wox/Raycast launcher plugin that has a short patience window.
- **`/api/calendar/`**, **`/api/sources/`**, **`/api/timeline/`**, **`/api/search/`**,
  **`/api/stats/`**, **`/api/chat/global/`** — cross-project views (§10 covers their pages).
- **`/api/settings/`** — GET/POST the flat key/value config (masked API key on GET). Every POST must carry the settings password (`settings_password` in the body, or an `X-Settings-Password` header) — checked on the server each time; `POST /api/settings/unlock/` only checks it, so the page can unlock. The password is a fixed value read from the `SETTINGS_EDIT_PASSWORD` environment variable (or a `.env` file; an optional git-ignored `backend/orientme/local_secrets.py` also works, template: `local_secrets.example.py`), so it is never in the code; change it and restart. With no password set, Settings cannot be changed at all. The `Settings` table is deliberately not registered in the Django admin, which would bypass the password.
- **`/api/connectors/`** + request/reset — the request-only-never-real-access connector tracker (request/reset also need the settings password).
- **Auth**: `/api/auth/csrf/`, `login/`, `logout/`, `me/`, `change_password/`, `update_profile/` —
  real Django sessions (cookie-based), real password hashing. **One shared login only** (8 Oct):
  `login/` accepts just `SINGLE_LOGIN_USERNAME` (other accounts that exist in the database simply
  cannot sign in), and `register/` + `password_reset/request/` + `confirm/` are switched off (they
  return 403). The login's password is changed from `/profile` while signed in, or with
  `python manage.py changepassword <username>`.
- **HTML surfaces for external launchers** (not meant for the browser UI): `topics/<id>/brief_html/`,
  `orient_html/`, `topic_names/`, `files/<id>/open/`, `folders/<id>/open/` — a Wox/Raycast plugin can
  open a topic's brief as a styled standalone page, and "open source file/folder" launches the real
  file/folder in its native app on whatever machine the Django process runs on.

## 10. Frontend tour — every page

The frontend is plain React 19 + Tailwind v4 (no Redux/Zustand/UI kit). Every page is a client
component; the only server component is the root `layout.js`. Authentication and route-guarding
happen in exactly one place — `AppShell.js` (wrapping every page) delegates to `AuthContext.js`,
which redirects to `/login` whenever nobody's signed in and the current path isn't public.

**Public pages** (no login required — `PUBLIC_PATHS` in `AuthContext.js`):
- **`/`** — the public "Orient me" search box. Type a natural-language question, get routed via
  `resolve_topic` to `matched` (immediate answer) / `ambiguous` (pick a candidate) / `no_match`. This
  is the one surface a non-logged-in person can use at all; everything else needs a real account.
- **`/login`** — the one shared login (sign-up and password-reset pages were removed on 8 Oct).

**The admin console** (everything else, behind login):
- **`/dashboard`** — the real home page once logged in. Needs-attention panel (stale projects, open
  risks), a project grid (urgency badges, stale badges, file counts), and the "+ Create Project"
  modal with two modes: **auto** (give it folder path(s), it scans + generates the first brief in
  the background, polling a progress bar) or **manual** (a bare placeholder Topic with no files).
- **`/topics/[id]`** — the single-project page. A tab strip — **Overview**, **Action Items** (the
  project's own slice of the same list `/tasks` uses — reused, not duplicated), **Commitments**,
  **Decisions**, **Meetings** (stakeholders + meeting-info cards), **Risks**. The Overview is
  the Context Node layout: an optional *What needs your attention* card (overdue / due-soon
  commitments and tasks; it renders nothing when there are none) above the Context Node (Smart
  Suggestions, *Current Position (confirmed)*, executive summary, current objective and position,
  *Next / Waiting / Open questions*, *Recent activity*, Key State, launchers, prompt history), with
  the Project Timeline in a column on the right. (8 Oct 2026 briefly replaced this with an "at a
  glance" first screen, `components/ProjectGlance.js`; on 9 Oct this layout was restored. The component file is kept but no page uses it.) Header actions: Edit Project, Calendar,
  Manage sources, Export/Import (the Markdown/CSV round-trip described in §9).
- **`/transcripts`** — the recordings pipeline's activity feed and decision queue (§8c).
- **`/settings`** — LLM provider/key/model config, the stale-after-days threshold, and the
  recordings-pipeline config (§8e). Always opens locked: pressing Unlock asks for the settings
  password, and the page locks itself again after a successful save.
- **`/tasks`** ("Board" in the sidebar) — the cross-project Kanban board + a month calendar
  side-by-side, filterable to one project. Polls every 5 seconds while open, since a scan/upload
  running elsewhere writes tasks directly with no other notification mechanism.
- **`/calendar`** — a cross-project meetings list (not the small calendar widget — a full list,
  expandable per row for attendees/agenda/outcome).
- **`/sources`** — every ingested file across every project, one searchable/filterable library.
- **`/timeline`** — a cross-project activity feed (meetings ingested, tasks added/completed, status
  updates), newest first — the "what's happened anywhere" counterpart to a single project's own
  Timeline tab.
- **`/statistics`** — company-wide counts (projects/files/meetings/task-status breakdown) plus a
  hand-rolled per-project task bar chart (no charting library).
- **`/actions`** (the "Action Center") — every open task across every project, grouped by project,
  each with an "AI Execute" button that generates a ready-to-edit draft (§7) in a modal (Regenerate/
  Copy).
- **`/profile`** — change your display name or the login's password.
- **Ctrl/Cmd+K anywhere** — a global command palette (`CommandPalette.js`) searching projects,
  stakeholders, tasks, and files server-side (`/api/search/`), debounced, keyboard-navigable.

**Shared components worth knowing:** `TaskBoard.js` (the actual drag-and-drop Kanban, reused by both
`/tasks` and a project's own Action Items tab), `CalendarWidget.js` (a plain month-grid, no date
library), `ProjectTabs.js` (the tab-strip component — genuinely new, everything else was reuse), and
`Sidebar.js` (Projects / Transcripts / Settings, plus a "Recent" list of the last few active
projects).

## 11. What's genuinely NOT built yet (real gaps, not oversights)

- **No live SharePoint/Graph API/email connection** — deliberately deferred. Ingestion is
  local-folder/upload/paste only. Building a live connection needs an Entra ID app
  registration, which is a real organizational decision, not just an engineering task.
- **No type-specific brief templates** — every Topic type gets the same brief shape today; an
  opportunity's "current state vs. desired state" scorecard framing is a planned refinement.
- **No production deployment config** — CORS is hardcoded to localhost, SQLite is the dev database,
  `DEBUG=True`. Fine for where this stands today; not ready to deploy anywhere as-is.
- **No folder-level permission model** — every logged-in User can see every Topic's content; no
  per-folder restriction exists yet (e.g. pricing details may not be open
  to everyone).
- **KRA-level (Key Result Area) roll-up across all Topics for one person, for a whole year** —
  explicitly backlog, not started.
- **Connectors are request-only** — clicking "Request Access" for Slack/Outlook/Google Drive only
  records that someone asked; no real OAuth/integration exists behind any of them yet.

## 12. Quick reference — where things live

```
backend/core/
  models.py            every table (§5)
  views.py             every endpoint (§9) — ~2700 lines, organized by ViewSet/APIView per resource
  serializers.py        JSON shapes
  urls.py              routing
  ingestion.py         file → plain text (§6)
  extraction.py         plain text → structured facts, no LLM (§7)
  llm_brief.py          plain text → LLM-generated brief/action-items/task-draft (§7)
  corrections.py        chat-typed data corrections, no LLM (§7)
  recordings.py          the central Recordings-folder pipeline (§8)
  watcher.py            the background thread that drives both watchers (§8a)
  mbox_import.py / ics_import.py    email/calendar file parsers
  apps.py               starts the watcher thread on server start

frontend/app/
  page.js                     public search (/)
  dashboard/page.js           project list + create-project modal
  topics/[id]/page.js         single-project page (Overview/Action Items/Commitments/Decisions/Meetings/Risks)
  transcripts/page.js         recordings pipeline activity feed (§8c)
  settings/page.js            all configuration, including the recordings pipeline (§8e)
  tasks/page.js, actions/page.js, calendar/page.js, sources/page.js,
  timeline/page.js, statistics/page.js    cross-project views (§10)
  login/, profile/                                                  auth (one shared login)
  components/                 Sidebar, TaskBoard, CalendarWidget, CommandPalette, ProjectTabs, AppShell
  lib/api.js                  every backend call the frontend makes, in one file
  lib/AuthContext.js          session/role state + route guarding
  lib/format.js               shared date/urgency/type-label helpers
```
