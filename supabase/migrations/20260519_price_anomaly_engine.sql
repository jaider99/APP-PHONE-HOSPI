-- ============================================================================
-- Migration 20260519: Price anomaly detection engine
--
-- Adds tenant-scoped financial intelligence over product price history:
--   1) price_anomalies: deterministic anomaly events + AI explanation metadata
--   2) product_price_stats: cached per-product statistics for fast UI/querying
--   3) product_purchase_fingerprints: document-level product fingerprint matching
--   4) RPCs for stats refresh and anomaly resolution
--   5) Realtime publication for in-app alerts
--
-- Existing product_prices contract is preserved:
--   product_prices.price       = unit price
--   product_prices.date        = purchase date
--   product_prices.observed_at = observation timestamp
--   product_prices.supplier_id references providers(id)
-- ============================================================================

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ---------------------------------------------------------------------------
-- 0) Ensure product_prices has the local intelligence columns used by the app.
-- ---------------------------------------------------------------------------

ALTER TABLE product_prices
  ADD COLUMN IF NOT EXISTS supplier_id uuid REFERENCES providers(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS date date;

UPDATE product_prices
   SET date = COALESCE(date, observed_at::date)
 WHERE date IS NULL;

CREATE INDEX IF NOT EXISTS idx_product_prices_company_product_date_desc
  ON product_prices (company_id, product_id, date DESC NULLS LAST, observed_at DESC);

CREATE INDEX IF NOT EXISTS idx_product_prices_company_supplier_product_date
  ON product_prices (company_id, supplier_id, product_id, date DESC NULLS LAST)
  WHERE supplier_id IS NOT NULL;

-- ---------------------------------------------------------------------------
-- 1) Cached product statistics.
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS product_price_stats (
  company_id uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  product_id uuid NOT NULL REFERENCES products(id) ON DELETE CASCADE,

  sample_count integer NOT NULL DEFAULT 0,
  supplier_count integer NOT NULL DEFAULT 0,

  avg_price numeric(12,4),
  median_price numeric(12,4),
  stddev_price numeric(12,4),
  min_price numeric(12,4),
  max_price numeric(12,4),

  last_price numeric(12,4),
  last_supplier_id uuid REFERENCES providers(id) ON DELETE SET NULL,
  last_purchase_date date,

  avg_quantity numeric(12,4),
  stddev_quantity numeric(12,4),

  thirty_day_avg numeric(12,4),
  prior_thirty_day_avg numeric(12,4),
  trend_percent numeric(12,4),

  baseline_price numeric(12,4),
  baseline_approved_at timestamptz,

  updated_at timestamptz NOT NULL DEFAULT now(),

  PRIMARY KEY (company_id, product_id)
);

ALTER TABLE product_price_stats ENABLE ROW LEVEL SECURITY;
ALTER TABLE product_price_stats FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS product_price_stats_isolation ON product_price_stats;
CREATE POLICY product_price_stats_isolation ON product_price_stats
  FOR ALL
  TO authenticated
  USING (company_id = ANY(public.user_company_ids()))
  WITH CHECK (company_id = ANY(public.user_company_ids()));

CREATE INDEX IF NOT EXISTS idx_product_price_stats_company_updated
  ON product_price_stats (company_id, updated_at DESC);

-- ---------------------------------------------------------------------------
-- 2) Anomaly events.
-- ---------------------------------------------------------------------------

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'price_anomaly_severity') THEN
    CREATE TYPE price_anomaly_severity AS ENUM ('low', 'medium', 'high', 'critical');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'price_anomaly_resolution_status') THEN
    CREATE TYPE price_anomaly_resolution_status AS ENUM ('open', 'resolved', 'ignored', 'baseline_approved');
  END IF;
END;
$$;

CREATE TABLE IF NOT EXISTS price_anomalies (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  company_id uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  product_id uuid NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  supplier_id uuid REFERENCES providers(id) ON DELETE SET NULL,
  document_id uuid REFERENCES documents(id) ON DELETE SET NULL,
  document_item_id uuid REFERENCES document_items(id) ON DELETE SET NULL,
  product_price_id uuid REFERENCES product_prices(id) ON DELETE SET NULL,

  anomaly_type text NOT NULL,

  current_price numeric(12,4),
  expected_price numeric(12,4),
  deviation_percent numeric(12,4),

  severity price_anomaly_severity NOT NULL DEFAULT 'low',
  confidence_score numeric(5,4) NOT NULL DEFAULT 0 CHECK (confidence_score >= 0 AND confidence_score <= 1),

  explanation text,
  heuristic_details jsonb NOT NULL DEFAULT '{}'::jsonb,
  ai_confidence numeric(5,4) CHECK (ai_confidence IS NULL OR (ai_confidence >= 0 AND ai_confidence <= 1)),
  ai_explanation text,

  resolved boolean NOT NULL DEFAULT false,
  resolution_status price_anomaly_resolution_status NOT NULL DEFAULT 'open',
  resolution_note text,
  resolved_at timestamptz,
  resolved_by uuid,

  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE price_anomalies ENABLE ROW LEVEL SECURITY;
ALTER TABLE price_anomalies FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS price_anomalies_isolation ON price_anomalies;
CREATE POLICY price_anomalies_isolation ON price_anomalies
  FOR ALL
  TO authenticated
  USING (company_id = ANY(public.user_company_ids()))
  WITH CHECK (company_id = ANY(public.user_company_ids()));

CREATE INDEX IF NOT EXISTS idx_price_anomalies_company_created
  ON price_anomalies (company_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_price_anomalies_company_product_open
  ON price_anomalies (company_id, product_id, created_at DESC)
  WHERE resolved = false;

CREATE INDEX IF NOT EXISTS idx_price_anomalies_company_document
  ON price_anomalies (company_id, document_id)
  WHERE document_id IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS idx_price_anomalies_unique_price_type
  ON price_anomalies (company_id, product_price_id, anomaly_type);

-- ---------------------------------------------------------------------------
-- 3) Product-level document fingerprints for duplicate price pattern checks.
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS product_purchase_fingerprints (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  document_id uuid NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
  supplier_id uuid REFERENCES providers(id) ON DELETE SET NULL,
  fingerprint_hash text NOT NULL,
  line_count integer NOT NULL DEFAULT 0,
  total_price numeric(14,4),
  product_ids text[] NOT NULL DEFAULT ARRAY[]::text[],
  created_at timestamptz NOT NULL DEFAULT now(),

  UNIQUE (company_id, document_id)
);

ALTER TABLE product_purchase_fingerprints ENABLE ROW LEVEL SECURITY;
ALTER TABLE product_purchase_fingerprints FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS product_purchase_fingerprints_isolation ON product_purchase_fingerprints;
CREATE POLICY product_purchase_fingerprints_isolation ON product_purchase_fingerprints
  FOR ALL
  TO authenticated
  USING (company_id = ANY(public.user_company_ids()))
  WITH CHECK (company_id = ANY(public.user_company_ids()));

CREATE INDEX IF NOT EXISTS idx_product_purchase_fingerprints_company_hash
  ON product_purchase_fingerprints (company_id, fingerprint_hash, created_at DESC);

-- ---------------------------------------------------------------------------
-- 4) Stats refresh and resolution RPCs.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.refresh_product_price_stats(
  p_company_id uuid,
  p_product_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_sample_count integer;
  v_supplier_count integer;
  v_avg_price numeric(12,4);
  v_median_price numeric(12,4);
  v_stddev_price numeric(12,4);
  v_min_price numeric(12,4);
  v_max_price numeric(12,4);
  v_last_price numeric(12,4);
  v_last_supplier_id uuid;
  v_last_purchase_date date;
  v_avg_quantity numeric(12,4);
  v_stddev_quantity numeric(12,4);
  v_thirty_day_avg numeric(12,4);
  v_prior_thirty_day_avg numeric(12,4);
  v_trend_percent numeric(12,4);
BEGIN
  IF auth.uid() IS NOT NULL AND NOT (p_company_id = ANY(public.user_company_ids())) THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  WITH scoped AS (
    SELECT
      pp.*,
      COALESCE(pp.date, pp.observed_at::date) AS purchase_day
    FROM product_prices pp
    WHERE pp.company_id = p_company_id
      AND pp.product_id = p_product_id
      AND pp.price > 0
  ), latest AS (
    SELECT price, supplier_id, purchase_day
    FROM scoped
    ORDER BY purchase_day DESC NULLS LAST, observed_at DESC
    LIMIT 1
  ), aggregate_stats AS (
    SELECT
      COUNT(*)::integer AS sample_count,
      COUNT(DISTINCT supplier_id)::integer AS supplier_count,
      AVG(price)::numeric(12,4) AS avg_price,
      percentile_cont(0.5) WITHIN GROUP (ORDER BY price)::numeric(12,4) AS median_price,
      COALESCE(stddev_samp(price), 0)::numeric(12,4) AS stddev_price,
      MIN(price)::numeric(12,4) AS min_price,
      MAX(price)::numeric(12,4) AS max_price,
      AVG(quantity) FILTER (WHERE quantity IS NOT NULL AND quantity > 0)::numeric(12,4) AS avg_quantity,
      COALESCE(stddev_samp(quantity) FILTER (WHERE quantity IS NOT NULL AND quantity > 0), 0)::numeric(12,4) AS stddev_quantity,
      AVG(price) FILTER (WHERE purchase_day >= current_date - interval '30 days')::numeric(12,4) AS thirty_day_avg,
      AVG(price) FILTER (
        WHERE purchase_day < current_date - interval '30 days'
          AND purchase_day >= current_date - interval '60 days'
      )::numeric(12,4) AS prior_thirty_day_avg
    FROM scoped
  )
  SELECT
    a.sample_count,
    a.supplier_count,
    a.avg_price,
    a.median_price,
    a.stddev_price,
    a.min_price,
    a.max_price,
    l.price,
    l.supplier_id,
    l.purchase_day,
    a.avg_quantity,
    a.stddev_quantity,
    a.thirty_day_avg,
    a.prior_thirty_day_avg,
    CASE
      WHEN a.prior_thirty_day_avg IS NULL OR a.prior_thirty_day_avg = 0 OR a.thirty_day_avg IS NULL THEN NULL
      ELSE ((a.thirty_day_avg - a.prior_thirty_day_avg) / a.prior_thirty_day_avg * 100)::numeric(12,4)
    END
  INTO
    v_sample_count,
    v_supplier_count,
    v_avg_price,
    v_median_price,
    v_stddev_price,
    v_min_price,
    v_max_price,
    v_last_price,
    v_last_supplier_id,
    v_last_purchase_date,
    v_avg_quantity,
    v_stddev_quantity,
    v_thirty_day_avg,
    v_prior_thirty_day_avg,
    v_trend_percent
  FROM aggregate_stats a
  LEFT JOIN latest l ON true;

  INSERT INTO product_price_stats (
    company_id,
    product_id,
    sample_count,
    supplier_count,
    avg_price,
    median_price,
    stddev_price,
    min_price,
    max_price,
    last_price,
    last_supplier_id,
    last_purchase_date,
    avg_quantity,
    stddev_quantity,
    thirty_day_avg,
    prior_thirty_day_avg,
    trend_percent,
    updated_at
  ) VALUES (
    p_company_id,
    p_product_id,
    COALESCE(v_sample_count, 0),
    COALESCE(v_supplier_count, 0),
    v_avg_price,
    v_median_price,
    v_stddev_price,
    v_min_price,
    v_max_price,
    v_last_price,
    v_last_supplier_id,
    v_last_purchase_date,
    v_avg_quantity,
    v_stddev_quantity,
    v_thirty_day_avg,
    v_prior_thirty_day_avg,
    v_trend_percent,
    now()
  )
  ON CONFLICT (company_id, product_id) DO UPDATE SET
    sample_count = EXCLUDED.sample_count,
    supplier_count = EXCLUDED.supplier_count,
    avg_price = EXCLUDED.avg_price,
    median_price = EXCLUDED.median_price,
    stddev_price = EXCLUDED.stddev_price,
    min_price = EXCLUDED.min_price,
    max_price = EXCLUDED.max_price,
    last_price = EXCLUDED.last_price,
    last_supplier_id = EXCLUDED.last_supplier_id,
    last_purchase_date = EXCLUDED.last_purchase_date,
    avg_quantity = EXCLUDED.avg_quantity,
    stddev_quantity = EXCLUDED.stddev_quantity,
    thirty_day_avg = EXCLUDED.thirty_day_avg,
    prior_thirty_day_avg = EXCLUDED.prior_thirty_day_avg,
    trend_percent = EXCLUDED.trend_percent,
    updated_at = now();
END;
$$;

GRANT EXECUTE ON FUNCTION public.refresh_product_price_stats(uuid, uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.resolve_price_anomaly(
  p_company_id uuid,
  p_anomaly_id uuid,
  p_resolution_status price_anomaly_resolution_status,
  p_resolution_note text DEFAULT NULL
)
RETURNS price_anomalies
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row price_anomalies;
BEGIN
  IF NOT (p_company_id = ANY(public.user_company_ids())) THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  UPDATE price_anomalies
     SET resolved = p_resolution_status <> 'open',
         resolution_status = p_resolution_status,
         resolution_note = p_resolution_note,
         resolved_at = CASE WHEN p_resolution_status = 'open' THEN NULL ELSE now() END,
         resolved_by = CASE WHEN p_resolution_status = 'open' THEN NULL ELSE auth.uid() END
   WHERE id = p_anomaly_id
     AND company_id = p_company_id
   RETURNING * INTO v_row;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Anomaly not found';
  END IF;

  IF p_resolution_status = 'baseline_approved' THEN
    UPDATE product_price_stats
       SET baseline_price = v_row.current_price,
           baseline_approved_at = now(),
           updated_at = now()
     WHERE company_id = v_row.company_id
       AND product_id = v_row.product_id;
  END IF;

  RETURN v_row;
END;
$$;

GRANT EXECUTE ON FUNCTION public.resolve_price_anomaly(uuid, uuid, price_anomaly_resolution_status, text) TO authenticated;

-- ---------------------------------------------------------------------------
-- 5) Backfill cached stats for existing product price history.
-- ---------------------------------------------------------------------------

DO $$
DECLARE
  r record;
BEGIN
  FOR r IN
    SELECT DISTINCT company_id, product_id
    FROM product_prices
    WHERE product_id IS NOT NULL
  LOOP
    PERFORM public.refresh_product_price_stats(r.company_id, r.product_id);
  END LOOP;
END;
$$;

-- ---------------------------------------------------------------------------
-- 6) Realtime alerts.
-- ---------------------------------------------------------------------------

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
    IF NOT EXISTS (
      SELECT 1
      FROM pg_publication_tables
      WHERE pubname = 'supabase_realtime'
        AND schemaname = 'public'
        AND tablename = 'price_anomalies'
    ) THEN
      ALTER PUBLICATION supabase_realtime ADD TABLE price_anomalies;
    END IF;

    IF NOT EXISTS (
      SELECT 1
      FROM pg_publication_tables
      WHERE pubname = 'supabase_realtime'
        AND schemaname = 'public'
        AND tablename = 'product_price_stats'
    ) THEN
      ALTER PUBLICATION supabase_realtime ADD TABLE product_price_stats;
    END IF;
  END IF;
END;
$$;

COMMIT;
