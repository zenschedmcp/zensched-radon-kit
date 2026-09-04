-- ZenSched Radon-Tester Local Database Schema
-- SQLite database for CRM, properties (places), tests (place visit +
-- retrieve visit), closed-house / pCi/L summaries, and billing.
-- DO NOT duplicate live schedule data from ZenSched (shifts, punches, timesheets).
--
-- HOW TO LOAD THIS FILE
--   Normal path: paste this whole file into your AI chat and say
--   "Create these tables in my radon database. Run each statement one at a time."
--   The AI runs each statement through the SQLite MCP tool (sqlite_execute).
--   Most SQLite MCP tools accept ONE statement per call, so every statement
--   below ends with a semicolon and stands alone.
--
--   Alternative (if you have the sqlite3 command-line tool):
--     sqlite3 radon.db < schema.sql
--
-- Every statement is idempotent (IF NOT EXISTS / INSERT OR IGNORE), so it is
-- safe to run this file again on an existing database.
--
-- NOT A CERTIFIED LAB REPORT. closed_house_log is the owner's local extract
-- from the Place Record and Retrieve Record (date, property, closed-house,
-- pCi/L, tester). It is not an NRPP/NRSB laboratory analysis, not an EPA
-- AARST protocol package, not a state radon disclosure, and not a mitigation
-- design. Licensed testers still issue whatever their state and certifying
-- body require, on their own forms.
--
-- PRIVACY: properties.access_notes (gate codes, lockboxes, dogs, alarm words)
-- testers.cert_no (NRPP / NRSB / state license), and tests.device_serial live
-- ONLY in this file on your computer. They are never sent to ZenSched.
-- SKILL.md forbids the agent from putting them in any ZenSched notes field.

-- Foreign keys are OFF by default in SQLite. This must be run once per
-- connection for ON DELETE CASCADE to work. SKILL.md tells the agent to run it
-- at the start of each session.
PRAGMA foreign_keys = ON;

-- Settings: small key/value store so the agent does not have to be re-told the
-- basics every session (timezone, default tester, business name, form ids).
CREATE TABLE IF NOT EXISTS settings (
  key TEXT PRIMARY KEY,
  value TEXT
);

INSERT OR IGNORE INTO settings (key, value) VALUES ('business_name', 'My Radon Testing Co');
INSERT OR IGNORE INTO settings (key, value) VALUES ('timezone_offset', '-05:00');
INSERT OR IGNORE INTO settings (key, value) VALUES ('default_worker_id', NULL);
INSERT OR IGNORE INTO settings (key, value) VALUES ('default_shift_start', '09:00');
INSERT OR IGNORE INTO settings (key, value) VALUES ('default_place_minutes', '30');
INSERT OR IGNORE INTO settings (key, value) VALUES ('default_retrieve_minutes', '30');
INSERT OR IGNORE INTO settings (key, value) VALUES ('invoice_due_days', '14');
INSERT OR IGNORE INTO settings (key, value) VALUES ('invoice_prefix', 'INV');
INSERT OR IGNORE INTO settings (key, value) VALUES ('test_prefix', 'RDN');
INSERT OR IGNORE INTO settings (key, value) VALUES ('place_record_form_id', NULL);
INSERT OR IGNORE INTO settings (key, value) VALUES ('retrieve_record_form_id', NULL);
INSERT OR IGNORE INTO settings (key, value) VALUES ('event_window_days', '60');
INSERT OR IGNORE INTO settings (key, value) VALUES ('action_level_pci', '4.0');

-- Services: your price list. soak_days is how long the device stays after
-- placement before the default retrieve date (short-term 3, long-term 90).
-- Edit prices freely. tests.service_id is what was actually run.
CREATE TABLE IF NOT EXISTS services (
  service_id INTEGER PRIMARY KEY AUTOINCREMENT,
  code TEXT NOT NULL UNIQUE,
  service_name TEXT NOT NULL,
  default_minutes INTEGER NOT NULL,
  soak_days INTEGER NOT NULL,
  price REAL NOT NULL,
  is_active INTEGER DEFAULT 1,
  notes TEXT
);

INSERT OR IGNORE INTO services (code, service_name, default_minutes, soak_days, price) VALUES ('short_term', 'Short-term radon test', 30, 3, 175.00);
INSERT OR IGNORE INTO services (code, service_name, default_minutes, soak_days, price) VALUES ('long_term', 'Long-term radon test', 30, 90, 225.00);
INSERT OR IGNORE INTO services (code, service_name, default_minutes, soak_days, price) VALUES ('post_mitigation', 'Post-mitigation confirmation', 30, 3, 175.00);
INSERT OR IGNORE INTO services (code, service_name, default_minutes, soak_days, price) VALUES ('commercial', 'Commercial radon test', 45, 3, 250.00);

-- Clients: who hires you (homeowner, realtor, property manager, lab).
-- next_test_date is advanced by trigger when a retrieve visit is completed.
-- Frequency annual / biennial / on-demand only (real-estate work is on-demand).
CREATE TABLE IF NOT EXISTS clients (
  client_id INTEGER PRIMARY KEY AUTOINCREMENT,
  client_name TEXT NOT NULL,
  client_type TEXT NOT NULL DEFAULT 'homeowner'
    CHECK (client_type IN ('homeowner', 'realtor', 'property_manager', 'lab', 'other')),
  contact_email TEXT,
  contact_phone TEXT,
  service_id INTEGER,
  service_rate REAL,
  service_frequency TEXT NOT NULL DEFAULT 'on-demand'
    CHECK (service_frequency IN ('annual', 'biennial', 'on-demand')),
  next_test_date TEXT,
  last_test_date TEXT,
  preferred_start TEXT
    CHECK (preferred_start IS NULL OR preferred_start GLOB '[0-2][0-9]:[0-5][0-9]'),
  zensched_worker_id INTEGER,
  billing_notes TEXT,
  is_active INTEGER DEFAULT 1,
  notes TEXT,
  created_at TEXT DEFAULT (datetime('now')),
  updated_at TEXT DEFAULT (datetime('now')),
  FOREIGN KEY (service_id) REFERENCES services(service_id)
);

-- Properties (places): one service address per row, with ZenSched references.
-- One ZenSched LOCATION per property, created once and kept forever.
-- One ZenSched EVENT per property per rolling window of at most 60 days
-- (ZenSched caps event length). zensched_event_id is the CURRENT event and
-- event_valid_until is its last valid date. When a visit date is later than
-- event_valid_until, the agent creates a new event and updates both columns.
-- A short-term test (place + retrieve in 2–7 days) fits in one event. A
-- long-term test (retrieve at +90 days) rolls the event between the two visits.
CREATE TABLE IF NOT EXISTS properties (
  property_id INTEGER PRIMARY KEY AUTOINCREMENT,
  client_id INTEGER NOT NULL,
  address TEXT NOT NULL,
  address_line2 TEXT,
  city TEXT,
  state TEXT,
  zip TEXT,
  access_notes TEXT,
  foundation TEXT
    CHECK (foundation IS NULL OR foundation IN ('basement', 'crawl', 'slab', 'mixed')),
  zensched_location_id INTEGER,
  zensched_event_id INTEGER,
  event_valid_until TEXT,
  is_active INTEGER DEFAULT 1,
  created_at TEXT DEFAULT (datetime('now')),
  updated_at TEXT DEFAULT (datetime('now')),
  FOREIGN KEY (client_id) REFERENCES clients(client_id) ON DELETE CASCADE
);

-- Testers: your roster. zensched_worker_id comes from worker_invite.
-- cert_no is LOCAL ONLY (NRPP / NRSB / state license) and never sent to ZenSched.
CREATE TABLE IF NOT EXISTS testers (
  tester_id INTEGER PRIMARY KEY AUTOINCREMENT,
  tester_name TEXT NOT NULL,
  email TEXT,
  phone TEXT,
  zensched_worker_id INTEGER UNIQUE,
  cert_no TEXT,
  is_active INTEGER DEFAULT 1,
  notes TEXT,
  created_at TEXT DEFAULT (datetime('now')),
  updated_at TEXT DEFAULT (datetime('now'))
);

-- Tests: one engagement at a property. Each test owns exactly two visits
-- (place + retrieve), seeded by trigger. closed_house and pci_l are filled
-- from the Place Record / Retrieve Record when those visits are recorded.
-- test_no is auto-assigned as RDN-YYYY-0001 when left NULL.
CREATE TABLE IF NOT EXISTS tests (
  test_id INTEGER PRIMARY KEY AUTOINCREMENT,
  test_no TEXT UNIQUE,
  client_id INTEGER NOT NULL,
  property_id INTEGER NOT NULL,
  service_id INTEGER NOT NULL,
  tester_id INTEGER,
  device_type TEXT
    CHECK (device_type IS NULL OR device_type IN ('charcoal', 'electret', 'crm', 'alpha_track', 'other')),
  device_serial TEXT,
  protocol TEXT
    CHECK (protocol IS NULL OR protocol IN ('short_term', 'long_term', 'post_mitigation')),
  place_date TEXT NOT NULL,
  retrieve_date TEXT,
  preferred_start TEXT
    CHECK (preferred_start IS NULL OR preferred_start GLOB '[0-2][0-9]:[0-5][0-9]'),
  amount REAL,
  status TEXT NOT NULL DEFAULT 'scheduled'
    CHECK (status IN ('scheduled', 'placed', 'retrieved', 'cancelled')),
  closed_house TEXT
    CHECK (closed_house IS NULL OR closed_house IN ('Yes', 'No')),
  pci_l REAL
    CHECK (pci_l IS NULL OR pci_l >= 0),
  place_report_dc_id INTEGER,
  retrieve_report_dc_id INTEGER,
  place_photo_url TEXT,
  retrieve_photo_url TEXT,
  place_notes TEXT,
  retrieve_notes TEXT,
  invoiced INTEGER DEFAULT 0,
  notes TEXT,
  created_at TEXT DEFAULT (datetime('now')),
  updated_at TEXT DEFAULT (datetime('now')),
  FOREIGN KEY (client_id) REFERENCES clients(client_id) ON DELETE CASCADE,
  FOREIGN KEY (property_id) REFERENCES properties(property_id) ON DELETE CASCADE,
  FOREIGN KEY (service_id) REFERENCES services(service_id),
  FOREIGN KEY (tester_id) REFERENCES testers(tester_id) ON DELETE SET NULL
);

-- Visits: one row per place or retrieve stop. Each maps to one ZenSched shift
-- on the property's current (<=60-day) event. UNIQUE(test_id, visit_kind)
-- enforces the two-visit shape. zensched_shift_id is UNIQUE so a shift cannot
-- be recorded twice.
CREATE TABLE IF NOT EXISTS visits (
  visit_id INTEGER PRIMARY KEY AUTOINCREMENT,
  test_id INTEGER NOT NULL,
  visit_kind TEXT NOT NULL
    CHECK (visit_kind IN ('place', 'retrieve')),
  scheduled_date TEXT NOT NULL,
  scheduled_start TEXT
    CHECK (scheduled_start IS NULL OR scheduled_start GLOB '[0-2][0-9]:[0-5][0-9]'),
  duration_minutes INTEGER
    CHECK (duration_minutes IS NULL OR duration_minutes BETWEEN 15 AND 480),
  tester_id INTEGER,
  status TEXT NOT NULL DEFAULT 'planned'
    CHECK (status IN ('planned', 'completed', 'missed', 'cancelled')),
  zensched_shift_id INTEGER UNIQUE,
  zensched_event_id INTEGER,
  zensched_worker_id INTEGER,
  actual_in TEXT,
  actual_out TEXT,
  duration_actual INTEGER,
  gps_verified INTEGER,
  report_dc_id INTEGER,
  created_at TEXT DEFAULT (datetime('now')),
  UNIQUE (test_id, visit_kind),
  FOREIGN KEY (test_id) REFERENCES tests(test_id) ON DELETE CASCADE,
  FOREIGN KEY (tester_id) REFERENCES testers(tester_id) ON DELETE SET NULL
);

-- Invoices: billing records.
-- invoice_number is filled in automatically by a trigger if left NULL.
CREATE TABLE IF NOT EXISTS invoices (
  invoice_id INTEGER PRIMARY KEY AUTOINCREMENT,
  client_id INTEGER NOT NULL,
  invoice_number TEXT UNIQUE,
  invoice_date TEXT NOT NULL,
  due_date TEXT,
  total_amount REAL NOT NULL,
  paid INTEGER DEFAULT 0,
  paid_date TEXT,
  sent_date TEXT,
  line_items TEXT,
  notes TEXT,
  created_at TEXT DEFAULT (datetime('now')),
  FOREIGN KEY (client_id) REFERENCES clients(client_id) ON DELETE CASCADE
);

-- Indexes for common queries
CREATE INDEX IF NOT EXISTS idx_clients_next_test ON clients(next_test_date, is_active);
CREATE INDEX IF NOT EXISTS idx_clients_service ON clients(service_id);
CREATE INDEX IF NOT EXISTS idx_properties_client ON properties(client_id);
CREATE INDEX IF NOT EXISTS idx_properties_zensched_location ON properties(zensched_location_id);
CREATE INDEX IF NOT EXISTS idx_properties_zensched_event ON properties(zensched_event_id);
CREATE INDEX IF NOT EXISTS idx_testers_worker ON testers(zensched_worker_id);
CREATE INDEX IF NOT EXISTS idx_tests_client ON tests(client_id, place_date);
CREATE INDEX IF NOT EXISTS idx_tests_property ON tests(property_id);
CREATE INDEX IF NOT EXISTS idx_tests_status ON tests(status);
CREATE INDEX IF NOT EXISTS idx_tests_invoiced ON tests(invoiced);
CREATE INDEX IF NOT EXISTS idx_visits_test ON visits(test_id, visit_kind);
CREATE INDEX IF NOT EXISTS idx_visits_scheduled ON visits(scheduled_date, status);
CREATE INDEX IF NOT EXISTS idx_invoices_client ON invoices(client_id);
CREATE INDEX IF NOT EXISTS idx_invoices_paid ON invoices(paid);

-- Keep updated_at current
CREATE TRIGGER IF NOT EXISTS update_client_timestamp
AFTER UPDATE ON clients
BEGIN
  UPDATE clients SET updated_at = datetime('now') WHERE client_id = NEW.client_id;
END;

CREATE TRIGGER IF NOT EXISTS update_property_timestamp
AFTER UPDATE ON properties
BEGIN
  UPDATE properties SET updated_at = datetime('now') WHERE property_id = NEW.property_id;
END;

CREATE TRIGGER IF NOT EXISTS update_tester_timestamp
AFTER UPDATE ON testers
BEGIN
  UPDATE testers SET updated_at = datetime('now') WHERE tester_id = NEW.tester_id;
END;

CREATE TRIGGER IF NOT EXISTS update_test_timestamp
AFTER UPDATE ON tests
BEGIN
  UPDATE tests SET updated_at = datetime('now') WHERE test_id = NEW.test_id;
END;

-- Auto-number tests: RDN-2026-0001, RDN-2026-0002, ...
CREATE TRIGGER IF NOT EXISTS number_test
AFTER INSERT ON tests
WHEN NEW.test_no IS NULL
BEGIN
  UPDATE tests
  SET test_no = (SELECT COALESCE(value, 'RDN') FROM settings WHERE key = 'test_prefix')
                || '-' || strftime('%Y', NEW.place_date)
                || '-' || printf('%04d', NEW.test_id)
  WHERE test_id = NEW.test_id;
END;

-- Fill amount, retrieve_date, protocol; seed the place + retrieve visit rows.
-- retrieve_date defaults to place_date + services.soak_days (3 or 90).
-- Visits are INSERT OR IGNORE so a retry of this trigger body cannot duplicate.
CREATE TRIGGER IF NOT EXISTS fill_test_defaults
AFTER INSERT ON tests
BEGIN
  UPDATE tests
  SET retrieve_date = COALESCE(
        NEW.retrieve_date,
        date(NEW.place_date, '+' || COALESCE((SELECT soak_days FROM services WHERE service_id = NEW.service_id), 3) || ' days')
      ),
      amount = COALESCE(
        NEW.amount,
        CASE WHEN (SELECT c.service_id FROM clients c WHERE c.client_id = NEW.client_id) = NEW.service_id
             THEN (SELECT c.service_rate FROM clients c WHERE c.client_id = NEW.client_id)
             END,
        (SELECT s.price FROM services s WHERE s.service_id = NEW.service_id)
      ),
      protocol = COALESCE(
        NEW.protocol,
        CASE (SELECT s.code FROM services s WHERE s.service_id = NEW.service_id)
          WHEN 'long_term' THEN 'long_term'
          WHEN 'post_mitigation' THEN 'post_mitigation'
          ELSE 'short_term'
        END
      ),
      tester_id = COALESCE(
        NEW.tester_id,
        (SELECT t.tester_id FROM testers t
          WHERE t.zensched_worker_id = COALESCE(
            (SELECT c.zensched_worker_id FROM clients c WHERE c.client_id = NEW.client_id),
            (SELECT CAST(value AS INTEGER) FROM settings WHERE key = 'default_worker_id')
          ))
      )
  WHERE test_id = NEW.test_id;
  INSERT OR IGNORE INTO visits (test_id, visit_kind, scheduled_date)
  VALUES (NEW.test_id, 'place', NEW.place_date);
  INSERT OR IGNORE INTO visits (test_id, visit_kind, scheduled_date)
  VALUES (
    NEW.test_id,
    'retrieve',
    COALESCE(
      NEW.retrieve_date,
      date(NEW.place_date, '+' || COALESCE((SELECT soak_days FROM services WHERE service_id = NEW.service_id), 3) || ' days')
    )
  );
END;

-- Fill visit start time and duration from the test / settings when left NULL.
CREATE TRIGGER IF NOT EXISTS fill_visit_defaults
AFTER INSERT ON visits
BEGIN
  UPDATE visits
  SET scheduled_start = COALESCE(
        NEW.scheduled_start,
        (SELECT t.preferred_start FROM tests t WHERE t.test_id = NEW.test_id),
        (SELECT c.preferred_start FROM tests t JOIN clients c ON c.client_id = t.client_id WHERE t.test_id = NEW.test_id),
        (SELECT value FROM settings WHERE key = 'default_shift_start')
      ),
      duration_minutes = COALESCE(
        NEW.duration_minutes,
        CASE NEW.visit_kind
          WHEN 'place' THEN CAST((SELECT value FROM settings WHERE key = 'default_place_minutes') AS INTEGER)
          ELSE CAST((SELECT value FROM settings WHERE key = 'default_retrieve_minutes') AS INTEGER)
        END
      ),
      tester_id = COALESCE(
        NEW.tester_id,
        (SELECT t.tester_id FROM tests t WHERE t.test_id = NEW.test_id)
      )
  WHERE visit_id = NEW.visit_id;
END;

-- Fill tester_id from the roster when the agent only has the ZenSched worker id.
CREATE TRIGGER IF NOT EXISTS fill_visit_tester
AFTER UPDATE OF zensched_worker_id ON visits
WHEN NEW.tester_id IS NULL AND NEW.zensched_worker_id IS NOT NULL
BEGIN
  UPDATE visits
  SET tester_id = (SELECT tester_id FROM testers WHERE zensched_worker_id = NEW.zensched_worker_id)
  WHERE visit_id = NEW.visit_id;
END;

-- Keep planned visit dates in sync when the owner reschedules the test window.
CREATE TRIGGER IF NOT EXISTS sync_place_visit_date
AFTER UPDATE OF place_date ON tests
WHEN NEW.place_date IS NOT NULL
BEGIN
  UPDATE visits
  SET scheduled_date = NEW.place_date
  WHERE test_id = NEW.test_id
    AND visit_kind = 'place'
    AND status = 'planned'
    AND zensched_shift_id IS NULL;
END;

CREATE TRIGGER IF NOT EXISTS sync_retrieve_visit_date
AFTER UPDATE OF retrieve_date ON tests
WHEN NEW.retrieve_date IS NOT NULL
BEGIN
  UPDATE visits
  SET scheduled_date = NEW.retrieve_date
  WHERE test_id = NEW.test_id
    AND visit_kind = 'retrieve'
    AND status = 'planned'
    AND zensched_shift_id IS NULL;
END;

-- Completing a visit advances the test: place → placed, retrieve → retrieved.
CREATE TRIGGER IF NOT EXISTS mark_test_from_visit
AFTER UPDATE OF status ON visits
WHEN NEW.status = 'completed'
BEGIN
  UPDATE tests
  SET status = CASE NEW.visit_kind
        WHEN 'retrieve' THEN 'retrieved'
        ELSE CASE WHEN tests.status = 'retrieved' THEN 'retrieved' ELSE 'placed' END
      END
  WHERE test_id = NEW.test_id
    AND status <> 'cancelled';
END;

-- Recording a completed retrieve advances the client's cadence.
-- annual +1 year, biennial +2 years, on-demand → NULL.
CREATE TRIGGER IF NOT EXISTS advance_next_test_on_retrieve
AFTER UPDATE OF status ON tests
WHEN NEW.status = 'retrieved' AND OLD.status <> 'retrieved'
BEGIN
  UPDATE clients
  SET last_test_date = COALESCE(NEW.retrieve_date, date('now')),
      next_test_date = CASE service_frequency
        WHEN 'annual'   THEN date(COALESCE(NEW.retrieve_date, date('now')), '+1 year')
        WHEN 'biennial' THEN date(COALESCE(NEW.retrieve_date, date('now')), '+2 years')
        ELSE NULL
      END
  WHERE client_id = NEW.client_id;
END;

-- Auto-number invoices: INV-2026-0001, INV-2026-0002, ...
CREATE TRIGGER IF NOT EXISTS number_invoice
AFTER INSERT ON invoices
WHEN NEW.invoice_number IS NULL
BEGIN
  UPDATE invoices
  SET invoice_number = (SELECT COALESCE(value, 'INV') FROM settings WHERE key = 'invoice_prefix')
                       || '-' || strftime('%Y', NEW.invoice_date)
                       || '-' || printf('%04d', NEW.invoice_id)
  WHERE invoice_id = NEW.invoice_id;
END;

-- Who is due in the next 7 days (today + 6). The agent's weekly scheduling
-- query. One row = one shift_create call (a place visit or a retrieve visit).
-- event_needs_roll = 1 means create a new ZenSched event first (see SKILL.md).
-- access_notes is included so the agent can tell the owner to pass it to the
-- tester; it must never go into a ZenSched field.
CREATE VIEW IF NOT EXISTS visits_due AS
SELECT
  v.visit_id,
  v.visit_kind,
  v.scheduled_date,
  v.status AS visit_status,
  COALESCE(v.scheduled_start, (SELECT value FROM settings WHERE key = 'default_shift_start')) AS start_time,
  COALESCE(v.duration_minutes, CASE v.visit_kind
      WHEN 'place' THEN CAST((SELECT value FROM settings WHERE key = 'default_place_minutes') AS INTEGER)
      ELSE CAST((SELECT value FROM settings WHERE key = 'default_retrieve_minutes') AS INTEGER)
    END) AS duration_minutes,
  t.test_id,
  t.test_no,
  t.amount,
  t.status AS test_status,
  t.device_type,
  t.protocol,
  sv.service_id,
  sv.code AS service_code,
  sv.service_name,
  c.client_id,
  c.client_name,
  c.client_type,
  c.contact_email,
  c.contact_phone,
  p.property_id,
  p.address,
  p.city,
  p.state,
  p.zip,
  p.foundation,
  p.access_notes,
  p.zensched_location_id,
  p.zensched_event_id,
  p.event_valid_until,
  CASE WHEN p.event_valid_until IS NULL OR p.event_valid_until < v.scheduled_date THEN 1 ELSE 0 END AS event_needs_roll,
  COALESCE(
    v.zensched_worker_id,
    t2.zensched_worker_id,
    c.zensched_worker_id,
    (SELECT CAST(value AS INTEGER) FROM settings WHERE key = 'default_worker_id')
  ) AS worker_id,
  (SELECT te.tester_name FROM testers te
    WHERE te.zensched_worker_id = COALESCE(
      v.zensched_worker_id,
      t2.zensched_worker_id,
      c.zensched_worker_id,
      (SELECT CAST(value AS INTEGER) FROM settings WHERE key = 'default_worker_id')
    )) AS tester_name,
  v.scheduled_date || 'T'
    || COALESCE(v.scheduled_start, (SELECT value FROM settings WHERE key = 'default_shift_start'))
    || ':00' || (SELECT value FROM settings WHERE key = 'timezone_offset') AS start_iso,
  strftime('%Y-%m-%dT%H:%M:%S', datetime(
      v.scheduled_date || ' '
      || COALESCE(v.scheduled_start, (SELECT value FROM settings WHERE key = 'default_shift_start'))
      || ':00',
      '+' || COALESCE(v.duration_minutes, CASE v.visit_kind
          WHEN 'place' THEN CAST((SELECT value FROM settings WHERE key = 'default_place_minutes') AS INTEGER)
          ELSE CAST((SELECT value FROM settings WHERE key = 'default_retrieve_minutes') AS INTEGER)
        END) || ' minutes'))
    || (SELECT value FROM settings WHERE key = 'timezone_offset') AS end_iso,
  'shift-test-' || t.test_id || '-' || v.visit_kind || '-' || strftime('%Y%m%d', v.scheduled_date) AS idempotency_key,
  'loc-property-' || p.property_id AS loc_idempotency_key,
  'event-property-' || p.property_id || '-' || strftime('%Y%m%d', v.scheduled_date) AS event_idempotency_key
FROM visits v
JOIN tests t ON t.test_id = v.test_id
JOIN properties p ON p.property_id = t.property_id AND p.is_active = 1
JOIN clients c ON c.client_id = t.client_id AND c.is_active = 1
LEFT JOIN testers t2 ON t2.tester_id = COALESCE(v.tester_id, t.tester_id)
LEFT JOIN services sv ON sv.service_id = t.service_id
WHERE v.status = 'planned'
  AND t.status <> 'cancelled'
  AND v.zensched_shift_id IS NULL
  AND v.scheduled_date IS NOT NULL
  AND v.scheduled_date <= date('now', '+7 days')
ORDER BY v.scheduled_date,
  COALESCE(v.scheduled_start, (SELECT value FROM settings WHERE key = 'default_shift_start')),
  c.client_name,
  v.visit_kind;

-- Properties whose current ZenSched event expires within 14 days (or has none)
-- and that belong to an active client with an open test. Roll these proactively.
CREATE VIEW IF NOT EXISTS events_expiring AS
SELECT
  p.property_id,
  c.client_name,
  p.address,
  p.zensched_location_id,
  p.zensched_event_id,
  p.event_valid_until
FROM properties p
JOIN clients c ON c.client_id = p.client_id AND c.is_active = 1
WHERE p.is_active = 1
  AND (p.event_valid_until IS NULL OR p.event_valid_until <= date('now', '+14 days'))
  AND EXISTS (
    SELECT 1 FROM tests t
    WHERE t.property_id = p.property_id
      AND t.status IN ('scheduled', 'placed')
  )
ORDER BY p.event_valid_until;

-- Open tests that have not been retrieved (or cancelled).
CREATE VIEW IF NOT EXISTS tests_open AS
SELECT
  t.test_id,
  t.test_no,
  t.status,
  t.place_date,
  t.retrieve_date,
  t.closed_house,
  t.pci_l,
  t.amount,
  t.protocol,
  c.client_name,
  p.address,
  p.city,
  p.state,
  (SELECT v.scheduled_date FROM visits v WHERE v.test_id = t.test_id AND v.visit_kind = 'place') AS place_visit_date,
  (SELECT v.status FROM visits v WHERE v.test_id = t.test_id AND v.visit_kind = 'place') AS place_visit_status,
  (SELECT v.scheduled_date FROM visits v WHERE v.test_id = t.test_id AND v.visit_kind = 'retrieve') AS retrieve_visit_date,
  (SELECT v.status FROM visits v WHERE v.test_id = t.test_id AND v.visit_kind = 'retrieve') AS retrieve_visit_status
FROM tests t
JOIN clients c ON c.client_id = t.client_id
JOIN properties p ON p.property_id = t.property_id
WHERE t.status IN ('scheduled', 'placed')
ORDER BY t.place_date, t.test_no;

-- Devices in the house: placed, retrieve not yet completed.
CREATE VIEW IF NOT EXISTS tests_awaiting_retrieve AS
SELECT
  t.test_id,
  t.test_no,
  t.place_date,
  t.retrieve_date,
  t.closed_house,
  t.device_type,
  t.device_serial,
  c.client_name,
  p.address,
  p.city,
  p.state,
  p.access_notes,
  CAST(julianday(t.retrieve_date) - julianday('now') AS INTEGER) AS days_until_retrieve
FROM tests t
JOIN clients c ON c.client_id = t.client_id
JOIN properties p ON p.property_id = t.property_id
WHERE t.status = 'placed'
ORDER BY t.retrieve_date, t.test_no;

-- Retrieved tests at or above the shop action level (default EPA 4.0 pCi/L).
CREATE VIEW IF NOT EXISTS tests_high AS
SELECT
  t.test_id,
  t.test_no,
  t.retrieve_date,
  t.pci_l,
  t.closed_house,
  t.protocol,
  c.client_name,
  c.contact_email,
  p.address,
  p.city,
  p.state,
  CAST((SELECT value FROM settings WHERE key = 'action_level_pci') AS REAL) AS action_level_pci
FROM tests t
JOIN clients c ON c.client_id = t.client_id
JOIN properties p ON p.property_id = t.property_id
WHERE t.status = 'retrieved'
  AND t.pci_l IS NOT NULL
  AND t.pci_l >= CAST((SELECT value FROM settings WHERE key = 'action_level_pci') AS REAL)
ORDER BY t.pci_l DESC, t.retrieve_date;

-- Owner's local closed-house + reading extract. This is the product: GPS-
-- backed place/retrieve plus what the tester typed. Not a lab report.
CREATE VIEW IF NOT EXISTS closed_house_log AS
SELECT
  t.test_id,
  t.test_no,
  t.place_date,
  t.retrieve_date,
  t.closed_house,
  t.pci_l,
  t.device_type,
  t.protocol,
  p.address AS property,
  p.city,
  p.state,
  c.client_name,
  COALESCE(te.tester_name, 'tester') AS tester,
  t.place_photo_url,
  t.retrieve_photo_url,
  t.place_notes,
  t.retrieve_notes,
  t.place_report_dc_id,
  t.retrieve_report_dc_id
FROM tests t
JOIN properties p ON p.property_id = t.property_id
JOIN clients c ON c.client_id = t.client_id
LEFT JOIN testers te ON te.tester_id = t.tester_id
WHERE t.status IN ('placed', 'retrieved')
ORDER BY COALESCE(t.retrieve_date, t.place_date) DESC, t.test_no;

-- Retrieved tests that have not been invoiced yet, grouped by client.
CREATE VIEW IF NOT EXISTS tests_to_invoice AS
SELECT
  c.client_id,
  c.client_name,
  c.contact_email,
  c.billing_notes,
  COUNT(t.test_id)      AS test_count,
  SUM(t.amount)         AS total_amount,
  MIN(t.retrieve_date)  AS first_test_date,
  MAX(t.retrieve_date)  AS last_test_date
FROM tests t
JOIN clients c ON c.client_id = t.client_id
WHERE t.invoiced = 0
  AND t.status = 'retrieved'
GROUP BY c.client_id
ORDER BY c.client_name;

-- Unpaid invoices, oldest first.
CREATE VIEW IF NOT EXISTS invoices_outstanding AS
SELECT
  i.invoice_id,
  i.invoice_number,
  c.client_name,
  c.contact_email,
  i.invoice_date,
  i.due_date,
  i.total_amount,
  i.sent_date,
  CASE WHEN i.due_date < date('now') THEN 1 ELSE 0 END AS overdue
FROM invoices i
JOIN clients c ON c.client_id = i.client_id
WHERE i.paid = 0
ORDER BY i.due_date;
