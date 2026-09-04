# ZenSched Radon-Tester Reference Kit

A copy-pasteable setup for a 1–3 person radon-testing shop (short-term charcoal/electret/CRM, long-term alpha-track, post-mitigation confirmation, commercial) that wants an AI assistant to run place-and-retrieve scheduling, GPS-verified device photos, a local closed-house + pCi/L log, and invoicing. ZenSched handles the live schedule, the tester's phone app, GPS check-ins at the property, the Place Record, and the Retrieve Record. A small local database on your computer holds your clients, properties, prices, tests, visit summaries, and invoices.

**You do not need to know how to program or write SQL to use this.** You type plain English to your AI assistant ("schedule this week", "add a short-term at Walsh", "what did Kim read at Maple", "who owes me money?") and the AI does the work using two tools you set up once. Setup takes about 15 minutes and is the only technical part.

If you *are* a developer, skip to [For developers](#for-developers).

## What this kit is not — read this first

**What it is:** GPS-verified proof that a tester placed a device and later retrieved it, a Place Record (device photo + closed-house Yes/No), a Retrieve Record (pCi/L + device photo), a local extract of those records for your own files, and invoices built from retrieved tests.

**What it is not:**

- **Not an official ANSI/AARST MAH-2023 measurement, not a certified radon report, and not an NRPP / NRSB / C-NRPP device PDF.** `closed_house_log` is *your* copy of what the tester typed on the phone (dates, property, closed-house, pCi/L). The pCi/L on the Retrieve Record is a **field note**, not the number from the certified CRM / lab PDF. This kit is not a Health Canada remediation decision and not a substitute for whatever your state and certifying body require you to issue. Iowa DPH, Health Canada, and every other jurisdiction still want *their* report. This kit does not produce it and does not claim you are certified because you used it.
- **Not a mitigation design and not a real-estate disclosure.** A high reading in this kit is a number plus a photo. It is not a fan spec, not a system sketch, and not the form a seller hands a buyer.
- **Not a signed legal document.** Neither form has a signature field. On ZenSched a signature field replaces the Submit button, so adding one would make every stop look like the tester (or the occupant) had signed something. Submitting the form is just submitting the form.
- **Closed-house is self-reported.** The Place Record asks Yes/No. GPS proves the tester was at the address; it does not prove windows stayed shut for 48 hours.

If any of those is a deal-breaker, this kit is not for you. If you want place/retrieve cadence, door-GPS, and a local extract you can file next to your real certifying-body report, read on.

## What lives where

**ZenSched (source of truth for what happened, when, and where):**

- Locations (client properties with GPS coordinates; the check-in radius is a **policy** setting)
- Workers (testers with the mobile app)
- Events (one "Radon test" job per property, renewed every 60 days)
- Shifts (each place visit and each retrieve visit, with push notifications to the tester)
- GPS punches (check-in/check-out with distance-from-the-pin verification)
- The Place Record form (device photo, closed-house Yes/No, notes) and every submission
- The Retrieve Record form (pCi/L, device photo, notes) and every submission
- Timesheets (verified hours worked)

**Local SQLite database (`radon.db`, on your computer):**

- Client contact, per-test rate, frequency (annual / biennial / on-demand), next test date
- Properties (places), including access notes (gate code, lockbox, dog) that **never leave your computer**
- Your price list (short-term, long-term, post-mitigation, commercial)
- Testers, including NRPP/NRSB/state license numbers that **never leave your computer**
- Tests with a summary of each Place Record and Retrieve Record, the closed-house log, and invoices
- Your settings (timezone, default tester, invoice prefix, both form ids, action level)

**Never duplicated:** the live schedule, punches, timesheets, and report photos stay in ZenSched. The local database only stores *references* to them plus a short per-test summary so you can answer "what did we read at Walsh" without paying to re-read reports.

### Privacy note

Gate codes, lockbox numbers, alarm words, tester certification numbers, device serials, and client names are stored only in the local database. `SKILL.md` forbids the AI from putting them into any ZenSched field. The location label is the property code plus street (`P-1 - 4412 Maple Street`); the event title is `Radon test - 4412 Maple Street`. Give access notes to your tester yourself, by whatever channel you trust. ZenSched only ever sees the property code, the street address, and the GPS pin.

## How it works day to day

Your AI assistant has two sets of tools:

1. **ZenSched tools** (`location_create`, `shift_create`, `form_submissions`, `shift_list`, ...) that talk to ZenSched over the internet.
2. **A SQLite tool** (`sqlite_query`, `sqlite_execute`) that reads and writes `radon.db` on your computer.

When you say "schedule this week," the AI reads who is due from the local database (`visits_due`: place or retrieve dates in the next 7 days), creates one shift per stop on ZenSched, and tells you what it did. Your tester sees the stops in the app, checks in at the property (GPS-verified), places or retrieves the device, fills in the matching form with a photo, and checks out. Later you say "record this week's visits" and the AI pulls the completed shifts and records, saves a summary locally, marks the test placed or retrieved, and flags closed-house No or a reading at or above your action level (default 4.0 pCi/L). "Closed-house log for September" is a local query. You never run SQL yourself. `SKILL.md` in this repo is the instruction sheet that teaches the AI how to do all of this; you paste it into your AI tool once.

A typical **test costs about $0.70** on ZenSched: two visits × (GPS in $0.10 + GPS out $0.10 + reading a photo form $0.15). Geocoding a new property is $0.03 once. The AI states the cost before it spends.

**Events are capped at 60 days.** One location per property, reused forever. One event per property, rolled every ≤60 days (the kit stores `event_valid_until` locally). A short-term test (place Monday, retrieve Thursday) fits in one event. A long-term test (retrieve at +90 days) rolls a new event before that retrieve shift is created.

## Setup

### 0. What you need

- **An AI tool that supports MCP.** These instructions use Claude Desktop (Windows or Mac). Cursor works too.
- **Node.js 20 or newer.** The SQLite tool runs on it. Download the LTS installer from [nodejs.org](https://nodejs.org/) and run it with the defaults. This is the only software install.
- You do **not** need the `sqlite3` command-line program, Python, or Git.

### 1. Make a folder for your data

Create a folder where the database will live and write down its full path. Examples:

- Windows: `C:\Users\YourName\radon`
- Mac: `/Users/yourname/radon`

The database file will be created automatically inside this folder the first time the AI uses it.

### 2. Add both tools to your AI's config file

Open the MCP configuration file for your AI tool:

- **Claude Desktop, Windows:** `%APPDATA%\Claude\claude_desktop_config.json` (paste that into the File Explorer address bar)
- **Claude Desktop, Mac:** `~/Library/Application Support/Claude/claude_desktop_config.json` (in Claude Desktop: Settings → Developer → Edit Config)
- **Cursor:** Settings → MCP → Add new global MCP server

Paste in the contents of `mcp.json.example` from this repo, then change one line, the `SQLITE_PATH`, to point at your folder from step 1 plus `\radon.db` (Windows) or `/radon.db` (Mac):

```json
{
  "mcpServers": {
    "zensched": {
      "url": "https://mcp.zensched.com/mcp",
      "headers": { "Authorization": "Bearer zsc_your_key_here" }
    },
    "radon-db": {
      "command": "npx",
      "args": ["-y", "easy-sqlite-mcp"],
      "env": { "SQLITE_PATH": "/Users/yourname/radon/radon.db" }
    }
  }
}
```

**Windows path gotcha:** inside a JSON file every backslash must be doubled. Write `"C:\\Users\\YourName\\radon\\radon.db"`, not `"C:\Users\..."`. A single backslash will silently break the config.

**Leave `zsc_your_key_here` exactly as it is for now.** You do not have a key yet. The ZenSched tools that create your account work without one, and you will fill this in during step 3.

Save the file and **fully quit and reopen** your AI tool (on Mac, Cmd-Q; on Windows, right-click the tray icon → Quit). It only reads this file on startup.

### 3. Create your ZenSched account

In a new chat, type:

> Call `zensched_guide`, then call `account_create` with org_name "My Radon Testing Co" (use my real business name if I told you one). Show me the `zsc_` key it returns.

Copy the `zsc_` key. Go back to the config file from step 2, replace `zsc_your_key_here` with your real key, save, and fully quit and reopen the AI tool again.

Some clients can adopt the key mid-session with `account_use_key`; you can ask the AI to try that to keep going immediately, but still update the config file so the key survives restarts. Keep the key private; it is the password to your account.

### 4. Create the database tables

Open `schema.sql` from this repo in any text editor, copy the whole thing, and paste it into the chat with this message in front of it:

> Create these tables in my radon database. Run each statement one at a time using the SQLite tool, then list the tables to confirm.

The AI will run the statements one at a time and confirm the tables exist. The `radon.db` file now exists in your folder, pre-loaded with a starter price list you can change.

If you happen to have the `sqlite3` command-line tool, `sqlite3 radon.db < schema.sql` does the same thing, but it is not required.

### 5. Teach the AI the workflow

Paste the contents of `SKILL.md` into your AI tool as standing instructions. In Claude Desktop, create a Project and put it in the project instructions; in Cursor, save it as a rule. Then tell it your basics once:

> My business is ClearAir Radon in Des Moines, Iowa (Central time). Save that in settings, and set up the Place Record and Retrieve Record forms.

It writes those to the `settings` table, creates both forms on ZenSched (free), and saves the form ids so every stop gets them automatically.

**Check-in radius.** The default pin uses `checkin_radius_m=75` on `location_create`, but ZenSched **enforces** the radius through the account's policy, not per property. With geofencing on it raises anything under 100 m to about 91 m (300 ft), so 75 behaves as roughly a house-and-driveway circle. For a warehouse, a large lot, or a pin that lands on the road, ask the AI to "set the check-in radius to 200 m" (`policy_update`) or to move the pin onto the building (`location_update`, free). Do not ask it to widen the radius "on that location" — that field is informational only.

### 6. Funding (only when asked)

The first 200 ZenSched tool calls per day are free. Some things are metered: creating a location (geocoding, $0.03), inviting a tester ($0.25), each GPS-verified check-in or check-out ($0.10), and reading a Place or Retrieve Record ($0.05, or $0.15 when it has photos). When a metered call happens without funds, the AI will get a `payment_required` response and tell you how to add the $5 activation deposit, which is credited to your balance. You will not be charged without seeing this first.

A typical test is about $0.70 (two visits × in + out + photo record). A tester doing 4 tests a week is about $2.80 in meters that week, plus $0.03 the first time you add each property. The AI states the cost before it spends.

## Using it

Everything after setup is plain English. Examples:

- "Add Dana Walsh, dana@example.com, 515-555-0144, 4412 Maple Street, Des Moines IA 50312. Short-term $175, place Monday 9, retrieve Thursday. Basement. Gate code 2281."
- "Add a listing test for realtor Pat Okonkwo at 890 Walnut Ave, Ames, Tuesday 11, $175. Vacant, lockbox 4092."
- "Invite Kim Alvarez, kim@example.com, and make her the default tester."
- "Schedule this week for Kim."
- "Record this week's visits."
- "Closed-house log for last week."
- "Any high readings?"
- "Draft invoices for everyone with uninvoiced work."
- "Who still owes me money?"
- "Dana paid INV-2026-0001."
- "Add a long-term at the warehouse on 22nd."

See `QUICKSTART.md` for the first-week walkthrough and `example-workflow.md` for exactly which tools the AI calls behind each of these.

### What "invoice" means here

"Draft an invoice" records the invoice in your database (number, date, due date, amount, which tests) and the AI writes out a plain-text invoice you can paste into an email or text message, with a line per test and a note that both visits were GPS-verified. It does **not** generate a PDF, email it for you, or collect payment. Invoices do not list pCi/L, device serials, or license numbers unless you ask. When the client pays, tell the AI ("Dana paid INV-2026-0001") and it marks it paid. If you outgrow this, the invoice records are simple enough to import into any accounting tool.

## Mobile app for testers

- **Android:** [Google Play](https://play.google.com/store/apps/details?id=com.zensched.app)
- **iOS:** [TestFlight](https://testflight.apple.com/join/Wp51m5Yq)

When you invite a tester, they get an email, install the app, and can immediately see their stops, check in and out with GPS verification, and fill in the Place Record or Retrieve Record with a photo. Both forms are attached to the property's event, so both can appear on the phone — place visit fills Place Record only; retrieve visit fills Retrieve Record only. There is no signature step — they tap Submit.

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| AI says it has no ZenSched tools | Config file not saved, or the app was not fully restarted | Check the JSON is valid (paste it into [jsonlint.com](https://jsonlint.com)), then quit and reopen the app |
| AI says it has no SQLite / `radon-db` tools | Node.js not installed, or bad `SQLITE_PATH` | Install Node.js LTS; on Windows check every backslash is doubled |
| `SQLITE_PATH` points nowhere / "unable to open database" | Folder from step 1 does not exist | Create the folder; the file is created automatically but the folder is not |
| ZenSched tools return an auth error | Key still says `zsc_your_key_here`, or was pasted with a space | Re-paste the key, restart |
| `payment_required` | Metered call with no balance | Follow the instructions in the response; $5 deposit |
| AI creates shifts at the wrong hour | Timezone not set | "Set my timezone offset to -05:00 in settings" (use your own offset) |
| Shift creation fails for a long-term retrieve | The property's 60-day ZenSched event has expired | Say "renew the events"; the AI runs the roll-over in `SKILL.md` and retries |
| Tester's check-in not GPS-verified at a house | Geocoded pin is at the mailbox, tester parked far away, or a large lot | Ask the AI to widen `checkin_radius_m` with `policy_update` (not on the location), or run `location_update` / `location_refine` ($0.10) |
| Tester does not see the Place or Retrieve Record | Form not assigned to that property's event | "Attach both radon forms to that property's event" (`form_assign(event_id=...)`). That installs on existing shifts — do not cancel and recreate the shift. |
| Tester filled Retrieve Record on a place visit | Both forms are on the event | Ask them to submit Place Record on place days only; the AI matches by form id + date |
| "Closed-house log" comes back empty | Visits not recorded yet | "Record this week's visits" first |
| AI asks you to run SQL yourself | It does not have `SKILL.md` loaded | Re-paste `SKILL.md` as project instructions |
| AI refuses to put a gate code or device serial in ZenSched | Working as intended | Give it to the tester directly |
| AI offers an MAH-2023 / NRPP certificate or a state disclosure | It shouldn't | This kit does not produce those; use your certifying-body / CRM / lab PDF |

If something is confusing or broken in ZenSched itself, ask the AI to call `feedback_submit` with a description. It is free, needs no account, and a human reads every submission.

## For developers

**Architecture.** Two MCP servers, no application code. The agent is the integration layer; `SKILL.md` is the spec it follows. ZenSched is authoritative for operations (schedule, punches, forms); SQLite is authoritative for CRM, tests, visit summaries, the closed-house log, and billing; each side stores only the other's **integer** IDs, plus a per-test report summary cached locally because submission reads are metered.

**Data model decisions.**

- **clients → properties (places) → tests → visits.** A test is one engagement. Inserting it seeds exactly two `visits` rows (`place` and `retrieve`) via `fill_test_defaults`. `UNIQUE(test_id, visit_kind)` enforces the shape.
- One ZenSched **location** per property, permanent, stored on `properties.zensched_location_id` as an integer. Created with `location_create(name="P-{property_id} - {street}", street_address=..., checkin_radius_m=75, idempotency_key=...)`. `name` is the property code plus street — **never the client or occupant name**. `checkin_radius_m` on `location_create` is informational; the enforced radius is `policy_update(0, '{"checkin_radius_m": N}')`, and with geofencing on the platform raises values under 100 m to 300 ft.
- **Events are capped at 60 days by ZenSched**, so an event cannot span a 90-day long-term soak. Each property holds its *current* event in `properties.zensched_event_id` and its last covered date in `properties.event_valid_until`. The agent creates a new event (`event_create(location_id, title="Radon test - <street>", start_date, end_date=start+59 days, idempotency_key="event-property-{property_id}-{YYYYMMDD}")`) whenever a visit date is later than `event_valid_until`, calls `form_assign` for **both** forms on it, and updates the row. The new event key is dated on the **new window start** (the retrieve date for a +90 roll) — never the place window's key, which would replay the expired event. `visits_due` exposes `event_needs_roll` per row and `event_idempotency_key` (window-start key when the current event still covers the visit; visit date when a roll is required). `events_expiring` lists properties due for renewal within 14 days. Shifts already created on the old event remain valid. When recording a completed visit whose `event_id` no longer matches a property, the agent falls back to `event_get(event_id).location_id` against `properties.zensched_location_id`.
- **Cadence is next-test-date, not a weekday mask.** `clients.service_frequency` is `annual | biennial | on-demand`. Real-estate work is on-demand. `visits_due` is every planned visit with `scheduled_date <= today+7` and no `zensched_shift_id` yet, joined to an active test/property/client, emitting `start_iso` / `end_iso` and the shift `idempotency_key`. One test produces two rows, on two dates.
- **The `advance_next_test_on_retrieve` trigger** sets `last_test_date` and `next_test_date` when `tests.status` becomes `retrieved`: +1 year / +2 years / NULL. Recording a one-off on an annual client also moves the cadence; `SKILL.md` tells the agent to set the date back if the owner says so.
- **The `mark_test_from_visit` trigger** sets `tests.status` to `placed` when the place visit is completed, and to `retrieved` when the retrieve visit is completed.
- Rate lives on the **test** (`amount`). The insert trigger fills it from an explicit value, else `clients.service_rate` when the test uses that client's default `service_id`, else the service list price (so a long-term on a short-term account does not inherit $175). `services.soak_days` (3 or 90) fills `retrieve_date` when the owner does not name one.
- `visits.zensched_shift_id` and `testers.zensched_worker_id` are integer `UNIQUE`. `tests.place_report_dc_id` / `retrieve_report_dc_id` hold the form `submission_id`s. `closed_house` is `CHECK`-constrained to the Place Record labels (`Yes` / `No`).
- `fill_visit_tester` sets `tester_id` from `zensched_worker_id` when the agent leaves it NULL. `fill_visit_defaults` fills start time and duration (30 / 30) from settings.
- `tests.test_no` is auto-assigned by trigger as `{prefix}-{YYYY}-{0001}` (`RDN-2026-0001`). `invoices.invoice_number` is `{prefix}-{YYYY}-{0001}`.
- **`closed_house_log`** is a view over placed and retrieved tests. It does not transmit anything and is not a lab report.
- `properties.access_notes`, `testers.cert_no`, `tests.device_serial`, and `clients.client_name` are the columns that must never be sent to ZenSched; `SKILL.md` rule 6 enforces it. `visits_due` still *selects* `access_notes` and `client_name` so the agent can talk to the owner; only the property code + street go to ZenSched.
- `PRAGMA foreign_keys = ON` is in `schema.sql` and `SKILL.md` tells the agent to run it per session; SQLite does not persist it.

**Forms.** Created once with `form_create`; the exact `fields_json` for each is in `SKILL.md` and `example-workflow.md` (byte-identical) and was validated against ZenSched's `_validate_fields`. Every field carries an explicit `identifier` so submission `data` keys are stable (Place: `device_placed`, `closed_house`, `notes`, section `sec_place`; Retrieve: `pci_l`, `device_retrieved`, `notes`, section `sec_retrieve`). Option keys are derived by ZenSched from the labels (lowercase, non-alphanumerics → `_`, truncated at 30 characters); `Yes` / `No` become `yes` / `no`. **No `signature` field** — the phone keeps a Submit button, and submitting is not a legal attestation. Neither form is an official MAH-2023 / certified radon report / NRPP device PDF; `pci_l` is a field note. Photos are `max_images: 1`. Attaching is `form_assign(form_id, event_id=..., idempotency_key=...)` for **both** forms on every event — that installs on existing shifts; do not cancel and recreate. Both can appear on every shift; the tester fills the matching one.

**Idempotency keys.** Deterministic, derived from local IDs:

- location: `loc-property-{property_id}`
- event: `event-property-{property_id}-{YYYYMMDD window start}`
- shift: `shift-test-{test_id}-{place|retrieve}-{YYYYMMDD}` for the first stop of that kind that day; a same-day second visit, a tester swap, or any replacement after `shift_cancel` appends `-2`, `-3`, … so a cancelled key is never reused (ZenSched replays the cached response for 24 hours)
- worker: `worker-{email}`
- forms: `form-place-record`, `form-retrieve-record`; assignments: `assign-place-record-{event_id}`, `assign-retrieve-record-{event_id}`

ZenSched caches idempotent responses for 24 hours.

**Timestamps.** `shift_create` takes `start` and `end` in ISO 8601 with an explicit offset. Always use the business's local offset from `settings.timezone_offset` (e.g. `2026-09-07T09:00:00-05:00`), never `Z`. The view builds these strings so the agent does not have to. The offset is a fixed setting, not a zone name, so it must be updated when daylight-saving time starts or ends (`SKILL.md` rule 8; `example-workflow.md` shows the November flip to `-06:00` for Des Moines before the December long-term retrieve). Saskatchewan has no DST.

**Metered reads.** `form_submissions` and `form_export` bill $0.05 per submission read ($0.15 with media); `form_export` is preferred for a week at a time. The kit stores the summary and media URLs on `tests` on first read so later closed-house-log questions are answered from SQLite. `shift_list`, `shift_status`, `event_get`, and `timesheet_export(mode="hours"|"raw")` are free.

**SQLite MCP server.** `mcp.json.example` uses [`easy-sqlite-mcp`](https://github.com/chenkumi/easy-sqlite-mcp) (Node, `better-sqlite3`, `SQLITE_PATH` env var). Its `sqlite_execute` calls `prepare()`, so it accepts **one statement per call**; `schema.sql` is written so every statement stands alone and is idempotent. Any SQLite MCP server with read and write tools will work; adjust the tool names in `SKILL.md`.

**Schema test.** The schema was verified by splitting the file into its 61 statements with `sqlite3.complete_statement` and executing each individually (as the MCP server does) twice for idempotency (seed rows not duplicated), then exercising: all 8 tables, 8 views, and 13 triggers present; every view on an empty database; the `fill_test_defaults` trigger for short-term retrieve **+3 days** (2026-09-07 → 2026-09-10), long-term retrieve **+90 days** (2026-09-07 → 2026-12-06, not +3 months / Dec 7), post-mitigation +3, commercial protocol fallback `short_term`; amount from explicit value, from `clients.service_rate` when the test uses that client's default service, and from the list price when it does not (long-term $225 / commercial $250 on a $175 short-term account); `number_test` (`RDN-2026-0001`, explicit number kept); two visits seeded per test with `UNIQUE(test_id, visit_kind)`; `fill_visit_defaults` start `09:00` and duration 30/30; `fill_visit_tester` from `zensched_worker_id`; `sync_place_visit_date` / `sync_retrieve_visit_date` on planned unshifted rows; `mark_test_from_visit` place→`placed` / retrieve→`retrieved`; `advance_next_test_on_retrieve` for annual (+1 year, 2026-09-10 → 2027-09-10), biennial (+2 years → 2028-09-10), and on-demand (NULL); `UNIQUE` on `zensched_shift_id` and `testers.zensched_worker_id`; every `CHECK` (client_type, frequency, `preferred_start` including rejected `HH:MM:SS`, foundation, device_type, protocol, closed_house, negative `pci_l`, visit_kind); `visits_due` `start_iso` / `end_iso` / `idempotency_key` / worker / 30- and 45-minute durations; `event_needs_roll` flipping exactly when `event_valid_until < scheduled_date`; `event_idempotency_key` matching the window start (`event-property-1-20260907`) on a retrieve that still fits the event and the visit date (`event-property-1-20261206`) on a +90 roll; inactive, cancelled, already-shifted, and +20-day rows excluded; `events_expiring` within 14 days; `tests_awaiting_retrieve` / `tests_high` (6.2 vs 4.0, 1.8 omitted) / `closed_house_log`; invoice numbering (auto `INV-2026-0001`, explicit number kept); `tests_to_invoice` / `invoices_outstanding` filters; cascade delete and tester set-null; `updated_at`; integer types on ZenSched ID columns. Both form payloads validated against `_validate_fields` (4 + 4 fields, no signature, SKILL.md byte-identical to example-workflow.md, option keys `yes`/`no` ≤ 30 characters, `device_placed` / `device_retrieved` `max_images` 1). 139 checks, all passing.

## Support

- ZenSched docs: <https://www.zensched.com/docs/>
- Tool reference: <https://www.zensched.com/docs/tools/>
- Feedback: ask your AI to call `feedback_submit` (categories: `bug`, `friction`, `missing_capability`, `docs`, `billing`, `feature`, `other`)

## License

MIT. See `LICENSE`.
