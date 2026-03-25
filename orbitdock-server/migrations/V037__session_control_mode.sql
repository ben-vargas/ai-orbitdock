ALTER TABLE sessions ADD COLUMN control_mode TEXT;

UPDATE sessions
SET control_mode = CASE
    WHEN provider = 'codex' AND codex_integration_mode = 'direct' THEN 'direct'
    WHEN provider = 'claude' AND claude_integration_mode = 'direct' THEN 'direct'
    ELSE 'passive'
END
WHERE control_mode IS NULL OR control_mode = '';
