-- Render this template to .deployment before running it; see README.
-- IF NOT EXISTS preserves the existing password on a setup retry.
CREATE USER IF NOT EXISTS link_shortener_app
IDENTIFIED WITH sha256_hash BY 'REPLACE_WITH_SHA256_HASH';
