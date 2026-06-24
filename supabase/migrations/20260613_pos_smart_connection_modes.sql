-- ============================================================================
-- HOSPIDASH: Smart POS Connection Modes
-- Date: 2026-06-13
-- ============================================================================
-- Makes the POS catalog explicit about capability versus actual backend support.
-- Native provider APIs are represented as candidates only until an adapter exists.
-- ============================================================================

ALTER TABLE public.sales_imports
  ADD COLUMN IF NOT EXISTS provider_key text,
  ADD COLUMN IF NOT EXISTS metadata jsonb NOT NULL DEFAULT '{}'::jsonb;

CREATE INDEX IF NOT EXISTS idx_sales_imports_company_provider
  ON public.sales_imports(company_id, provider_key, created_at DESC)
  WHERE provider_key IS NOT NULL;

ALTER TABLE public.pos_provider_catalog
  ADD COLUMN IF NOT EXISTS country_codes text[],
  ADD COLUMN IF NOT EXISTS connection_mode text,
  ADD COLUMN IF NOT EXISTS connection_status text,
  ADD COLUMN IF NOT EXISTS supports_oauth boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS supports_api_key boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS supports_file_import boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS supports_email_invite boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS has_backend_adapter boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS edge_function_name text,
  ADD COLUMN IF NOT EXISTS documentation_url text,
  ADD COLUMN IF NOT EXISTS notes text;

UPDATE public.pos_provider_catalog
SET
  country_codes = COALESCE(country_codes, countries),
  connection_mode = COALESCE(
    connection_mode,
    CASE
      WHEN status = 'custom' THEN 'custom'
      WHEN connection_type = 'oauth' THEN 'native_oauth'
      WHEN connection_type = 'api_key' THEN 'native_api_key'
      WHEN connection_type = 'file_import' THEN 'import_reports'
      ELSE 'request_only'
    END
  ),
  connection_status = COALESCE(
    connection_status,
    CASE
      WHEN status = 'available' THEN 'live'
      WHEN status = 'custom' THEN 'import_only'
      ELSE 'setup_required'
    END
  ),
  edge_function_name = COALESCE(edge_function_name, 'connect-pos');

ALTER TABLE public.pos_provider_catalog
  ALTER COLUMN country_codes SET NOT NULL,
  ALTER COLUMN connection_mode SET NOT NULL,
  ALTER COLUMN connection_status SET NOT NULL;

DO $$
BEGIN
  ALTER TABLE public.pos_provider_catalog
    ADD CONSTRAINT pos_provider_catalog_connection_mode_check
    CHECK (connection_mode IN (
      'native_oauth',
      'native_api_key',
      'assisted_credentials',
      'import_reports',
      'request_only',
      'custom'
    ));
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  ALTER TABLE public.pos_provider_catalog
    ADD CONSTRAINT pos_provider_catalog_connection_status_check
    CHECK (connection_status IN (
      'live',
      'beta',
      'setup_required',
      'import_only',
      'requested',
      'unavailable'
    ));
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

INSERT INTO public.pos_provider_catalog (
  provider_key,
  display_name,
  countries,
  country_codes,
  connection_type,
  status,
  description,
  connection_mode,
  connection_status,
  supports_oauth,
  supports_api_key,
  supports_file_import,
  supports_email_invite,
  has_backend_adapter,
  edge_function_name,
  documentation_url,
  notes
)
VALUES
  ('custom', 'Custom POS', ARRAY['ES', 'US', 'GB', 'FR', 'IT', 'DE', 'CO', 'MX', 'PT', 'NL', 'OTHER'], ARRAY['ES', 'US', 'GB', 'FR', 'IT', 'DE', 'CO', 'MX', 'PT', 'NL', 'OTHER'], 'file_import', 'custom', 'Use report imports for any POS export, closing report, or sales screenshot.', 'custom', 'import_only', false, false, true, false, false, 'connect-pos', NULL, 'Creates a tenant-scoped import connection with no POS secrets.'),
  ('square', 'Square', ARRAY['ES', 'US', 'GB', 'FR'], ARRAY['ES', 'US', 'GB', 'FR'], 'oauth', 'coming_soon', 'Official OAuth and Orders APIs exist; HospiDash sync is not live yet.', 'native_oauth', 'setup_required', true, false, true, false, false, 'connect-pos', 'https://developer.squareup.com/docs/oauth-api/overview', 'Use report imports until the Square adapter is implemented.'),
  ('lightspeed', 'Lightspeed', ARRAY['ES', 'US', 'GB', 'FR', 'IT', 'DE', 'PT', 'NL'], ARRAY['ES', 'US', 'GB', 'FR', 'IT', 'DE', 'PT', 'NL'], 'oauth', 'coming_soon', 'Restaurant and retail POS used by hospitality operators.', 'native_oauth', 'setup_required', true, false, true, true, false, 'connect-pos', 'https://developers.lightspeedhq.com/retail/authentication/authentication-overview/', 'Retail API is documented; restaurant setup may require assisted provider access.'),
  ('toast', 'Toast', ARRAY['US'], ARRAY['US'], 'oauth', 'coming_soon', 'US-focused restaurant POS platform.', 'assisted_credentials', 'setup_required', true, false, true, true, false, 'connect-pos', 'https://doc.toasttab.com/doc/devguide/apiOverview.html', 'Toast access is partner/integration-type gated. Keep hidden outside the US.'),
  ('clover', 'Clover', ARRAY['US', 'GB'], ARRAY['US', 'GB'], 'oauth', 'coming_soon', 'POS and payment platform for small businesses.', 'native_oauth', 'setup_required', true, false, true, false, false, 'connect-pos', 'https://docs.clover.com/dev/reference/orders', 'Official Orders API exists, but HospiDash does not have a Clover adapter yet.'),
  ('sumup', 'SumUp', ARRAY['GB', 'FR', 'IT', 'DE', 'PT', 'NL'], ARRAY['GB', 'FR', 'IT', 'DE', 'PT', 'NL'], 'api_key', 'coming_soon', 'European payment and POS platform.', 'native_api_key', 'setup_required', false, true, true, false, false, 'connect-pos', 'https://developer.sumup.com/api/transactions', 'API keys must be captured and encrypted server-side before native sync can be offered.'),
  ('zettle', 'Zettle', ARRAY['GB', 'FR', 'IT', 'DE', 'NL'], ARRAY['GB', 'FR', 'IT', 'DE', 'NL'], 'oauth', 'coming_soon', 'PayPal Zettle POS and payments.', 'native_oauth', 'setup_required', true, false, true, false, false, 'connect-pos', 'https://developer.zettle.com/docs/api/purchase/overview', 'Zettle APIs are OAuth based and not supported in every country.'),
  ('glop', 'Glop', ARRAY['ES'], ARRAY['ES'], 'api_key', 'coming_soon', 'Spanish hospitality POS for restaurants and bars.', 'assisted_credentials', 'setup_required', false, true, true, true, false, 'connect-pos', 'https://www.glop.es/api/', 'Developer registration is required before native setup can be verified.'),
  ('agora', 'Agora', ARRAY['ES'], ARRAY['ES'], 'api_key', 'coming_soon', 'Spanish hospitality POS and back-office platform.', 'assisted_credentials', 'setup_required', false, false, true, true, false, 'connect-pos', 'https://www.agorapos.com/integraciones/', 'Official pages point to partner integrations rather than a verified self-serve API.'),
  ('revo', 'Revo', ARRAY['ES'], ARRAY['ES'], 'api_key', 'coming_soon', 'Spanish restaurant POS and management platform.', 'request_only', 'requested', false, false, true, true, false, 'connect-pos', NULL, 'No usable public API documentation was verified in this pass.'),
  ('covermanager', 'CoverManager', ARRAY['ES'], ARRAY['ES'], 'api_key', 'coming_soon', 'Hospitality reservations and restaurant operations platform.', 'assisted_credentials', 'setup_required', false, false, true, true, false, 'connect-pos', 'https://developers.covermanager.com/', 'Developer access appears gated; treat as assisted setup until a sales adapter exists.'),
  ('lastapp', 'Last.app', ARRAY['ES'], ARRAY['ES'], 'api_key', 'coming_soon', 'Spanish restaurant POS and delivery operations platform.', 'assisted_credentials', 'setup_required', false, false, true, true, false, 'connect-pos', 'https://developers.last.app/', 'Developer portal is login-gated; do not claim native availability yet.'),
  ('poster', 'Poster', ARRAY['CO', 'MX', 'PT'], ARRAY['CO', 'MX', 'PT'], 'api_key', 'coming_soon', 'Cloud POS used by restaurants and cafes.', 'native_api_key', 'setup_required', false, true, true, false, false, 'connect-pos', 'https://dev.joinposter.com/en/docs/v3/web/transactions/getTransactions', 'Native sync needs server-side credential encryption and validation first.'),
  ('alegra_pos', 'Alegra POS', ARRAY['CO', 'MX'], ARRAY['CO', 'MX'], 'api_key', 'coming_soon', 'LATAM POS and business management platform.', 'assisted_credentials', 'setup_required', false, true, true, true, false, 'connect-pos', 'https://developer.alegra.com/reference/autenticaci%C3%B3n', 'Requires email/token credentials and accounting setup. Do not capture credentials in Flutter.'),
  ('siigo', 'Siigo', ARRAY['CO'], ARRAY['CO'], 'api_key', 'coming_soon', 'Colombian accounting and POS platform.', 'assisted_credentials', 'setup_required', false, true, true, true, false, 'connect-pos', 'https://siigoapi.docs.apiary.io/', 'Requires username/access_key and Partner-Id. Do not capture credentials in Flutter.')
ON CONFLICT (provider_key) DO UPDATE SET
  display_name = EXCLUDED.display_name,
  countries = EXCLUDED.countries,
  country_codes = EXCLUDED.country_codes,
  connection_type = EXCLUDED.connection_type,
  status = EXCLUDED.status,
  description = EXCLUDED.description,
  connection_mode = EXCLUDED.connection_mode,
  connection_status = EXCLUDED.connection_status,
  supports_oauth = EXCLUDED.supports_oauth,
  supports_api_key = EXCLUDED.supports_api_key,
  supports_file_import = EXCLUDED.supports_file_import,
  supports_email_invite = EXCLUDED.supports_email_invite,
  has_backend_adapter = EXCLUDED.has_backend_adapter,
  edge_function_name = EXCLUDED.edge_function_name,
  documentation_url = EXCLUDED.documentation_url,
  notes = EXCLUDED.notes,
  updated_at = now();

ALTER TABLE public.pos_connections
  ADD COLUMN IF NOT EXISTS connection_mode text,
  ADD COLUMN IF NOT EXISTS deleted_at timestamptz;

UPDATE public.pos_connections
SET connection_mode = COALESCE(
  connection_mode,
  CASE
    WHEN provider_key = 'custom' THEN 'custom'
    WHEN connection_type = 'oauth' THEN 'native_oauth'
    WHEN connection_type = 'api_key' THEN 'native_api_key'
    WHEN connection_type = 'file_import' THEN 'import_reports'
    ELSE 'request_only'
  END
);

ALTER TABLE public.pos_connections
  ALTER COLUMN connection_mode SET NOT NULL;

DO $$
BEGIN
  ALTER TABLE public.pos_connections
    ADD CONSTRAINT pos_connections_connection_mode_check
    CHECK (connection_mode IN (
      'native_oauth',
      'native_api_key',
      'assisted_credentials',
      'import_reports',
      'request_only',
      'custom'
    ));
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

ALTER TABLE public.pos_sync_jobs
  ADD COLUMN IF NOT EXISTS records_processed integer NOT NULL DEFAULT 0;

DROP VIEW IF EXISTS public.pos_connection_status;
CREATE VIEW public.pos_connection_status AS
SELECT
  id,
  company_id,
  provider,
  provider_key,
  provider_name,
  country_code,
  status,
  connection_type,
  connection_mode,
  credentials_status,
  external_account_id,
  last_sync_at,
  sync_status,
  metadata,
  created_at,
  updated_at
FROM public.pos_connections
WHERE deleted_at IS NULL
  AND public.user_belongs_to_company(company_id);

GRANT SELECT ON public.pos_connection_status TO authenticated;

CREATE INDEX IF NOT EXISTS idx_pos_provider_catalog_mode_status
  ON public.pos_provider_catalog(connection_mode, connection_status, provider_key);

CREATE INDEX IF NOT EXISTS idx_pos_connections_company_mode
  ON public.pos_connections(company_id, connection_mode, status)
  WHERE deleted_at IS NULL;
