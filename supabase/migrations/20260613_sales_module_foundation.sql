-- ============================================================================
-- HOSPIDASH: Sales Module Foundation
-- Date: 2026-06-13
-- ============================================================================
-- Adds the real Sales module data model while preserving compatibility with the
-- existing dashboard code that reads public.sales.total_amount.
-- ============================================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ---------------------------------------------------------------------------
-- sales_imports: batch/import status for manual, POS, VLM, and CSV sales data
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.sales_imports (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  source_type text NOT NULL CHECK (source_type IN ('manual', 'pos', 'vlm_import', 'csv_import')),
  source_name text,
  file_path text,
  status text NOT NULL DEFAULT 'processing' CHECK (status IN ('processing', 'completed', 'flagged', 'failed')),
  imported_at timestamptz,
  period_start date,
  period_end date,
  total_gross numeric(14,2),
  total_net numeric(14,2),
  total_tax numeric(14,2),
  currency text NOT NULL DEFAULT 'EUR',
  notes text,
  extraction_raw jsonb,
  extraction_clean jsonb,
  created_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------------
-- sales: upgrade old daily aggregate table to support transaction/import rows
-- ---------------------------------------------------------------------------

ALTER TABLE public.sales DROP CONSTRAINT IF EXISTS sales_company_id_sale_date_key;

ALTER TABLE public.sales
  ALTER COLUMN id SET DEFAULT gen_random_uuid();

ALTER TABLE public.sales
  ADD COLUMN IF NOT EXISTS sales_import_id uuid REFERENCES public.sales_imports(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS sale_datetime timestamptz,
  ADD COLUMN IF NOT EXISTS gross_amount numeric(14,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS net_amount numeric(14,2),
  ADD COLUMN IF NOT EXISTS tax_amount numeric(14,2),
  ADD COLUMN IF NOT EXISTS discount_amount numeric(14,2),
  ADD COLUMN IF NOT EXISTS tip_amount numeric(14,2),
  ADD COLUMN IF NOT EXISTS currency text NOT NULL DEFAULT 'EUR',
  ADD COLUMN IF NOT EXISTS payment_method text,
  ADD COLUMN IF NOT EXISTS channel text,
  ADD COLUMN IF NOT EXISTS pos_transaction_id text,
  ADD COLUMN IF NOT EXISTS source_type text NOT NULL DEFAULT 'manual',
  ADD COLUMN IF NOT EXISTS metadata jsonb NOT NULL DEFAULT '{}'::jsonb;

UPDATE public.sales
SET
  gross_amount = COALESCE(
    NULLIF(gross_amount, 0),
    total_amount,
    COALESCE(cash_amount, 0) + COALESCE(card_amount, 0) + COALESCE(other_amount, 0),
    0
  ),
  net_amount = COALESCE(net_amount, total_amount - COALESCE(tax_collected, 0)),
  tax_amount = COALESCE(tax_amount, tax_collected),
  discount_amount = COALESCE(discount_amount, discounts_amount),
  tip_amount = COALESCE(tip_amount, tips_amount),
  source_type = CASE
    WHEN source = 'pos_import' THEN 'pos'
    WHEN source = 'api' THEN 'pos'
    ELSE COALESCE(source_type, 'manual')
  END,
  total_amount = COALESCE(
    total_amount,
    gross_amount,
    COALESCE(cash_amount, 0) + COALESCE(card_amount, 0) + COALESCE(other_amount, 0),
    0
  )
WHERE gross_amount = 0
   OR net_amount IS NULL
   OR tax_amount IS NULL
   OR discount_amount IS NULL
   OR tip_amount IS NULL
   OR total_amount IS NULL;

DO $$
BEGIN
  ALTER TABLE public.sales
    ADD CONSTRAINT sales_source_type_check
    CHECK (source_type IN ('manual', 'pos', 'vlm_import', 'csv_import'));
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  ALTER TABLE public.sales
    ADD CONSTRAINT sales_channel_check
    CHECK (channel IS NULL OR channel IN ('dine_in', 'takeaway', 'delivery', 'unknown'));
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

CREATE OR REPLACE FUNCTION public.sync_sales_amount_compatibility()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF (NEW.gross_amount IS NULL OR NEW.gross_amount = 0)
     AND NEW.total_amount IS NOT NULL THEN
    NEW.gross_amount := NEW.total_amount;
  END IF;

  IF NEW.total_amount IS NULL THEN
    NEW.total_amount := COALESCE(NEW.gross_amount, 0);
  END IF;

  IF NEW.sale_datetime IS NULL AND NEW.sale_date IS NOT NULL THEN
    NEW.sale_datetime := NEW.sale_date::timestamptz;
  END IF;

  IF NEW.source_type IS NULL THEN
    NEW.source_type := CASE
      WHEN NEW.source = 'pos_import' THEN 'pos'
      WHEN NEW.source = 'api' THEN 'pos'
      ELSE 'manual'
    END;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_sync_sales_amount_compatibility ON public.sales;
CREATE TRIGGER trg_sync_sales_amount_compatibility
  BEFORE INSERT OR UPDATE ON public.sales
  FOR EACH ROW
  EXECUTE FUNCTION public.sync_sales_amount_compatibility();

-- ---------------------------------------------------------------------------
-- sales_items: item-level rows from POS/VLM/CSV sales reports
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.sales_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  sale_id uuid REFERENCES public.sales(id) ON DELETE SET NULL,
  sales_import_id uuid REFERENCES public.sales_imports(id) ON DELETE SET NULL,
  product_name text NOT NULL,
  normalized_product_name text,
  quantity numeric(14,3),
  unit_price numeric(14,2),
  total_amount numeric(14,2),
  category text,
  pos_product_id text,
  product_id uuid REFERENCES public.products(id) ON DELETE SET NULL,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------------
-- POS tables. Tokens are stored only in pos_connections and are not exposed to
-- Flutter; clients should read public.pos_connection_status instead.
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.pos_provider_catalog (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  provider_key text UNIQUE NOT NULL,
  display_name text NOT NULL,
  countries text[] NOT NULL,
  connection_type text NOT NULL CHECK (connection_type IN ('oauth', 'api_key', 'file_import', 'manual', 'coming_soon')),
  status text NOT NULL CHECK (status IN ('available', 'coming_soon', 'custom')),
  description text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

INSERT INTO public.pos_provider_catalog (
  provider_key,
  display_name,
  countries,
  connection_type,
  status,
  description
)
VALUES
  ('custom', 'Custom POS', ARRAY['ES', 'US', 'GB', 'FR', 'IT', 'DE', 'CO', 'MX', 'PT', 'NL', 'OTHER'], 'manual', 'custom', 'Manual/API configuration for any POS provider.'),
  ('square', 'Square', ARRAY['ES', 'US', 'GB', 'FR'], 'oauth', 'coming_soon', 'Common card and POS platform in several markets.'),
  ('lightspeed', 'Lightspeed', ARRAY['ES', 'US', 'GB', 'FR', 'IT', 'DE', 'PT', 'NL'], 'oauth', 'coming_soon', 'Restaurant and retail POS used by hospitality operators.'),
  ('toast', 'Toast', ARRAY['US'], 'oauth', 'coming_soon', 'US-focused restaurant POS.'),
  ('clover', 'Clover', ARRAY['US', 'GB'], 'oauth', 'coming_soon', 'POS and payment platform for small businesses.'),
  ('sumup', 'SumUp', ARRAY['GB', 'FR', 'IT', 'DE', 'PT', 'NL'], 'api_key', 'coming_soon', 'European payment and POS platform.'),
  ('zettle', 'Zettle', ARRAY['GB', 'FR', 'IT', 'DE', 'NL'], 'api_key', 'coming_soon', 'PayPal Zettle POS and payments.'),
  ('glop', 'Glop', ARRAY['ES'], 'api_key', 'coming_soon', 'Spanish hospitality POS for restaurants and bars.'),
  ('agora', 'Agora', ARRAY['ES'], 'api_key', 'coming_soon', 'Spanish hospitality POS and back-office platform.'),
  ('revo', 'Revo', ARRAY['ES'], 'api_key', 'coming_soon', 'Spanish restaurant POS and management platform.'),
  ('covermanager', 'CoverManager', ARRAY['ES'], 'api_key', 'coming_soon', 'Hospitality reservations and restaurant operations platform.'),
  ('lastapp', 'Last.app', ARRAY['ES'], 'api_key', 'coming_soon', 'Spanish restaurant POS and delivery operations platform.'),
  ('poster', 'Poster', ARRAY['CO', 'MX', 'PT'], 'api_key', 'coming_soon', 'Cloud POS used by restaurants and cafes.'),
  ('alegra_pos', 'Alegra POS', ARRAY['CO', 'MX'], 'api_key', 'coming_soon', 'LATAM POS and business management platform.'),
  ('siigo', 'Siigo', ARRAY['CO'], 'api_key', 'coming_soon', 'Colombian accounting and POS platform.')
ON CONFLICT (provider_key) DO UPDATE SET
  display_name = EXCLUDED.display_name,
  countries = EXCLUDED.countries,
  connection_type = EXCLUDED.connection_type,
  status = EXCLUDED.status,
  description = EXCLUDED.description,
  updated_at = now();

CREATE TABLE IF NOT EXISTS public.pos_connections (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  provider text NOT NULL CHECK (provider IN ('square', 'lightspeed', 'poster', 'toast', 'sumup', 'custom')),
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('connected', 'disconnected', 'error', 'pending')),
  access_token_encrypted text,
  refresh_token_encrypted text,
  external_account_id text,
  last_sync_at timestamptz,
  sync_status text,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.pos_connections DROP CONSTRAINT IF EXISTS pos_connections_provider_check;
ALTER TABLE public.pos_connections DROP CONSTRAINT IF EXISTS pos_connections_status_check;

ALTER TABLE public.pos_connections
  ADD COLUMN IF NOT EXISTS provider_key text,
  ADD COLUMN IF NOT EXISTS provider_name text,
  ADD COLUMN IF NOT EXISTS country_code text,
  ADD COLUMN IF NOT EXISTS connection_type text,
  ADD COLUMN IF NOT EXISTS credentials_status text NOT NULL DEFAULT 'none',
  ADD COLUMN IF NOT EXISTS created_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL;

UPDATE public.pos_connections
SET
  provider_key = COALESCE(provider_key, provider),
  provider_name = COALESCE(provider_name, initcap(replace(provider, '_', ' '))),
  country_code = COALESCE(country_code, 'OTHER'),
  connection_type = COALESCE(connection_type, 'manual'),
  credentials_status = COALESCE(credentials_status, 'none');

ALTER TABLE public.pos_connections
  ALTER COLUMN provider_key SET NOT NULL,
  ALTER COLUMN provider_name SET NOT NULL,
  ALTER COLUMN country_code SET NOT NULL,
  ALTER COLUMN connection_type SET NOT NULL;

ALTER TABLE public.pos_connections
  ADD CONSTRAINT pos_connections_status_check
  CHECK (status IN ('pending', 'connected', 'error', 'disconnected', 'coming_soon'));

DO $$
BEGIN
  ALTER TABLE public.pos_connections
    ADD CONSTRAINT pos_connections_connection_type_check
    CHECK (connection_type IN ('oauth', 'api_key', 'file_import', 'manual', 'coming_soon'));
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  ALTER TABLE public.pos_connections
    ADD CONSTRAINT pos_connections_credentials_status_check
    CHECK (credentials_status IN ('none', 'pending', 'configured', 'expired'));
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

CREATE TABLE IF NOT EXISTS public.pos_sync_jobs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  pos_connection_id uuid NOT NULL REFERENCES public.pos_connections(id) ON DELETE CASCADE,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'processing', 'completed', 'failed')),
  period_start date,
  period_end date,
  error_message text,
  created_at timestamptz NOT NULL DEFAULT now(),
  completed_at timestamptz
);

CREATE TABLE IF NOT EXISTS public.pos_connection_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  provider_key text NOT NULL,
  provider_name text NOT NULL,
  country_code text NOT NULL,
  status text NOT NULL DEFAULT 'requested' CHECK (status IN ('requested', 'notified', 'closed')),
  requested_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

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
  credentials_status,
  external_account_id,
  last_sync_at,
  sync_status,
  metadata,
  created_at,
  updated_at
FROM public.pos_connections
WHERE public.user_belongs_to_company(company_id);

-- ---------------------------------------------------------------------------
-- Storage bucket for sales report imports
-- ---------------------------------------------------------------------------

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'sales-imports',
  'sales-imports',
  FALSE,
  10485760,
  ARRAY['image/jpeg', 'image/png', 'image/webp', 'application/pdf', 'text/csv']
)
ON CONFLICT (id) DO UPDATE SET
  public = EXCLUDED.public,
  file_size_limit = EXCLUDED.file_size_limit,
  allowed_mime_types = EXCLUDED.allowed_mime_types;

DROP POLICY IF EXISTS "Company members can view sales imports storage" ON storage.objects;
CREATE POLICY "Company members can view sales imports storage"
ON storage.objects FOR SELECT
TO authenticated
USING (
  bucket_id = 'sales-imports'
  AND public.get_company_id_from_path(name) = (SELECT public.get_current_company_id())
);

DROP POLICY IF EXISTS "Company members can upload sales imports storage" ON storage.objects;
CREATE POLICY "Company members can upload sales imports storage"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id = 'sales-imports'
  AND public.get_company_id_from_path(name) = (SELECT public.get_current_company_id())
  AND (SELECT public.user_has_role_in_company(
    (SELECT public.get_current_company_id()),
    ARRAY['owner', 'admin', 'manager', 'member']
  ))
);

DROP POLICY IF EXISTS "Company members can update sales imports storage" ON storage.objects;
CREATE POLICY "Company members can update sales imports storage"
ON storage.objects FOR UPDATE
TO authenticated
USING (
  bucket_id = 'sales-imports'
  AND public.get_company_id_from_path(name) = (SELECT public.get_current_company_id())
)
WITH CHECK (
  bucket_id = 'sales-imports'
  AND public.get_company_id_from_path(name) = (SELECT public.get_current_company_id())
);

DROP POLICY IF EXISTS "Admins can delete sales imports storage" ON storage.objects;
CREATE POLICY "Admins can delete sales imports storage"
ON storage.objects FOR DELETE
TO authenticated
USING (
  bucket_id = 'sales-imports'
  AND public.get_company_id_from_path(name) = (SELECT public.get_current_company_id())
  AND (SELECT public.user_is_company_admin((SELECT public.get_current_company_id())))
);

-- ---------------------------------------------------------------------------
-- Indexes
-- ---------------------------------------------------------------------------

CREATE INDEX IF NOT EXISTS idx_sales_imports_company_status_created
  ON public.sales_imports(company_id, status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_sales_imports_company_period
  ON public.sales_imports(company_id, period_start, period_end);

CREATE INDEX IF NOT EXISTS idx_sales_company_sale_date
  ON public.sales(company_id, sale_date DESC);
CREATE INDEX IF NOT EXISTS idx_sales_company_import
  ON public.sales(company_id, sales_import_id);
CREATE INDEX IF NOT EXISTS idx_sales_company_source
  ON public.sales(company_id, source_type, sale_date DESC);
CREATE UNIQUE INDEX IF NOT EXISTS idx_sales_company_pos_transaction
  ON public.sales(company_id, pos_transaction_id)
  WHERE pos_transaction_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_sales_items_company_import
  ON public.sales_items(company_id, sales_import_id);
CREATE INDEX IF NOT EXISTS idx_sales_items_company_sale
  ON public.sales_items(company_id, sale_id);
CREATE INDEX IF NOT EXISTS idx_sales_items_company_product_name
  ON public.sales_items(company_id, normalized_product_name);

CREATE INDEX IF NOT EXISTS idx_pos_connections_company_provider
  ON public.pos_connections(company_id, provider);
CREATE INDEX IF NOT EXISTS idx_pos_connections_company_provider_key
  ON public.pos_connections(company_id, provider_key);
CREATE INDEX IF NOT EXISTS idx_pos_connections_company_country
  ON public.pos_connections(company_id, country_code);
CREATE INDEX IF NOT EXISTS idx_pos_sync_jobs_company_status
  ON public.pos_sync_jobs(company_id, status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_pos_provider_catalog_status
  ON public.pos_provider_catalog(status, provider_key);
CREATE INDEX IF NOT EXISTS idx_pos_connection_requests_company_status
  ON public.pos_connection_requests(company_id, status, created_at DESC);

-- ---------------------------------------------------------------------------
-- Updated-at triggers
-- ---------------------------------------------------------------------------

DROP TRIGGER IF EXISTS update_sales_imports_updated_at ON public.sales_imports;
CREATE TRIGGER update_sales_imports_updated_at
  BEFORE UPDATE ON public.sales_imports
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at_column();

DROP TRIGGER IF EXISTS update_pos_connections_updated_at ON public.pos_connections;
CREATE TRIGGER update_pos_connections_updated_at
  BEFORE UPDATE ON public.pos_connections
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at_column();

DROP TRIGGER IF EXISTS update_pos_provider_catalog_updated_at ON public.pos_provider_catalog;
CREATE TRIGGER update_pos_provider_catalog_updated_at
  BEFORE UPDATE ON public.pos_provider_catalog
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at_column();

DROP TRIGGER IF EXISTS update_pos_connection_requests_updated_at ON public.pos_connection_requests;
CREATE TRIGGER update_pos_connection_requests_updated_at
  BEFORE UPDATE ON public.pos_connection_requests
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at_column();

-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------

ALTER TABLE public.sales_imports ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sales_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pos_provider_catalog ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pos_connections ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pos_sync_jobs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pos_connection_requests ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.sales_imports FORCE ROW LEVEL SECURITY;
ALTER TABLE public.sales_items FORCE ROW LEVEL SECURITY;
ALTER TABLE public.pos_provider_catalog FORCE ROW LEVEL SECURITY;
ALTER TABLE public.pos_connections FORCE ROW LEVEL SECURITY;
ALTER TABLE public.pos_sync_jobs FORCE ROW LEVEL SECURITY;
ALTER TABLE public.pos_connection_requests FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Company members can view sales imports" ON public.sales_imports;
CREATE POLICY "Company members can view sales imports"
  ON public.sales_imports FOR SELECT
  TO authenticated
  USING (public.user_belongs_to_company(company_id));

DROP POLICY IF EXISTS "Company members can create sales imports" ON public.sales_imports;
CREATE POLICY "Company members can create sales imports"
  ON public.sales_imports FOR INSERT
  TO authenticated
  WITH CHECK (
    public.user_belongs_to_company(company_id)
    AND public.user_has_role_in_company(company_id, ARRAY['owner', 'admin', 'manager', 'member'])
  );

DROP POLICY IF EXISTS "Company members can update sales imports" ON public.sales_imports;
CREATE POLICY "Company members can update sales imports"
  ON public.sales_imports FOR UPDATE
  TO authenticated
  USING (public.user_belongs_to_company(company_id))
  WITH CHECK (public.user_belongs_to_company(company_id));

DROP POLICY IF EXISTS "Admins can delete sales imports" ON public.sales_imports;
CREATE POLICY "Admins can delete sales imports"
  ON public.sales_imports FOR DELETE
  TO authenticated
  USING (public.user_is_company_admin(company_id));

DROP POLICY IF EXISTS "Company members can view sales items" ON public.sales_items;
CREATE POLICY "Company members can view sales items"
  ON public.sales_items FOR SELECT
  TO authenticated
  USING (public.user_belongs_to_company(company_id));

DROP POLICY IF EXISTS "Company members can create sales items" ON public.sales_items;
CREATE POLICY "Company members can create sales items"
  ON public.sales_items FOR INSERT
  TO authenticated
  WITH CHECK (
    public.user_belongs_to_company(company_id)
    AND public.user_has_role_in_company(company_id, ARRAY['owner', 'admin', 'manager', 'member'])
  );

DROP POLICY IF EXISTS "Company members can update sales items" ON public.sales_items;
CREATE POLICY "Company members can update sales items"
  ON public.sales_items FOR UPDATE
  TO authenticated
  USING (public.user_belongs_to_company(company_id))
  WITH CHECK (public.user_belongs_to_company(company_id));

DROP POLICY IF EXISTS "Admins can delete sales items" ON public.sales_items;
CREATE POLICY "Admins can delete sales items"
  ON public.sales_items FOR DELETE
  TO authenticated
  USING (public.user_is_company_admin(company_id));

DROP POLICY IF EXISTS "Authenticated users can view POS provider catalog" ON public.pos_provider_catalog;
CREATE POLICY "Authenticated users can view POS provider catalog"
  ON public.pos_provider_catalog FOR SELECT
  TO authenticated
  USING (true);

-- No direct SELECT policy on pos_connections: token columns must not be exposed.
-- Flutter reads public.pos_connection_status instead.
DROP POLICY IF EXISTS "Company members can create POS connections" ON public.pos_connections;
CREATE POLICY "Company members can create POS connections"
  ON public.pos_connections FOR INSERT
  TO authenticated
  WITH CHECK (
    public.user_belongs_to_company(company_id)
    AND public.user_has_role_in_company(company_id, ARRAY['owner', 'admin'])
  );

DROP POLICY IF EXISTS "Admins can update POS connections" ON public.pos_connections;
CREATE POLICY "Admins can update POS connections"
  ON public.pos_connections FOR UPDATE
  TO authenticated
  USING (public.user_is_company_admin(company_id))
  WITH CHECK (public.user_is_company_admin(company_id));

DROP POLICY IF EXISTS "Admins can delete POS connections" ON public.pos_connections;
CREATE POLICY "Admins can delete POS connections"
  ON public.pos_connections FOR DELETE
  TO authenticated
  USING (public.user_is_company_admin(company_id));

DROP POLICY IF EXISTS "Company members can view POS sync jobs" ON public.pos_sync_jobs;
CREATE POLICY "Company members can view POS sync jobs"
  ON public.pos_sync_jobs FOR SELECT
  TO authenticated
  USING (public.user_belongs_to_company(company_id));

DROP POLICY IF EXISTS "Admins can create POS sync jobs" ON public.pos_sync_jobs;
CREATE POLICY "Admins can create POS sync jobs"
  ON public.pos_sync_jobs FOR INSERT
  TO authenticated
  WITH CHECK (public.user_is_company_admin(company_id));

DROP POLICY IF EXISTS "Admins can update POS sync jobs" ON public.pos_sync_jobs;
CREATE POLICY "Admins can update POS sync jobs"
  ON public.pos_sync_jobs FOR UPDATE
  TO authenticated
  USING (public.user_is_company_admin(company_id))
  WITH CHECK (public.user_is_company_admin(company_id));

DROP POLICY IF EXISTS "Admins can delete POS sync jobs" ON public.pos_sync_jobs;
CREATE POLICY "Admins can delete POS sync jobs"
  ON public.pos_sync_jobs FOR DELETE
  TO authenticated
  USING (public.user_is_company_admin(company_id));

DROP POLICY IF EXISTS "Company members can view POS connection requests" ON public.pos_connection_requests;
CREATE POLICY "Company members can view POS connection requests"
  ON public.pos_connection_requests FOR SELECT
  TO authenticated
  USING (public.user_belongs_to_company(company_id));

DROP POLICY IF EXISTS "Company members can create POS connection requests" ON public.pos_connection_requests;
CREATE POLICY "Company members can create POS connection requests"
  ON public.pos_connection_requests FOR INSERT
  TO authenticated
  WITH CHECK (public.user_belongs_to_company(company_id));

DROP POLICY IF EXISTS "Admins can update POS connection requests" ON public.pos_connection_requests;
CREATE POLICY "Admins can update POS connection requests"
  ON public.pos_connection_requests FOR UPDATE
  TO authenticated
  USING (public.user_is_company_admin(company_id))
  WITH CHECK (public.user_is_company_admin(company_id));

DROP POLICY IF EXISTS "Admins can delete POS connection requests" ON public.pos_connection_requests;
CREATE POLICY "Admins can delete POS connection requests"
  ON public.pos_connection_requests FOR DELETE
  TO authenticated
  USING (public.user_is_company_admin(company_id));

GRANT SELECT ON public.pos_connection_status TO authenticated;
GRANT SELECT ON public.pos_provider_catalog TO authenticated;

-- ---------------------------------------------------------------------------
-- Tenant-checked summary RPC. Flutter uses this instead of fetching all sales
-- rows and aggregating client-side.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.get_sales_summary(
  p_company_id uuid,
  p_period_start date,
  p_period_end date
)
RETURNS TABLE (
  gross_revenue numeric,
  net_revenue numeric,
  tax_amount numeric,
  transaction_count bigint,
  average_ticket numeric
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.user_belongs_to_company(p_company_id) THEN
    RAISE EXCEPTION 'Access denied for company %', p_company_id USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT
    COALESCE(SUM(s.gross_amount), 0)::numeric AS gross_revenue,
    COALESCE(SUM(COALESCE(s.net_amount, s.gross_amount - COALESCE(s.tax_amount, 0))), 0)::numeric AS net_revenue,
    COALESCE(SUM(COALESCE(s.tax_amount, 0)), 0)::numeric AS tax_amount,
    COUNT(s.id)::bigint AS transaction_count,
    COALESCE(AVG(s.gross_amount), 0)::numeric AS average_ticket
  FROM public.sales s
  WHERE s.company_id = p_company_id
    AND s.sale_date >= p_period_start
    AND s.sale_date <= p_period_end;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_sales_summary(uuid, date, date) TO authenticated;

-- ---------------------------------------------------------------------------
-- Realtime
-- ---------------------------------------------------------------------------

DO $$
BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.sales_imports;
EXCEPTION
  WHEN duplicate_object THEN NULL;
  WHEN undefined_object THEN NULL;
END $$;

DO $$
BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.sales_items;
EXCEPTION
  WHEN duplicate_object THEN NULL;
  WHEN undefined_object THEN NULL;
END $$;

DO $$
BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.pos_connections;
EXCEPTION
  WHEN duplicate_object THEN NULL;
  WHEN undefined_object THEN NULL;
END $$;

DO $$
BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.pos_sync_jobs;
EXCEPTION
  WHEN duplicate_object THEN NULL;
  WHEN undefined_object THEN NULL;
END $$;

ALTER TABLE public.sales_imports REPLICA IDENTITY FULL;
ALTER TABLE public.sales_items REPLICA IDENTITY FULL;
ALTER TABLE public.pos_connections REPLICA IDENTITY FULL;
ALTER TABLE public.pos_sync_jobs REPLICA IDENTITY FULL;