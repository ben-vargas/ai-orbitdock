ALTER TABLE sessions ADD COLUMN last_progress_at TEXT;

UPDATE sessions
SET last_progress_at = last_activity_at
WHERE last_progress_at IS NULL
  AND last_activity_at IS NOT NULL;
