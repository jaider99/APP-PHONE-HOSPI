-- ============================================================================
-- Migration 20260505: Supplier Intelligence System
-- ============================================================================
-- Transforms the static providers list into an intelligent supplier system.
--
-- Adds:
--   1) supplier_aliases — maps raw OCR names to canonical provider records
--   2) resolve_supplier() — fuzzy-match + auto-create RPC with noise stripping
--   3) auto_resolve_supplier trigger — fires on documents.status='completed'
--      and applies better fuzzy matching than the edge function's simple ilike
--   4) v_supplier_intelligence — pre-aggregated supplier metrics view
--   5) Indexes for query performance
-- ============================================================================

BEGIN;

-- Ensure pg_trgm is available (already enabled in 00001, defensive repeat)
CREATE EXTENSION IF NOT EXISTS "pg_trgm";

-- ============================================================================
-- 1) SUPPLIER ALIASES TABLE
-- ============================================================================
-- Caches the mapping from raw OCR names → canonical provider.
-- Enables O(1) lookup on repeated documents from the same supplier.

CREATE TABLE IF NOT EXISTS supplier_aliases (
    id          UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id  UUID        NOT NULL REFERENCES companies(id)  ON DELETE CASCADE,
    provider_id UUID        NOT NULL REFERENCES providers(id)  ON DELETE CASCADE,
    raw_name    TEXT        NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT supplier_aliases_unique_raw_name UNIQUE (company_id, raw_name)
);

CREATE INDEX IF NOT EXISTS idx_supplier_aliases_company_provider
    ON supplier_aliases (company_id, provider_id);

CREATE INDEX IF NOT EXISTS idx_supplier_aliases_raw_gin
    ON supplier_aliases USING gin (lower(raw_name) gin_trgm_ops)
    WHERE raw_name IS NOT NULL;

ALTER TABLE supplier_aliases ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS supplier_aliases_tenant_isolation ON supplier_aliases;
CREATE POLICY supplier_aliases_tenant_isolation ON supplier_aliases
    FOR ALL
    TO authenticated
    USING  (company_id = ANY(public.user_company_ids()))
    WITH CHECK (company_id = ANY(public.user_company_ids()));

-- ============================================================================
-- 2) SUPPLIER NAME CLEANING HELPER
--    Strips document-type noise words that OCR picks up as part of the name.
--    Example: "Escola Vins i Destil·lats ALBARÁN" → "Escola Vins i Destil·lats"
-- ============================================================================

CREATE OR REPLACE FUNCTION clean_supplier_name(p_raw TEXT)
RETURNS TEXT
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
    v TEXT;
BEGIN
    IF p_raw IS NULL THEN RETURN NULL; END IF;
    v := trim(p_raw);

    -- Strip trailing/leading Spanish document type noise
    v := regexp_replace(v,
        '\s+(albar[aá]n|factura|albar[aá]n\s+de\s+entrega|nota\s+de\s+cr[eé]dito|'
        'presupuesto|pedido|ticket|recibo|delivery\s+note|invoice)\s*$',
        '', 'gi');

    v := trim(v);
    RETURN NULLIF(v, '');
END;
$$;

-- ============================================================================
-- 3) RESOLVE SUPPLIER RPC
--    Better resolution logic than the edge function's simple ilike:
--      1. Alias cache (exact raw → provider_id, O(1))
--      2. Exact tax-ID match
--      3. Fuzzy name match ≥ 85% similarity (via pg_trgm)
--      4. Auto-create if no match
--    Always caches the raw_name in supplier_aliases for future calls.
-- ============================================================================

CREATE OR REPLACE FUNCTION resolve_supplier(
    p_company_id  UUID,
    p_raw_name    TEXT,
    p_tax_id      TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_provider_id  UUID;
    v_clean_name   TEXT;
    v_score        NUMERIC;
BEGIN
    -- Guard
    IF p_raw_name IS NULL OR trim(p_raw_name) = '' THEN
        RETURN NULL;
    END IF;

    -- ── 1. Alias cache ──────────────────────────────────────────────────
    SELECT provider_id INTO v_provider_id
    FROM supplier_aliases
    WHERE company_id = p_company_id
      AND lower(trim(raw_name)) = lower(trim(p_raw_name))
    LIMIT 1;

    IF v_provider_id IS NOT NULL THEN
        RETURN v_provider_id;
    END IF;

    -- ── Clean the name before fuzzy matching ────────────────────────────
    v_clean_name := COALESCE(clean_supplier_name(p_raw_name), p_raw_name);

    -- ── 2. Exact tax-ID match ───────────────────────────────────────────
    IF p_tax_id IS NOT NULL AND trim(p_tax_id) <> '' THEN
        SELECT id INTO v_provider_id
        FROM providers
        WHERE company_id  = p_company_id
          AND is_active   = TRUE
          AND normalize_tax_id(tax_id) = normalize_tax_id(p_tax_id)
        LIMIT 1;

        IF v_provider_id IS NOT NULL THEN
            INSERT INTO supplier_aliases (company_id, provider_id, raw_name)
            VALUES (p_company_id, v_provider_id, p_raw_name)
            ON CONFLICT (company_id, raw_name) DO NOTHING;
            RETURN v_provider_id;
        END IF;
    END IF;

    -- ── 3. Fuzzy name match (≥ 85%) ─────────────────────────────────────
    SELECT
        id,
        name_similarity_score(name, v_clean_name) AS score
    INTO v_provider_id, v_score
    FROM providers
    WHERE company_id = p_company_id
      AND is_active  = TRUE
      AND similarity(
              normalize_business_name(name),
              normalize_business_name(v_clean_name)
          ) >= 0.85
    ORDER BY score DESC
    LIMIT 1;

    IF v_provider_id IS NOT NULL THEN
        INSERT INTO supplier_aliases (company_id, provider_id, raw_name)
        VALUES (p_company_id, v_provider_id, p_raw_name)
        ON CONFLICT (company_id, raw_name) DO NOTHING;
        RETURN v_provider_id;
    END IF;

    -- ── 4. No match — create new canonical provider ─────────────────────
    -- Use the cleaned name so "Escola Vins ALBARÁN" becomes "Escola Vins"
    INSERT INTO providers (company_id, name, tax_id)
    VALUES (p_company_id, v_clean_name, p_tax_id)
    ON CONFLICT (company_id, name_normalized)
        DO UPDATE SET updated_at = NOW()
    RETURNING id INTO v_provider_id;

    -- Cache both the cleaned and raw forms
    INSERT INTO supplier_aliases (company_id, provider_id, raw_name)
    VALUES (p_company_id, v_provider_id, p_raw_name)
    ON CONFLICT (company_id, raw_name) DO NOTHING;

    IF lower(trim(v_clean_name)) <> lower(trim(p_raw_name)) THEN
        INSERT INTO supplier_aliases (company_id, provider_id, raw_name)
        VALUES (p_company_id, v_provider_id, v_clean_name)
        ON CONFLICT (company_id, raw_name) DO NOTHING;
    END IF;

    RETURN v_provider_id;
END;
$$;

-- Grant execute to authenticated users (Supabase RPC calls from Flutter)
GRANT EXECUTE ON FUNCTION resolve_supplier(UUID, TEXT, TEXT) TO authenticated;

-- ============================================================================
-- 4) AUTO-RESOLVE TRIGGER
--    Fires BEFORE every documents.status UPDATE.
--    When status transitions to 'completed':
--      - Reads supplier_name from extraction_clean JSONB
--      - Applies better fuzzy matching via resolve_supplier()
--      - Overwrites provider_id with the canonical match
--    This corrects cases where the edge function's simple ilike created a
--    duplicate provider (e.g., "Escola Vins ALBARÁN" vs "Escola Vins").
-- ============================================================================

CREATE OR REPLACE FUNCTION auto_resolve_supplier_trigger_fn()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_raw_name    TEXT;
    v_tax_id      TEXT;
    v_provider_id UUID;
BEGIN
    -- Only run when transitioning INTO 'completed'
    IF NEW.status <> 'completed' OR OLD.status = 'completed' THEN
        RETURN NEW;
    END IF;

    -- Extract supplier name: prefer direct column, fall back to extraction_clean JSON
    v_raw_name := COALESCE(
        NULLIF(trim(NEW.extraction_clean->>'supplier_name'), ''),
        NULL
    );

    IF v_raw_name IS NULL THEN
        RETURN NEW;
    END IF;

    -- Optionally extract tax ID from extraction for better matching
    v_tax_id := NULLIF(trim(NEW.extraction_clean->>'supplier_tax_id'), '');

    -- Resolve with improved fuzzy logic
    v_provider_id := resolve_supplier(NEW.company_id, v_raw_name, v_tax_id);

    IF v_provider_id IS NOT NULL THEN
        NEW.provider_id := v_provider_id;
    END IF;

    RETURN NEW;
END;
$$;

-- Attach trigger (replace if exists)
DROP TRIGGER IF EXISTS auto_resolve_supplier ON documents;
CREATE TRIGGER auto_resolve_supplier
    BEFORE UPDATE OF status ON documents
    FOR EACH ROW
    EXECUTE FUNCTION auto_resolve_supplier_trigger_fn();

-- ============================================================================
-- 5) SUPPLIER INTELLIGENCE VIEW
--    Aggregates spend metrics per provider for the Flutter supplier list.
--    Joined with documents; LEFT JOIN so providers with 0 documents appear.
-- ============================================================================

CREATE OR REPLACE VIEW v_supplier_intelligence
WITH (security_invoker = true)
AS
SELECT
    p.id,
    p.company_id,
    p.name,
    p.category,
    p.is_active,
    p.created_at,

    -- Aggregate spend from completed, non-deleted documents with known date
    COUNT(DISTINCT d.id)                                    AS total_orders,
    COALESCE(SUM(d.total_amount), 0)                        AS total_spent,
    MAX(d.document_date)                                    AS last_order_date,

    -- Current calendar month spend
    COALESCE(SUM(
        CASE WHEN d.document_date >= date_trunc('month', CURRENT_DATE)::date
             THEN d.total_amount ELSE 0 END
    ), 0)                                                   AS current_month_spent,

    -- Previous calendar month spend
    COALESCE(SUM(
        CASE WHEN d.document_date >= (date_trunc('month', CURRENT_DATE) - INTERVAL '1 month')::date
              AND d.document_date  <  date_trunc('month', CURRENT_DATE)::date
             THEN d.total_amount ELSE 0 END
    ), 0)                                                   AS prior_month_spent

FROM providers p
LEFT JOIN documents d
    ON  d.provider_id    = p.id
    AND d.status         = 'completed'
    AND d.deleted_at     IS NULL
    AND d.document_date  IS NOT NULL
    AND d.total_amount   IS NOT NULL

GROUP BY
    p.id, p.company_id, p.name, p.category, p.is_active, p.created_at;

-- ============================================================================
-- 6) PERFORMANCE INDEXES
-- ============================================================================

-- Fast lookup: all completed docs for a given provider
CREATE INDEX IF NOT EXISTS idx_documents_provider_status_date
    ON documents (company_id, provider_id, status, document_date DESC)
    WHERE provider_id IS NOT NULL AND deleted_at IS NULL;

-- Fast lookup: document_items for a provider (via document)
CREATE INDEX IF NOT EXISTS idx_documents_provider_id
    ON documents (provider_id)
    WHERE provider_id IS NOT NULL;

-- Fuzzy match index on providers.name_normalized (GIN trgm)
CREATE INDEX IF NOT EXISTS idx_providers_name_trgm
    ON providers USING gin (name_normalized gin_trgm_ops);

-- Alias cache index
CREATE INDEX IF NOT EXISTS idx_supplier_aliases_lower_raw
    ON supplier_aliases (company_id, lower(trim(raw_name)));

COMMIT;
