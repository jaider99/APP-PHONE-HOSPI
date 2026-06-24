-- ============================================================================
-- Migration 20260517: Intelligence Analytics Layer
--
-- Adds:
--   1) document_items.supplier_id  — ties each line item to its supplier
--      so product-level spend can be broken down by supplier without
--      needing to go through the parent document.
--   2) v_category_intelligence    — pre-aggregated per-category metrics
--      (total spend, order count, current-month, prior-month).
--   3) v_top_products_by_spend    — top products ranked by spend this month
--      and overall, with category and supplier context.
--   4) Helper indexes for all new query patterns.
--
-- Multi-tenancy: all views use security_invoker = true, relying on the
-- existing RLS on the underlying tables.  No security model changes.
-- ============================================================================

BEGIN;

-- ============================================================================
-- 0) products.category_id guard
--    Added by 20260424_product_recognition.sql; repeated here with IF NOT EXISTS
--    so this migration is safe to run on databases that skipped that migration.
-- ============================================================================

ALTER TABLE products
  ADD COLUMN IF NOT EXISTS image_url     TEXT;

ALTER TABLE products
  ADD COLUMN IF NOT EXISTS category_id  UUID REFERENCES categories(id) ON DELETE SET NULL;

-- ============================================================================
-- 1) document_items.supplier_id
--    Links each extracted line item to the supplier that issued the document.
--    Set by recognize-products after deployment of this migration.
-- ============================================================================

ALTER TABLE document_items
  ADD COLUMN IF NOT EXISTS supplier_id UUID REFERENCES providers(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_document_items_supplier
  ON document_items (company_id, supplier_id)
  WHERE supplier_id IS NOT NULL;

-- ============================================================================
-- 2) v_category_intelligence
--    Aggregated per-category expense metrics for the current company.
--
--    Reads from documents (not expenses) so it works even for companies
--    that have not yet created expense records — any completed document
--    with a category_id contributes.
--
--    Columns:
--      id                  — category UUID
--      company_id          — tenant key
--      name                — category display name
--      color_hex           — category colour
--      total_documents     — count of distinct completed documents
--      total_spent         — sum of total_amount across those documents
--      current_month_spent — total_amount for current calendar month
--      prior_month_spent   — total_amount for prior calendar month
--      last_document_date  — most recent document_date with this category
-- ============================================================================

CREATE OR REPLACE VIEW v_category_intelligence
WITH (security_invoker = true)
AS
SELECT
    c.id,
    c.company_id,
    c.name,
    c.color_hex,
    c.icon,
    c.sort_order,

    COUNT(DISTINCT d.id)                                        AS total_documents,
    COALESCE(SUM(d.total_amount), 0)                            AS total_spent,

    COALESCE(SUM(
        CASE WHEN d.document_date >= date_trunc('month', CURRENT_DATE)::date
             THEN d.total_amount ELSE 0 END
    ), 0)                                                       AS current_month_spent,

    COALESCE(SUM(
        CASE WHEN d.document_date >= (date_trunc('month', CURRENT_DATE) - INTERVAL '1 month')::date
              AND d.document_date  <   date_trunc('month', CURRENT_DATE)::date
             THEN d.total_amount ELSE 0 END
    ), 0)                                                       AS prior_month_spent,

    MAX(d.document_date)                                        AS last_document_date

FROM categories c
LEFT JOIN documents d
    ON  d.category_id   = c.id
    AND d.company_id    = c.company_id
    AND d.status        = 'completed'
    AND d.deleted_at    IS NULL
    AND d.document_date IS NOT NULL
    AND d.total_amount  IS NOT NULL
    AND (d.merge_status IS NULL OR d.merge_status != 'merged')

GROUP BY
    c.id, c.company_id, c.name, c.color_hex, c.icon, c.sort_order;

-- ============================================================================
-- 3) v_top_products_by_spend
--    Top products ranked by total line-item spend within a company.
--
--    Aggregates product_prices (one row per document line item) rather than
--    summing document totals so that multi-item documents do not double-count.
--
--    Columns:
--      product_id          — products.id
--      company_id          — tenant key
--      product_name        — canonical product name
--      category_id         — linked category (if any)
--      category_name       — denormalised for UI
--      category_color      — denormalised colour
--      supplier_id         — most recent supplier (by observed_at)
--      supplier_name       — denormalised
--      image_url           — product image
--      total_quantity      — total units purchased (all time)
--      total_spent         — total cost (all time)
--      current_month_spent — cost in current calendar month
--      prior_month_spent   — cost in prior calendar month
--      latest_price        — unit price from most recent purchase
--      min_price           — cheapest unit price ever recorded
--      max_price           — most expensive unit price ever recorded
--      purchase_count      — number of distinct purchase events
-- ============================================================================

CREATE OR REPLACE VIEW v_top_products_by_spend
WITH (security_invoker = true)
AS
SELECT
    p.id                                                        AS product_id,
    p.company_id,
    p.name                                                      AS product_name,
    p.image_url,
    p.category_id,
    cat.name                                                    AS category_name,
    cat.color_hex                                               AS category_color,

    -- Most recent supplier for this product
    (
        SELECT pp2.supplier_id
        FROM product_prices pp2
        WHERE pp2.product_id  = p.id
          AND pp2.company_id  = p.company_id
          AND pp2.supplier_id IS NOT NULL
        ORDER BY pp2.observed_at DESC
        LIMIT 1
    )                                                           AS supplier_id,

    (
        SELECT prov.name
        FROM product_prices pp2
        JOIN providers prov ON prov.id = pp2.supplier_id
        WHERE pp2.product_id  = p.id
          AND pp2.company_id  = p.company_id
          AND pp2.supplier_id IS NOT NULL
        ORDER BY pp2.observed_at DESC
        LIMIT 1
    )                                                           AS supplier_name,

    -- Quantity aggregates
    COALESCE(SUM(pp.quantity), 0)                               AS total_quantity,

    -- Spend aggregates (price × quantity, falling back to price if no quantity)
    COALESCE(SUM(
        pp.price * COALESCE(pp.quantity, 1)
    ), 0)                                                       AS total_spent,

    COALESCE(SUM(
        CASE WHEN pp.date >= date_trunc('month', CURRENT_DATE)::date
             THEN pp.price * COALESCE(pp.quantity, 1) ELSE 0 END
    ), 0)                                                       AS current_month_spent,

    COALESCE(SUM(
        CASE WHEN pp.date >= (date_trunc('month', CURRENT_DATE) - INTERVAL '1 month')::date
              AND pp.date  <   date_trunc('month', CURRENT_DATE)::date
             THEN pp.price * COALESCE(pp.quantity, 1) ELSE 0 END
    ), 0)                                                       AS prior_month_spent,

    -- Price analytics
    (
        SELECT pp3.price
        FROM product_prices pp3
        WHERE pp3.product_id = p.id
          AND pp3.company_id = p.company_id
        ORDER BY pp3.observed_at DESC
        LIMIT 1
    )                                                           AS latest_price,

    MIN(pp.price)                                               AS min_price,
    MAX(pp.price)                                               AS max_price,
    COUNT(DISTINCT pp.id)                                       AS purchase_count

FROM products p
JOIN product_prices pp
    ON  pp.product_id = p.id
    AND pp.company_id = p.company_id
LEFT JOIN categories cat
    ON  cat.id         = p.category_id
    AND cat.company_id = p.company_id

WHERE p.is_active = true

GROUP BY
    p.id, p.company_id, p.name, p.image_url, p.category_id,
    cat.name, cat.color_hex;

-- ============================================================================
-- 4) Performance indexes
-- ============================================================================

-- Category intelligence: fast per-company category + status + date scans
CREATE INDEX IF NOT EXISTS idx_documents_company_category_status_date
  ON documents (company_id, category_id, status, document_date DESC)
  WHERE category_id IS NOT NULL AND deleted_at IS NULL;

-- Top products: product_prices per product with date for month slicing
CREATE INDEX IF NOT EXISTS idx_product_prices_product_date_company
  ON product_prices (company_id, product_id, date DESC NULLS LAST)
  WHERE date IS NOT NULL;

COMMIT;
