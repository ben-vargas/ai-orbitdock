CREATE TRIGGER trg_sessions_unique_claude_direct_owner_insert
BEFORE INSERT ON sessions
WHEN COALESCE(NEW.provider, 'claude') = 'claude'
  AND COALESCE(
      NEW.control_mode,
      CASE
          WHEN COALESCE(NEW.claude_integration_mode, 'passive') = 'direct' THEN 'direct'
          ELSE 'passive'
      END
  ) = 'direct'
  AND NEW.claude_sdk_session_id IS NOT NULL
  AND trim(NEW.claude_sdk_session_id) != ''
  AND EXISTS (
      SELECT 1
      FROM sessions direct
      WHERE direct.provider = 'claude'
        AND COALESCE(
            direct.control_mode,
            CASE
                WHEN COALESCE(direct.claude_integration_mode, 'passive') = 'direct' THEN 'direct'
                ELSE 'passive'
            END
        ) = 'direct'
        AND direct.claude_sdk_session_id = NEW.claude_sdk_session_id
        AND direct.id != NEW.id
  )
BEGIN
    SELECT RAISE(ABORT, 'claude direct session owner already exists');
END;

CREATE TRIGGER trg_sessions_unique_claude_direct_owner_update
BEFORE UPDATE ON sessions
WHEN COALESCE(NEW.provider, 'claude') = 'claude'
  AND COALESCE(
      NEW.control_mode,
      CASE
          WHEN COALESCE(NEW.claude_integration_mode, 'passive') = 'direct' THEN 'direct'
          ELSE 'passive'
      END
  ) = 'direct'
  AND NEW.claude_sdk_session_id IS NOT NULL
  AND trim(NEW.claude_sdk_session_id) != ''
  AND EXISTS (
      SELECT 1
      FROM sessions direct
      WHERE direct.provider = 'claude'
        AND COALESCE(
            direct.control_mode,
            CASE
                WHEN COALESCE(direct.claude_integration_mode, 'passive') = 'direct' THEN 'direct'
                ELSE 'passive'
            END
        ) = 'direct'
        AND direct.claude_sdk_session_id = NEW.claude_sdk_session_id
        AND direct.id != NEW.id
  )
BEGIN
    SELECT RAISE(ABORT, 'claude direct session owner already exists');
END;
