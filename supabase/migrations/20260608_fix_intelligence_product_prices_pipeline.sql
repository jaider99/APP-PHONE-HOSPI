-- Fix product price observation persistence for dashboard intelligence.
-- The recognizer upserts ON CONFLICT (document_item_id); Postgres needs a
-- matching non-partial unique arbiter for that conflict target.

DROP INDEX IF EXISTS public.idx_product_prices_document_item_unique;

CREATE UNIQUE INDEX IF NOT EXISTS idx_product_prices_document_item_unique
  ON public.product_prices (document_item_id);

WITH price_observations AS (
  SELECT
    di.company_id,
    di.product_id,
    di.document_id,
    di.id AS document_item_id,
    COALESCE(di.supplier_id, d.provider_id) AS supplier_id,
    COALESCE(
      NULLIF(di.unit_price, 0),
      CASE
        WHEN di.line_total IS NOT NULL
          AND di.quantity IS NOT NULL
          AND di.quantity > 0
        THEN di.line_total / di.quantity
        ELSE NULL
      END
    ) AS price,
    di.quantity,
    di.unit_type AS unit,
    d.document_date AS date,
    COALESCE(
      d.document_date::timestamptz + interval '12 hours',
      di.created_at,
      now()
    ) AS observed_at
  FROM public.document_items di
  JOIN public.documents d
    ON d.id = di.document_id
   AND d.company_id = di.company_id
  WHERE di.product_id IS NOT NULL
    AND d.status = 'completed'
    AND d.deleted_at IS NULL
    AND COALESCE(d.is_duplicate, false) = false
    AND COALESCE(d.merge_status, '') <> 'merged'
)
INSERT INTO public.product_prices (
  company_id,
  product_id,
  document_id,
  document_item_id,
  supplier_id,
  price,
  quantity,
  unit,
  date,
  observed_at
)
SELECT
  company_id,
  product_id,
  document_id,
  document_item_id,
  supplier_id,
  price,
  quantity,
  unit,
  date,
  observed_at
FROM price_observations
WHERE price IS NOT NULL
  AND price > 0
ON CONFLICT (document_item_id) DO UPDATE SET
  company_id = EXCLUDED.company_id,
  product_id = EXCLUDED.product_id,
  document_id = EXCLUDED.document_id,
  supplier_id = EXCLUDED.supplier_id,
  price = EXCLUDED.price,
  quantity = EXCLUDED.quantity,
  unit = EXCLUDED.unit,
  date = EXCLUDED.date,
  observed_at = EXCLUDED.observed_at;