ALTER TABLE sessions ADD COLUMN lifecycle_state TEXT NOT NULL DEFAULT 'open';

UPDATE sessions
SET lifecycle_state = CASE
    WHEN status = 'ended' OR work_status = 'ended' THEN 'ended'
    ELSE 'open'
END
WHERE lifecycle_state IS NULL OR lifecycle_state = '';
