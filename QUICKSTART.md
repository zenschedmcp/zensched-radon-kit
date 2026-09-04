# Quickstart

Setup is about 15 minutes, once. After that everything is plain English to your AI. Each step below tells you what to do and, where relevant, exactly what to type to the AI.

You need: Claude Desktop (or Cursor) and [Node.js LTS](https://nodejs.org/) installed. Nothing else.

Before you start, read the "What this kit is not" section of `README.md`. Short version: this is GPS-verified place-and-retrieve proof plus a local extract of the Place Record and Retrieve Record. It is **not** a certified lab report and **not** a state disclosure.

## 1. Make a data folder

Create a folder such as `C:\Users\YourName\radon` (Windows) or `/Users/yourname/radon` (Mac). Note the full path.

## 2. Add the two tools to your AI's config

Open the config file:

- **Claude Desktop, Windows:** `%APPDATA%\Claude\claude_desktop_config.json`
- **Claude Desktop, Mac:** `~/Library/Application Support/Claude/claude_desktop_config.json`
- **Cursor:** Settings → MCP → Add new global MCP server

Paste this in and fix only the `SQLITE_PATH` line to match your folder from step 1:

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

- On Windows, double every backslash: `"C:\\Users\\YourName\\radon\\radon.db"`.
- Leave `zsc_your_key_here` as it is. You get the real key in the next step.

Save, then **fully quit and reopen** the AI app.

## 3. Create your ZenSched account

Type to the AI:

> Call zensched_guide, then account_create with org_name "ClearAir Radon". Show me the zsc_ key.

Copy the key into the config file in place of `zsc_your_key_here`. Save. Quit and reopen the app once more. (You can also ask the AI to call `account_use_key` with the key to continue right away, but update the file anyway so it sticks.)

## 4. Create the database tables

Copy the full contents of `schema.sql` and paste it into the chat with this line above it:

> Create these tables in my radon database. Run each statement one at a time with the SQLite tool, then list the tables to confirm.

## 5. Give the AI its instructions

Paste `SKILL.md` into the AI as standing instructions (Claude Desktop: a Project's instructions; Cursor: a rule). Then:

> My business is ClearAir Radon in Des Moines, Iowa, Central time. Save that to settings and create the Place Record and Retrieve Record forms.

The AI saves your settings and calls `form_create` twice (free) to build the two forms your testers fill in: Place Record (device photo, closed-house Yes/No, notes) and Retrieve Record (pCi/L, device photo, notes). No signature. It stores both form ids so every stop gets them.

## 6. Add your first two tests

> Add Dana Walsh, dana@example.com, 515-555-0144, 4412 Maple Street, Des Moines IA 50312. Homeowner, short-term $175, place Monday 2026-09-07 at 9, retrieve Thursday 2026-09-10. Basement. Gate code 2281. Charcoal canister.

> Add a listing test for realtor Pat Okonkwo, pat@example.com, 515-555-0190, 890 Walnut Ave, Ames IA 50010, place Tuesday 2026-09-08 at 11, $175. Vacant house, lockbox 4092.

Behind the scenes the AI inserts each client, property, and test (which seeds a place visit and a retrieve visit), calls `location_create` (geocode, $0.03, may trigger the $5 activation deposit the first time), creates a 60-day `event_create` for the property, attaches both forms with `form_assign`, and saves the IDs. Gate / lockbox notes go only into the local database. You just see a confirmation.

## 7. Invite your tester

> Invite Kim Alvarez at kim@example.com as a tester and make her my default.

Kim gets an email ($0.25), installs the app ([Android](https://play.google.com/store/apps/details?id=com.zensched.app) / [iOS TestFlight](https://testflight.apple.com/join/Wp51m5Yq)), and activates. Give her the gate code and lockbox yourself; the AI will not put them in ZenSched.

## 8. Schedule the week

> Schedule this week for Kim.

The AI reads `visits_due`, creates one shift per place or retrieve stop on ZenSched, and summarizes by day. Kim gets a push notification for each. Place visits get the Place Record; retrieve visits get the Retrieve Record (both forms are on the event — she fills the matching one). It will confirm each test is about $0.70 once she punches both visits and you read the photo records.

## 9. After the work is done

> Record this week's visits, show me the closed-house log, then draft invoices for anyone with uninvoiced work.

The AI pulls the completed, GPS-verified shifts and the two forms from ZenSched (reading records is metered, so it tells you the cost first), saves a per-test summary, flags any closed-house No or a reading at or above 4.0 pCi/L, creates invoice records for retrieved tests, and writes out each invoice as text you can paste into an email.

> Dana paid INV-2026-0001.

Marks it paid.

## What next

- `README.md` for the full explanation, the certified-report boundary, troubleshooting table, and developer notes
- `example-workflow.md` to see the exact tool calls behind each step above
