-- Migration 0001 — interests table
--
-- V1 of the Parachute interest list (issue #25). Captures email signups
-- from the homepage form via the standalone subscribe Worker.
--
-- Schema mirrors LVB's interests table after #44, minus the JSON tags
-- column (Parachute V1 doesn't segment). Two reserved columns kept:
--   user_id           — NULL for V1; reserved for future identity linking
--                       once Parachute has user accounts.
--   resend_contact_id — NULL for V1; reserved for V2 Resend audience sync.
--
-- No UNIQUE constraint on email — duplicate signups are tolerated and
-- preserve signal (when someone came back, from where).

CREATE TABLE interests (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  email TEXT NOT NULL,
  name TEXT,            -- reserved; the V1 form collects email only (NULL for now)
  source_path TEXT,     -- pathname from Referer; often NULL on cross-origin POST
                        -- (default Referrer-Policy sends origin only, no path)
  user_id INTEGER,
  resend_contact_id TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX idx_interests_email ON interests(email);
