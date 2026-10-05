-- One row per counted request. No IP addresses, no cookies: `visitor` is a hash keyed by a random
-- value that exists for one day only (see `salts`), so it can't be reversed or linked across days.
CREATE TABLE IF NOT EXISTS hits (
  ts INTEGER NOT NULL,        -- unix seconds
  day TEXT NOT NULL,          -- YYYY-MM-DD, UTC
  kind TEXT NOT NULL,         -- 'view' | 'download' | 'agent'
  path TEXT NOT NULL,
  visitor TEXT NOT NULL,
  referrer TEXT,              -- the linking site's domain only, or NULL
  country TEXT                -- as Cloudflare reports it
);
CREATE INDEX IF NOT EXISTS hits_day_kind ON hits (day, kind);

-- Today's random salt. Yesterday's is deleted by the daily cleanup, which is what makes old visitor
-- codes impossible to work back from — for anyone, including whoever runs this site.
CREATE TABLE IF NOT EXISTS salts (
  day TEXT PRIMARY KEY,
  salt TEXT NOT NULL
);
