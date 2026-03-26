CREATE TRIGGER trg_sessions_block_claude_shadow_insert
BEFORE INSERT ON sessions
WHEN EXISTS (
    SELECT 1 FROM sessions direct
    WHERE direct.provider = 'claude'
      AND direct.claude_integration_mode = 'direct'
      AND direct.claude_sdk_session_id = NEW.id
) AND COALESCE(NEW.provider, 'claude') = 'claude'
  AND COALESCE(
      NEW.control_mode,
      CASE
          WHEN COALESCE(NEW.claude_integration_mode, 'passive') = 'direct' THEN 'direct'
          ELSE 'passive'
      END
  ) != 'direct'
BEGIN
    SELECT RAISE(IGNORE);
END;

CREATE TRIGGER trg_sessions_block_claude_shadow_update
BEFORE UPDATE ON sessions
WHEN EXISTS (
    SELECT 1 FROM sessions direct
    WHERE direct.provider = 'claude'
      AND direct.claude_integration_mode = 'direct'
      AND direct.claude_sdk_session_id = NEW.id
) AND COALESCE(NEW.provider, 'claude') = 'claude'
  AND COALESCE(
      NEW.control_mode,
      CASE
          WHEN COALESCE(NEW.claude_integration_mode, 'passive') = 'direct' THEN 'direct'
          ELSE 'passive'
      END
  ) != 'direct'
BEGIN
    SELECT RAISE(IGNORE);
END;
