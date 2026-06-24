-- ============================================================================
-- Migration 20260510: Product intelligence pipeline hardening
--
-- Adds:
--   1) normalized_name column on products for canonical matching
--   2) product_aliases table for OCR variation deduplication
--   3) supplier/date enrichment on product_prices
--   4) normalized_description on document_items
--   5) helper RPCs for exact alias and candidate lookup
-- ============================================================================

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;

ALTER TABLE products
  ADD COLUMN IF NOT EXISTS normalized_name text GENERATED ALWAYS AS (
    lower(trim(regexp_replace(immutable_unaccent(name), '[^a-zA-Z0-9]', '', 'g')))
  ) STORED;

CREATE INDEX IF NOT EXISTS idx_products_company_normalized_name
  ON products (company_id, normalized_name)
  WHERE is_active = true;

ALTER TABLE document_items
  ADD COLUMN IF NOT EXISTS normalized_description text;

CREATE INDEX IF NOT EXISTS idx_document_items_company_normalized_description
  ON document_items (company_id, normalized_description)
  WHERE normalized_description IS NOT NULL;

CREATE TABLE IF NOT EXISTS product_prices (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  product_id uuid NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  document_id uuid REFERENCES documents(id) ON DELETE SET NULL,
  document_item_id uuid REFERENCES document_items(id) ON DELETE SET NULL,
  price numeric(12,4) NOT NULL,
  quantity numeric(12,3),
  unit text,
  observed_at timestamptz NOT NULL DEFAULT now(),
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE product_prices
  ADD COLUMN IF NOT EXISTS supplier_id uuid REFERENCES providers(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS date date;

UPDATE product_prices
   SET date = COALESCE(date, observed_at::date)
 WHERE date IS NULL;

CREATE INDEX IF NOT EXISTS idx_product_prices_company_product_date
  ON product_prices (company_id, product_id, date DESC NULLS LAST, observed_at DESC);

CREATE INDEX IF NOT EXISTS idx_product_prices_company_supplier
  ON product_prices (company_id, supplier_id, date DESC NULLS LAST)
  WHERE supplier_id IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS idx_product_prices_document_item_unique
  ON product_prices (document_item_id)
  WHERE document_item_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS product_aliases (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  product_id uuid NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  raw_name text NOT NULL,
  normalized_name text GENERATED ALWAYS AS (
    lower(trim(regexp_replace(immutable_unaccent(raw_name), '[^a-zA-Z0-9]', '', 'g')))
  ) STORED,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_product_aliases_company_normalized_unique
  ON product_aliases (company_id, normalized_name);

CREATE INDEX IF NOT EXISTS idx_product_aliases_company_product
  ON product_aliases (company_id, product_id, created_at DESC);

ALTER TABLE product_aliases ENABLE ROW LEVEL SECURITY;
ALTER TABLE product_aliases FORCE ROW LEVEL SECURITY;

ALTER TABLE product_prices ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS product_aliases_isolation ON product_aliases;
CREATE POLICY product_aliases_isolation ON product_aliases
  FOR ALL
  TO authenticated
  USING (company_id = ANY(public.user_company_ids()))
  WITH CHECK (company_id = ANY(public.user_company_ids()));

DROP POLICY IF EXISTS product_prices_isolation ON product_prices;
CREATE POLICY product_prices_isolation ON product_prices
  FOR ALL
  TO authenticated
  USING (company_id = ANY(public.user_company_ids()))
  WITH CHECK (company_id = ANY(public.user_company_ids()));

ALTER TABLE product_prices FORCE ROW LEVEL SECURITY;

INSERT INTO product_aliases (company_id, product_id, raw_name)
SELECT p.company_id, p.id, p.name
  FROM products p
 WHERE NOT EXISTS (
   SELECT 1
     FROM product_aliases pa
    WHERE pa.company_id = p.company_id
      AND pa.product_id = p.id
      AND pa.normalized_name = p.normalized_name
   )
  ON CONFLICT (company_id, normalized_name) DO NOTHING;

CREATE OR REPLACE FUNCTION public.find_product_alias_match(
  p_company_id uuid,
  p_normalized_name text
)
RETURNS TABLE (
  product_id uuid,
  product_name text,
  alias_name text,
  normalized_name text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    pa.product_id,
    p.name AS product_name,
    pa.raw_name AS alias_name,
    pa.normalized_name
  FROM product_aliases pa
  JOIN products p
    ON p.id = pa.product_id
   AND p.company_id = pa.company_id
  WHERE pa.company_id = p_company_id
    AND pa.normalized_name = p_normalized_name
    AND p.is_active = true
  LIMIT 1;
$$;

GRANT EXECUTE ON FUNCTION public.find_product_alias_match(uuid, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.find_product_candidates(
  p_company_id uuid,
  p_normalized_name text,
  p_limit integer DEFAULT 5
)
RETURNS TABLE (
  product_id uuid,
  product_name text,
  alias_name text,
  score double precision,
  match_source text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  WITH alias_candidates AS (
    SELECT
      pa.product_id,
      p.name AS product_name,
      pa.raw_name AS alias_name,
      GREATEST(
        similarity(pa.normalized_name, p_normalized_name),
        CASE WHEN pa.normalized_name ILIKE '%' || p_normalized_name || '%' THEN 0.72 ELSE 0 END
      ) AS score,
      'alias'::text AS match_source
    FROM product_aliases pa
    JOIN products p
      ON p.id = pa.product_id
     AND p.company_id = pa.company_id
    WHERE pa.company_id = p_company_id
      AND p.is_active = true
      AND (
        pa.normalized_name ILIKE '%' || p_normalized_name || '%'
        OR similarity(pa.normalized_name, p_normalized_name) > 0.28
      )
  ),
  product_candidates AS (
    SELECT
      p.id AS product_id,
      p.name AS product_name,
      NULL::text AS alias_name,
      GREATEST(
        similarity(COALESCE(p.normalized_name, p.name_normalized), p_normalized_name),
        CASE WHEN COALESCE(p.normalized_name, p.name_normalized) ILIKE '%' || p_normalized_name || '%' THEN 0.68 ELSE 0 END
      ) AS score,
      'product'::text AS match_source
    FROM products p
    WHERE p.company_id = p_company_id
      AND p.is_active = true
      AND (
        COALESCE(p.normalized_name, p.name_normalized) ILIKE '%' || p_normalized_name || '%'
        OR similarity(COALESCE(p.normalized_name, p.name_normalized), p_normalized_name) > 0.28
      )
  )
  SELECT *
  FROM (
    SELECT * FROM alias_candidates
    UNION ALL
    SELECT * FROM product_candidates
  ) candidates
  ORDER BY score DESC, product_name ASC
  LIMIT GREATEST(COALESCE(p_limit, 5), 1);
$$;

GRANT EXECUTE ON FUNCTION public.find_product_candidates(uuid, text, integer) TO authenticated;

COMMIT;