-- +goose Up
UPDATE applications
SET config_json=JSON_MERGE_PATCH(config_json, JSON_OBJECT(
  'auth', JSON_OBJECT(
    'registration_enabled', TRUE,
    'username_password_enabled', TRUE,
    'phone_enabled', FALSE,
    'email_enabled', FALSE,
    'login_captcha_required', FALSE,
    'register_captcha_required', FALSE,
    'login_code_required', FALSE,
    'register_code_required', FALSE
  ),
  'history_sync_enabled', TRUE,
  'read_receipts_enabled', TRUE,
  'service_accounts_enabled', TRUE,
  'moments_enabled', TRUE,
  'livekit_enabled', TRUE
)), updated_at=NOW(6)
WHERE id=1;

-- +goose Down
UPDATE applications
SET config_json=JSON_REMOVE(config_json,
  '$.auth', '$.history_sync_enabled', '$.read_receipts_enabled',
  '$.service_accounts_enabled', '$.moments_enabled', '$.livekit_enabled'),
  updated_at=NOW(6)
WHERE id=1;
