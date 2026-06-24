-- ============================================================================
-- Migration 20260424: Product Recognition Pipeline
-- ============================================================================
-- Adds:
--   1) image_url + category_id FK to products
--   2) product_prices table (price history per document line_item)
--   3) trgm GIN index on products.name_normalized for fuzzy matching
--   4) PostgreSQL function for similarity-based product lookup
--   5) RLS for product_prices
--   6) Products storage bucket
-- ============================================================================

BEGIN;

-- ============================================================================
-- 1) EXTEND products TABLE
-- ============================================================================

-- AI-generated product image stored in Supabase Storage or external URL
ALTER TABLE products
  ADD COLUMN IF NOT EXISTS image_url text;

-- Link product to an expense category
ALTER TABLE products
  ADD COLUMN IF NOT EXISTS category_id uuid REFERENCES categories(id) ON DELETE SET NULL;

-- ============================================================================
-- 2) PRODUCT_PRICES TABLE — price history per document line item
-- ============================================================================

CREATE TABLE IF NOT EXISTS product_prices (
  id           uuid          PRIMARY KEY DEFAULT uuid_generate_v4(),
  company_id   uuid          NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  product_id   uuid          NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  document_id  uuid          REFERENCES documents(id) ON DELETE SET NULL,
  document_item_id uuid      REFERENCES document_items(id) ON DELETE SET NULL,
  price        numeric(12,4) NOT NULL,   -- unit price (line_total / quantity)
  quantity     numeric(12,3),
  unit         text,
  observed_at  timestamptz   NOT NULL DEFAULT now(),
  created_at   timestamptz   NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_product_prices_product_date
  ON product_prices (product_id, observed_at DESC);

CREATE INDEX IF NOT EXISTS idx_product_prices_company_date
  ON product_prices (company_id, observed_at DESC);

CREATE INDEX IF NOT EXISTS idx_product_prices_document
  ON product_prices (document_id);

-- ============================================================================
-- 3) FUZZY MATCH INDEX — GIN trgm on products.name_normalized
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_products_trgm
  ON products USING gin (name_normalized gin_trgm_ops);

-- Composite index for company-scoped catalogue queries
CREATE INDEX IF NOT EXISTS idx_products_company_normalized
  ON products (company_id, name_normalized);

-- ============================================================================
-- 4) SIMILARITY SEARCH FUNCTION
-- ============================================================================

-- Called from the recognize-products edge function via supabase.rpc().
-- Returns the best-matching product_id + name for a given normalized name.
CREATE OR REPLACE FUNCTION public.find_product_by_similarity(
  p_company_id      uuid,
  p_normalized_name text,
  p_threshold       float DEFAULT 0.35
)
RETURNS TABLE (
  id         uuid,
  name       text,
  sim        float
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    p.id,
    p.name,
    similarity(p.name_normalized, p_normalized_name) AS sim
  FROM products p
  WHERE p.company_id = p_company_id
    AND p.is_active = true
    AND similarity(p.name_normalized, p_normalized_name) > p_threshold
  ORDER BY sim DESC
  LIMIT 1;
$$;

-- ============================================================================
-- 5) RLS FOR product_prices
-- ============================================================================

ALTER TABLE product_prices ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS product_prices_isolation ON product_prices;
CREATE POLICY product_prices_isolation ON product_prices
  FOR ALL
  USING  (company_id = ANY(public.user_company_ids()))
  WITH CHECK (company_id = ANY(public.user_company_ids()));

-- ============================================================================
-- 6) PRODUCTS STORAGE BUCKET
-- ============================================================================

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'products',
  'products',
  TRUE,
  5242880,  -- 5 MB
  ARRAY['image/jpeg', 'image/png', 'image/webp']
)
ON CONFLICT (id) DO NOTHING;

-- Allow authenticated users to upload product images for their company
DROP POLICY IF EXISTS "products_upload_own_company" ON storage.objects;
CREATE POLICY "products_upload_own_company"
  ON storage.objects
  FOR INSERT
  TO authenticated
  WITH CHECK (
    bucket_id = 'products'
    AND (storage.foldername(name))[1] = ANY(
      SELECT company_id::text FROM company_users
      WHERE user_id = auth.uid() AND is_active = true
    )
  );

DROP POLICY IF EXISTS "products_images_public_read" ON storage.objects;
CREATE POLICY "products_images_public_read"
  ON storage.objects
  FOR SELECT
  TO public
  USING (bucket_id = 'products');

DROP POLICY IF EXISTS "products_images_service_write" ON storage.objects;
CREATE POLICY "products_images_service_write"
  ON storage.objects
  FOR ALL
  TO service_role
  USING (bucket_id = 'products')
  WITH CHECK (bucket_id = 'products');

COMMIT;
