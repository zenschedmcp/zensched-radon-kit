# Example Workflow: What the AI Does Behind Each Request

This shows the exact tool calls the agent makes for a first week of operation, following `SKILL.md`. The owner only types the quoted lines; everything else is the agent's work. Assumes setup from `QUICKSTART.md` is complete (both MCP servers configured, `schema.sql` loaded, `SKILL.md` given as instructions).

IDs and responses are illustrative. ZenSched IDs are integers.

Shop: **ClearAir Radon**, Des Moines, Iowa, Central time (`-05:00` in September). Two short-term tests (homeowner + realtor listing), one tester, then invoice.

Access notes (gate code, lockbox), any NRPP/NRSB number, and device serials stay in SQLite. They are never sent to ZenSched.

## Session start (every session)

```
sqlite_execute: PRAGMA foreign_keys = ON;
sqlite_query:   SELECT key, value FROM settings;
  → business_name = My Radon Testing Co, timezone_offset = -05:00,
    default_worker_id = NULL, default_shift_start = 09:00,
    default_place_minutes = 30, default_retrieve_minutes = 30,
    invoice_due_days = 14, invoice_prefix = INV, test_prefix = RDN,
    place_record_form_id = NULL, retrieve_record_form_id = NULL,
    event_window_days = 60, action_level_pci = 4.0
```

## "My business is ClearAir Radon in Des Moines, Iowa, Central time."

```
sqlite_execute: UPDATE settings SET value = 'ClearAir Radon' WHERE key = 'business_name';
sqlite_execute: UPDATE settings SET value = '-05:00' WHERE key = 'timezone_offset';
```

> Saved. I'll schedule everything in Central time (-05:00). You don't have the Place Record or Retrieve Record forms yet; they're free to create. Place Record is a device photo plus closed-house Yes/No. Retrieve Record is a pCi/L field note plus a device photo. No signature — these are internal placement/retrieve logs, not an official MAH-2023 measurement, not a certified radon report, and not an NRPP device PDF. Want me to set them up now?

Owner: *"yes"*

```
form_create:
  title: "Place Record"
  idempotency_key: "form-place-record"
  fields_json: (the JSON below, passed as one string)
```

```json
[
  {"type": "section", "label": "Place record", "identifier": "sec_place",
   "text": "Photograph the device in place. Confirm closed-house conditions. This is an internal placement log, not the official ANSI/AARST MAH-2023 measurement, not a certified radon report, and not an NRPP / NRSB / C-NRPP device PDF."},
  {"type": "photo", "label": "Device placed", "identifier": "device_placed", "required": true, "max_images": 1},
  {"type": "select", "label": "Closed house", "identifier": "closed_house", "required": true,
   "options": ["Yes", "No"]},
  {"type": "textarea", "label": "Notes", "identifier": "notes"}
]
```

```
  → form_id: 501, fields: [ ...4 fields echoed with identifiers... ]

sqlite_execute: UPDATE settings SET value = '501' WHERE key = 'place_record_form_id';

form_create:
  title: "Retrieve Record"
  idempotency_key: "form-retrieve-record"
  fields_json: (the JSON below, passed as one string)
```

```json
[
  {"type": "section", "label": "Retrieve record", "identifier": "sec_retrieve",
   "text": "Enter the pCi/L reading as a field note and photograph the device as retrieved. This is an internal retrieve log. The pCi/L here is not the certified CRM / lab / NRPP device PDF and not an official MAH-2023 or Health Canada measurement."},
  {"type": "number", "label": "pCi/L", "identifier": "pci_l", "required": true},
  {"type": "photo", "label": "Device retrieved", "identifier": "device_retrieved", "required": true, "max_images": 1},
  {"type": "textarea", "label": "Notes", "identifier": "notes"}
]
```

```
  → form_id: 502, fields: [ ...4 fields echoed with identifiers... ]

sqlite_execute: UPDATE settings SET value = '502' WHERE key = 'retrieve_record_form_id';
```

> Both forms created. I'll attach them to every property automatically. There is no signature step. On a place visit Kim fills Place Record only; on a retrieve visit she fills Retrieve Record only.

## "Add Dana Walsh, dana@example.com, 515-555-0144, 4412 Maple Street, Des Moines IA 50312. Homeowner, short-term $175, place Monday 2026-09-07 at 9, retrieve Thursday 2026-09-10. Basement. Gate code 2281. Charcoal canister."

```
sqlite_query:   SELECT service_id, price, soak_days, default_minutes FROM services WHERE code = 'short_term';
  → 1, 175.00, 3, 30

sqlite_execute:
  INSERT INTO clients (client_name, client_type, contact_email, contact_phone, service_id, service_rate,
                       service_frequency, preferred_start)
  VALUES ('Dana Walsh', 'homeowner', 'dana@example.com', '515-555-0144', 1, 175.00,
          'on-demand', '09:00');
  → lastInsertRowid = 1

sqlite_execute:
  INSERT INTO properties (client_id, address, city, state, zip, access_notes, foundation)
  VALUES (1, '4412 Maple Street', 'Des Moines', 'IA', '50312',
          'Gate 2281. Dog — wait for owner.',
          'basement');
  → lastInsertRowid = 1
```

Agent (first metered call this session, rule 11):

> Creating Dana's address on ZenSched costs $0.03 for geocoding. If your account isn't funded yet you'll get a prompt for the $5 activation deposit. Go ahead?

Owner: *"yes"*

```
location_create:
  name: "P-1 - 4412 Maple Street"
  street_address: "4412 Maple Street, Des Moines, IA 50312"
  checkin_radius_m: 75
  idempotency_key: "loc-property-1"
  → location_id: 9201, lat: 41.5868, lng: -93.6250, pin_quality: "street"
    billing: { meter: "geocode", units: 1, price: 0.03 }
```

The gate code is **not** in `notes`. It lives only in `properties.access_notes`. `checkin_radius_m` on the location is informational; the enforced radius is the policy (see later if Kim misses a punch).

```
event_create:
  location_id: 9201
  title: "Radon test - 4412 Maple Street"
  start_date: "2026-09-07"
  end_date:   "2026-11-05"          ← start + 59 days (60-day cap)
  idempotency_key: "event-property-1-20260907"
  → event_id: 7201

form_assign:
  form_id: 501
  event_id: 7201
  idempotency_key: "assign-place-record-7201"
  → status: "assigned", form_id: 501, event_id: 7201, policy_id: 0

form_assign:
  form_id: 502
  event_id: 7201
  idempotency_key: "assign-retrieve-record-7201"
  → status: "assigned", form_id: 502, event_id: 7201, policy_id: 0

sqlite_execute:
  UPDATE properties SET zensched_location_id = 9201, zensched_event_id = 7201, event_valid_until = '2026-11-05'
  WHERE property_id = 1;

sqlite_execute:
  INSERT INTO tests (client_id, property_id, service_id, place_date, retrieve_date,
                     preferred_start, amount, device_type)
  VALUES (1, 1, 1, '2026-09-07', '2026-09-10', '09:00', 175.00, 'charcoal');
  → lastInsertRowid = 1
  -- trigger: test_no → RDN-2026-0001
  -- trigger: protocol → short_term; two visits seeded (place 2026-09-07, retrieve 2026-09-10)
```

> Added Dana Walsh, 4412 Maple Street. Short-term $175, RDN-2026-0001. Place Mon Sep 7 at 9:00, retrieve Thu Sep 10. The ZenSched label is "P-1 - 4412 Maple Street" — her name stays local. The gate code is saved on your computer only; give it to Kim directly. Her ZenSched event runs through Nov 5.

## "Add a listing test for realtor Pat Okonkwo, pat@example.com, 515-555-0190, 890 Walnut Ave, Ames IA 50010, place Tuesday 2026-09-08 at 11, $175. Vacant house, lockbox 4092."

Same pattern. The agent does not re-ask about the $0.03 (owner already approved geocoding this session). Frequency is `on-demand`. Retrieve date is left NULL so the trigger uses soak_days = 3 → Friday Sep 11.

```
sqlite_query:   SELECT service_id, soak_days FROM services WHERE code = 'short_term';
  → 1, 3

sqlite_execute:
  INSERT INTO clients (client_name, client_type, contact_email, contact_phone, service_id, service_rate,
                       service_frequency, preferred_start)
  VALUES ('Pat Okonkwo', 'realtor', 'pat@example.com', '515-555-0190', 1, 175.00,
          'on-demand', '11:00');
  → lastInsertRowid = 2

sqlite_execute:
  INSERT INTO properties (client_id, address, city, state, zip, access_notes, foundation)
  VALUES (2, '890 Walnut Ave', 'Ames', 'IA', '50010',
          'Vacant. Lockbox 4092.',
          'slab');
  → lastInsertRowid = 2

location_create:
  name: "P-2 - 890 Walnut Ave"
  street_address: "890 Walnut Ave, Ames, IA 50010"
  checkin_radius_m: 75
  idempotency_key: "loc-property-2"
  → location_id: 9202

event_create:
  location_id: 9202
  title: "Radon test - 890 Walnut Ave"
  start_date: "2026-09-08"
  end_date:   "2026-11-06"
  idempotency_key: "event-property-2-20260908"
  → event_id: 7202

form_assign: form_id 501, event_id 7202, idempotency_key "assign-place-record-7202"
form_assign: form_id 502, event_id 7202, idempotency_key "assign-retrieve-record-7202"

sqlite_execute:
  UPDATE properties SET zensched_location_id = 9202, zensched_event_id = 7202, event_valid_until = '2026-11-06'
  WHERE property_id = 2;

sqlite_execute:
  INSERT INTO tests (client_id, property_id, service_id, place_date, preferred_start, amount)
  VALUES (2, 2, 1, '2026-09-08', '11:00', 175.00);
  → lastInsertRowid = 2
  -- trigger: test_no → RDN-2026-0002; retrieve_date → 2026-09-11
```

> Added Pat Okonkwo (realtor), 890 Walnut Ave. Short-term $175, RDN-2026-0002. Place Tue Sep 8 at 11:00, retrieve Fri Sep 11. The ZenSched label is "P-2 - 890 Walnut Ave" — no client name. This is not an official MAH-2023 measurement or NRPP device PDF; if the buyer needs the state disclosure, that's still your certifying-body form. Lockbox note is local only.

## "Invite Kim Alvarez, kim@example.com, and make her the default."

> Inviting a tester costs $0.25. OK?

Owner: *"yes"*

```
worker_invite:
  email: "kim@example.com"
  first_name: "Kim"
  last_name: "Alvarez"
  idempotency_key: "worker-kim@example.com"
  → worker_id: 611, status: "invited", invitation_sent: true
    billing: { meter: "worker_invite", units: 1, price: 0.25 }

sqlite_execute:
  INSERT INTO testers (tester_name, email, zensched_worker_id)
  VALUES ('Kim Alvarez', 'kim@example.com', 611);
  → lastInsertRowid = 1

sqlite_execute: UPDATE settings SET value = '611' WHERE key = 'default_worker_id';
```

> Invited Kim. She'll get an email with the app link and an activation code. She's the default tester now. Remember to give her Dana's gate code and the Walnut lockbox; I keep those off ZenSched on purpose.

Optional, if the owner wants a wider circle for large lots:

```
policy_get: policy_id 0
policy_update:
  policy_id: 0
  settings_json: '{"geofence_enabled": true, "require_on_site": true, "checkin_radius_m": 150}'
```

The radius is on the **policy**, not on either location.

## "Schedule this week for Kim."

```
sqlite_query: SELECT * FROM visits_due;
  → 2026-09-07 | place    | Dana Walsh   | RDN-2026-0001 | evt 7201 | event_needs_roll 0 | worker 611 Kim
               | start_iso 2026-09-07T09:00:00-05:00 | end_iso 2026-09-07T09:30:00-05:00
               | shift-test-1-place-20260907
    2026-09-08 | place    | Pat Okonkwo  | RDN-2026-0002 | evt 7202 | event_needs_roll 0 | worker 611 Kim
               | start_iso 2026-09-08T11:00:00-05:00 | end_iso 2026-09-08T11:30:00-05:00
               | shift-test-2-place-20260908
    2026-09-10 | retrieve | Dana Walsh   | RDN-2026-0001 | evt 7201 | event_needs_roll 0 | worker 611 Kim
               | start_iso 2026-09-10T09:00:00-05:00 | end_iso 2026-09-10T09:30:00-05:00
               | shift-test-1-retrieve-20260910
  (3 rows; Okonkwo retrieve Fri 9/11 is also in the +7 window if today is Mon 9/7)

shift_create:
  event_id: 7201
  worker_id: 611
  start: "2026-09-07T09:00:00-05:00"
  end:   "2026-09-07T09:30:00-05:00"
  idempotency_key: "shift-test-1-place-20260907"
  → shift_id: 89011, status: "scheduled", forms_installed: [501, 502]

sqlite_execute: UPDATE visits SET zensched_shift_id = 89011, zensched_event_id = 7201, zensched_worker_id = 611
                WHERE visit_id = 1;

shift_create:
  event_id: 7202
  worker_id: 611
  start: "2026-09-08T11:00:00-05:00"
  end:   "2026-09-08T11:30:00-05:00"
  idempotency_key: "shift-test-2-place-20260908"
  → shift_id: 89012, status: "scheduled"

sqlite_execute: UPDATE visits SET zensched_shift_id = 89012, zensched_event_id = 7202, zensched_worker_id = 611
                WHERE visit_id = 3;

shift_create:
  event_id: 7201
  worker_id: 611
  start: "2026-09-10T09:00:00-05:00"
  end:   "2026-09-10T09:30:00-05:00"
  idempotency_key: "shift-test-1-retrieve-20260910"
  → shift_id: 89013, status: "scheduled"

sqlite_execute: UPDATE visits SET zensched_shift_id = 89013, zensched_event_id = 7201, zensched_worker_id = 611
                WHERE visit_id = 2;
```

> Scheduled 3 stops for Kim this week:
> - Mon 9/7  9:00–9:30   Dana Walsh, 4412 Maple St — **place** (Place Record)
> - Tue 9/8 11:00–11:30  Pat Okonkwo listing, 890 Walnut Ave — **place**
> - Thu 9/10 9:00–9:30   Dana Walsh — **retrieve** (Retrieve Record)
>
> Kim has been notified in the app. Each test is about $0.70 once she punches both visits and you read the photo records ($0.10 + $0.10 + $0.15 per visit). Pass her the gate code and the lockbox yourself.

If the owner asks "schedule this week" again, the identical idempotency keys make ZenSched return the same shifts instead of creating duplicates.

## Kim does the work

Monday 8:55, at 4412 Maple Street, in the ZenSched app: **Check in** (GPS: 14 m from the pin, verified, $0.10). Places the charcoal canister in the basement. Opens **Place Record**: one photo of the device; Closed house = Yes; Notes = "Basement rec room, 20 in off floor, away from sump." Submits (no signature). **Check out** 9:22 ($0.10).

Tuesday 10:52, 890 Walnut Ave: check in via lockbox. Place Record: photo; Closed house = Yes; Notes = "Vacant, HVAC off, first-floor bedroom." Check out 11:18.

Thursday 8:58, back at Maple: check in. Opens **Retrieve Record**: pCi/L = 6.2; one photo of the retrieved canister; Notes = "Seal intact." Check out 9:19.

## "Record this week's visits."

```
shift_list:
  date_from: "2026-09-07"
  date_to:   "2026-09-13"
  status:    "checked_out"
  → shifts: [
      { shift_id: 89011, event_id: 7201, worker_id: 611, date: "2026-09-07", start: "09:00", status: "checked_out" },
      { shift_id: 89012, event_id: 7202, worker_id: 611, date: "2026-09-08", start: "11:00", status: "checked_out" },
      { shift_id: 89013, event_id: 7201, worker_id: 611, date: "2026-09-10", start: "09:00", status: "checked_out" }
    ], count: 3

sqlite_query: SELECT visit_id, test_id, visit_kind, status FROM visits
              WHERE zensched_shift_id IN (89011, 89012, 89013);
  → 1 / test 1 / place    / planned
    3 / test 2 / place    / planned
    2 / test 1 / retrieve / planned
```

Agent (metered read, rule 11):

> There are 2 Place Records and 1 Retrieve Record to pull, all with photos, so about $0.45 ($0.15 each). I'll read them once and keep the summaries locally. OK?

Owner: *"go"*

```
form_export:
  form_id: 501
  since: "2026-09-07"
  until: "2026-09-13"
  format: "json"
  → row_count: 2, rows: [
      { submission_id: 4501, worker_id: 611, event_id: 7201, submitted_at: "2026-09-07 09:18:12",
        data: { closed_house: "yes", notes: "Basement rec room, 20 in off floor, away from sump." },
        media: [ { field_id: 12, cdn_url: "https://cdn.zensched.com/m/.../p1.jpg", thumbnail_url: "https://cdn.zensched.com/m/.../p1-t.jpg", original_filename: "p1.jpg" } ] },
      { submission_id: 4502, worker_id: 611, event_id: 7202, submitted_at: "2026-09-08 11:14:40",
        data: { closed_house: "yes", notes: "Vacant, HVAC off, first-floor bedroom." },
        media: [ { field_id: 12, cdn_url: "https://cdn.zensched.com/m/.../p2.jpg", thumbnail_url: "https://cdn.zensched.com/m/.../p2-t.jpg", original_filename: "p2.jpg" } ] }
    ]
    billing: { meter: "form_media", units: 2, price: 0.30 }

form_export:
  form_id: 502
  since: "2026-09-07"
  until: "2026-09-13"
  format: "json"
  → row_count: 1, rows: [
      { submission_id: 4503, worker_id: 611, event_id: 7201, submitted_at: "2026-09-10 09:16:05",
        data: { pci_l: 6.2, notes: "Seal intact." },
        media: [ { field_id: 22, cdn_url: "https://cdn.zensched.com/m/.../r1.jpg", thumbnail_url: "https://cdn.zensched.com/m/.../r1-t.jpg", original_filename: "r1.jpg" } ] }
    ]
    billing: { meter: "form_media", units: 1, price: 0.15 }

shift_status: shift_id 89011
  → status "checked_out", actual_in "2026-09-07T08:55:10-05:00", actual_out "2026-09-07T09:22:05-05:00",
    punches: [ { type: "in", gps_verified: true, distance_from_site_m: 14 },
               { type: "out", gps_verified: true, distance_from_site_m: 11 } ]
(free)

sqlite_execute:
  UPDATE visits SET status = 'completed',
                    actual_in = '2026-09-07T08:55:10-05:00', actual_out = '2026-09-07T09:22:05-05:00',
                    duration_actual = 27, gps_verified = 1, report_dc_id = 4501, zensched_worker_id = 611
  WHERE visit_id = 1;
  -- trigger: tests.status for RDN-2026-0001 → placed

sqlite_execute:
  UPDATE tests SET closed_house = 'Yes', place_report_dc_id = 4501,
                   place_photo_url = 'https://cdn.zensched.com/m/.../p1.jpg',
                   place_notes = 'Basement rec room, 20 in off floor, away from sump.'
  WHERE test_id = 1;

(same pair of updates for Okonkwo place → test 2 placed, closed_house Yes)

sqlite_execute:
  UPDATE visits SET status = 'completed',
                    actual_in = '2026-09-10T08:58:02-05:00', actual_out = '2026-09-10T09:19:18-05:00',
                    duration_actual = 21, gps_verified = 1, report_dc_id = 4503, zensched_worker_id = 611
  WHERE visit_id = 2;
  -- trigger: tests.status for RDN-2026-0001 → retrieved
  -- trigger: clients.next_test_date for Dana → NULL (on-demand)

sqlite_execute:
  UPDATE tests SET pci_l = 6.2, retrieve_report_dc_id = 4503,
                   retrieve_photo_url = 'https://cdn.zensched.com/m/.../r1.jpg',
                   retrieve_notes = 'Seal intact.'
  WHERE test_id = 1;
```

> Recorded 3 visits, all GPS-verified.
>
> **High reading — Thursday, Walsh retrieve (RDN-2026-0001):** 6.2 pCi/L (field note, not the certified CRM / NRPP PDF), above your 4.0 action level. Closed-house Yes. Seal intact. This is your copy from the phone, not an official MAH-2023 measurement.
>
> Okonkwo listing is still in the house (placed Tue; retrieve Fri). Dana's on-demand date is cleared.

## "Closed-house log for last week."

```
sqlite_query: SELECT * FROM closed_house_log WHERE place_date BETWEEN '2026-09-07' AND '2026-09-13';
  → RDN-2026-0001 | 2026-09-07 / 2026-09-10 | Yes | 6.2 | charcoal | 4412 Maple Street | Dana Walsh
    RDN-2026-0002 | 2026-09-08 / 2026-09-11 | Yes | NULL | 890 Walnut Ave | Pat Okonkwo
```

> Your copy from the phone forms — not an official MAH-2023 measurement, not a certified radon report, and not an NRPP device PDF. The pCi/L is a field note:
>
> | Test | Place | Retrieve | Closed-house | pCi/L | Property |
> |---|---|---|---|---|---|
> | RDN-2026-0001 | Sep 7 | Sep 10 | Yes | 6.2 | 4412 Maple Street |
> | RDN-2026-0002 | Sep 8 | Sep 11 | Yes | — | 890 Walnut Ave (still out) |
>
> Walsh is on `tests_high`. Keep the official MAH-2023 / Iowa DPH / NRPP device PDF on their form separately.

## "Draft invoices for everyone with uninvoiced work."

```
sqlite_query: SELECT * FROM tests_to_invoice;
  → Dana Walsh | 1 test | 175.00 | 2026-09-10 .. 2026-09-10
  (Okonkwo is placed, not retrieved — omitted)

sqlite_execute:
  INSERT INTO invoices (client_id, invoice_date, due_date, total_amount, line_items)
  SELECT t.client_id, date('now'),
         date('now', '+' || (SELECT value FROM settings WHERE key = 'invoice_due_days') || ' days'),
         SUM(t.amount),
         json_group_array(json_object('test_id', t.test_id, 'test_no', t.test_no, 'place_date', t.place_date,
                                      'retrieve_date', t.retrieve_date, 'service', s.service_name,
                                      'amount', t.amount, 'pci_l', t.pci_l, 'closed_house', t.closed_house))
  FROM tests t JOIN services s ON s.service_id = t.service_id
  WHERE t.invoiced = 0 AND t.status = 'retrieved' AND t.client_id = 1 GROUP BY t.client_id;

sqlite_execute: UPDATE tests SET invoiced = 1 WHERE invoiced = 0 AND status = 'retrieved' AND client_id = 1;
sqlite_query:   SELECT invoice_number, invoice_date, due_date, total_amount FROM invoices WHERE invoice_id = last_insert_rowid();
  → INV-2026-0001 | 2026-09-10 | 2026-09-24 | 175.00     (number assigned by trigger)
```

The agent then writes the invoice out as text:

> Here is Dana's invoice. Paste it into an email or text. Okonkwo invoices after Friday's retrieve.
>
> ```
> ClearAir Radon
> Invoice INV-2026-0001
> To: Dana Walsh (dana@example.com)
> Date: Sep 10, 2026    Due: Sep 24, 2026
>
>   RDN-2026-0001    Short-term radon test, 4412 Maple Street
>                    Place Sep 7 / retrieve Sep 10                 $175.00
>
> Total due: $175.00
> Both visits GPS-verified at the property.
> Not an official MAH-2023 measurement, certified radon report, or NRPP device PDF.
> ```
>
> Say "sent" when it's out and I'll note the date.

## "Sent. Dana already paid."

```
sqlite_execute: UPDATE invoices SET sent_date = date('now') WHERE invoice_number = 'INV-2026-0001';
sqlite_execute: UPDATE invoices SET paid = 1, paid_date = date('now') WHERE invoice_number = 'INV-2026-0001';
```

> Marked INV-2026-0001 sent and paid. Okonkwo's $175 will invoice after the Friday retrieve.

## Ninety days later: "Schedule this week" (long-term retrieve)

A long-term test placed Sep 7 has retrieve_date Dec 6 (place + 90 days). The property event ended Nov 5. US Central DST ended the first Sunday of November (2026-11-01). Des Moines is now `-06:00`.

```
sqlite_execute: UPDATE settings SET value = '-06:00' WHERE key = 'timezone_offset';

sqlite_query: SELECT * FROM visits_due;
  → 2026-12-06 | retrieve | … | evt 7201 | event_valid_until 2026-11-05 | event_needs_roll 1
               | event_idempotency_key event-property-1-20261206
               | start_iso 2026-12-06T09:00:00-06:00
  -- retrieve row uses the NEW window key (visit date), not event-property-1-20260907
  -- (reusing the place-window key would replay the expired event)

event_create:
  location_id: 9201
  title: "Radon test - 4412 Maple Street"
  start_date: "2026-12-06"
  end_date:   "2027-02-03"
  idempotency_key: "event-property-1-20261206"
  → event_id: 7301

form_assign: form_id 501, event_id 7301, required True, idempotency_key "assign-place-record-7301"
form_assign: form_id 502, event_id 7301, required True, idempotency_key "assign-retrieve-record-7301"
sqlite_execute: UPDATE properties SET zensched_event_id = 7301, event_valid_until = '2027-02-03' WHERE property_id = 1;

shift_create: event_id 7301, worker_id 611, start "2026-12-06T09:00:00-06:00",
              end "2026-12-06T09:30:00-06:00", idempotency_key "shift-test-3-retrieve-20261206"
```

> Scheduled the long-term retrieve for Sun Dec 6 9:00 (`-06:00` after the clocks changed). The property's ZenSched event had expired (Nov 5), so I renewed it through Feb 3 with a new event key — not the September place-window key. Short-term tests never need this mid-test roll. A 91-day Health Canada test still needs this same two-event roll; one October-to-January event is rejected (60-day cap).

## Summary of who stored what

| Thing | Where | Why |
|---|---|---|
| Dana's contact, $175 on-demand, Pat's listing $175, prices | SQLite | CRM; ZenSched does not model rates or tests |
| Gate code, lockbox, cert number, device serial | SQLite **only** | Privacy; never sent to ZenSched |
| Each property's GPS location | ZenSched (integer ID in `properties`) | Needed for geofenced check-in |
| Each property's current ≤60-day event and its end date | ZenSched (integer ID + `event_valid_until` in `properties`) | Shifts hang off events; renewed by the agent |
| Place Record and Retrieve Record forms | ZenSched (IDs in `settings`) | Installed on the tester's phone per event |
| Kim, her invite, her app | ZenSched (integer ID in `testers`) | Workforce and notifications |
| The week's shifts | ZenSched (`zensched_shift_id` on `visits`) | Live schedule |
| GPS punches, actual times | ZenSched only | Verified record; queried via `shift_status` / `timesheet_export` |
| Place / retrieve records with photos | ZenSched (originals); summary + photo URLs in `tests` | Read once (metered), then closed-house log / invoices from SQLite |
| Two `tests` rows and four `visits` rows | SQLite | Billing + closed-house extract |
| One invoice, paid | SQLite | Billing |
