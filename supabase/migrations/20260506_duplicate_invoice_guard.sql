-- ============================================================================
-- Migration 20260506: Duplicate Invoice Guard
-- ============================================================================
-- Prevents double-counting invoices while preserving duplicate uploads for audit.
--
-- Strategy:
--   1) Persist normalized dedupe fields on documents
--   2) Detect duplicates inside Postgres (authoritative, multi-tenant safe)
--   3) Exclude duplicates from analytics views
-- ============================================================================

BEGIN;

ALTER TABLE documents
    ADD COLUMN IF NOT EXISTS is_duplicate BOOLEAN NOT NULL DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS duplicate_of UUID NULL REFERENCES documents(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS normalized_document_number TEXT,
    ADD COLUMN IF NOT EXISTS normalized_supplier TEXT;

CREATE INDEX IF NOT EXISTS idx_documents_dedupe
    ON documents (company_id, normalized_document_number, normalized_supplier)
    WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_documents_duplicate_of
    ON documents (duplicate_of)
    WHERE duplicate_of IS NOT NULL;

CREATE OR REPLACE FUNCTION normalize_invoice_document_number(p_raw TEXT)
RETURNS TEXT
LANGUAGE SQL
IMMUTABLE
AS $$
    SELECT NULLIF(
        upper(regexp_replace(trim(COALESCE(p_raw, '')), '[\s\-\/]', '', 'g')),
        ''
    );
$$;

CREATE OR REPLACE FUNCTION normalize_invoice_supplier(p_raw TEXT)
RETURNS TEXT
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
    v TEXT;
BEGIN
    IF p_raw IS NULL THEN
        RETURN NULL;
    END IF;

    v := COALESCE(clean_supplier_name(p_raw), p_raw);
    v := lower(immutable_unaccent(v));
    v := regexp_replace(
        v,
        '\s*(s\.?l\.?u?\.?|s\.?a\.?|ltd\.?|limited|sociedad limitada|sociedad anonima)\s*$',
        '',
        'gi'
    );
    v := regexp_replace(v, '[^a-z0-9\s]', '', 'g');
    v := regexp_replace(v, '\s+', ' ', 'g');
    v := trim(v);

    RETURN NULLIF(v, '');
END;
$$;

CREATE OR REPLACE FUNCTION build_document_dedupe_key(
    p_document_number TEXT,
    p_total_amount NUMERIC DEFAULT NULL,
    p_document_date DATE DEFAULT NULL,
    p_supplier_name TEXT DEFAULT NULL
)
RETURNS TEXT
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
    v_doc TEXT;
    v_supplier TEXT;
BEGIN
    v_doc := normalize_invoice_document_number(p_document_number);
    IF v_doc IS NOT NULL THEN
        RETURN v_doc;
    END IF;

    v_supplier := normalize_invoice_supplier(p_supplier_name);
    IF p_total_amount IS NULL OR p_document_date IS NULL OR v_supplier IS NULL THEN
        RETURN NULL;
    END IF;

    RETURN format(
        'FALLBACK:%s:%s:%s',
        to_char(p_document_date, 'YYYYMMDD'),
        round(p_total_amount * 100)::BIGINT,
        v_supplier
    );
END;
$$;

CREATE OR REPLACE FUNCTION apply_document_duplicate_guard_trigger_fn()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_supplier_name TEXT;
    v_original_id UUID;
BEGIN
    IF NEW.deleted_at IS NOT NULL THEN
        NEW.is_duplicate := FALSE;
        NEW.duplicate_of := NULL;
        RETURN NEW;
    END IF;

    v_supplier_name := COALESCE(
        NULLIF(trim(NEW.extraction_clean->>'supplier_name'), ''),
        (SELECT p.name FROM providers p WHERE p.id = NEW.provider_id),
        NULL
    );

    NEW.normalized_supplier := normalize_invoice_supplier(v_supplier_name);
    NEW.normalized_document_number := build_document_dedupe_key(
        NEW.document_number,
        NEW.total_amount,
        NEW.document_date,
        v_supplier_name
    );

    IF NEW.status <> 'completed'
       OR NEW.normalized_document_number IS NULL
       OR NEW.normalized_supplier IS NULL THEN
        NEW.is_duplicate := FALSE;
        NEW.duplicate_of := NULL;
        RETURN NEW;
    END IF;

    SELECT d.id
      INTO v_original_id
      FROM documents d
     WHERE d.company_id = NEW.company_id
       AND d.deleted_at IS NULL
       AND d.status = 'completed'
       AND COALESCE(d.is_duplicate, FALSE) = FALSE
       AND d.normalized_document_number = NEW.normalized_document_number
       AND d.normalized_supplier = NEW.normalized_supplier
       AND (NEW.id IS NULL OR d.id <> NEW.id)
     ORDER BY d.created_at ASC, d.id ASC
     LIMIT 1;

    NEW.is_duplicate := v_original_id IS NOT NULL;
    NEW.duplicate_of := v_original_id;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS apply_document_duplicate_guard ON documents;
CREATE TRIGGER apply_document_duplicate_guard
    BEFORE INSERT OR UPDATE OF
        document_number,
        document_date,
        total_amount,
        provider_id,
        extraction_clean,
        status,
        deleted_at
    ON documents
    FOR EACH ROW
    EXECUTE FUNCTION apply_document_duplicate_guard_trigger_fn();

-- Backfill normalized values for existing rows.
UPDATE documents d
   SET normalized_supplier = normalize_invoice_supplier(
           COALESCE(
               NULLIF(trim(d.extraction_clean->>'supplier_name'), ''),
               p.name
           )
       ),
       normalized_document_number = build_document_dedupe_key(
           d.document_number,
           d.total_amount,
           d.document_date,
           COALESCE(
               NULLIF(trim(d.extraction_clean->>'supplier_name'), ''),
               p.name
           )
       )
  FROM providers p
 WHERE d.provider_id = p.id;

UPDATE documents d
   SET normalized_supplier = normalize_invoice_supplier(NULLIF(trim(d.extraction_clean->>'supplier_name'), '')),
       normalized_document_number = build_document_dedupe_key(
           d.document_number,
           d.total_amount,
           d.document_date,
           NULLIF(trim(d.extraction_clean->>'supplier_name'), '')
       )
 WHERE d.provider_id IS NULL;

-- Recompute duplicate flags for existing rows.
UPDATE documents
   SET is_duplicate = FALSE,
       duplicate_of = NULL;

WITH ranked AS (
    SELECT
        d.id,
        first_value(d.id) OVER (
            PARTITION BY d.company_id, d.normalized_document_number, d.normalized_supplier
            ORDER BY d.created_at ASC, d.id ASC
        ) AS canonical_id,
        row_number() OVER (
            PARTITION BY d.company_id, d.normalized_document_number, d.normalized_supplier
            ORDER BY d.created_at ASC, d.id ASC
        ) AS seq
    FROM documents d
    WHERE d.deleted_at IS NULL
      AND d.status = 'completed'
      AND d.normalized_document_number IS NOT NULL
      AND d.normalized_supplier IS NOT NULL
)
UPDATE documents d
   SET is_duplicate = (r.seq > 1),
       duplicate_of = CASE WHEN r.seq > 1 THEN r.canonical_id ELSE NULL END
  FROM ranked r
 WHERE d.id = r.id;

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
    COUNT(DISTINCT d.id) AS total_orders,
    COALESCE(SUM(d.total_amount), 0) AS total_spent,
    MAX(d.document_date) AS last_order_date,
    COALESCE(SUM(
        CASE WHEN d.document_date >= date_trunc('month', CURRENT_DATE)::date
             THEN d.total_amount ELSE 0 END
    ), 0) AS current_month_spent,
    COALESCE(SUM(
        CASE WHEN d.document_date >= (date_trunc('month', CURRENT_DATE) - INTERVAL '1 month')::date
              AND d.document_date < date_trunc('month', CURRENT_DATE)::date
             THEN d.total_amount ELSE 0 END
    ), 0) AS prior_month_spent
FROM providers p
LEFT JOIN documents d
    ON  d.provider_id = p.id
    AND d.status = 'completed'
    AND d.deleted_at IS NULL
    AND d.document_date IS NOT NULL
    AND d.total_amount IS NOT NULL
    AND COALESCE(d.is_duplicate, FALSE) = FALSE
GROUP BY p.id, p.company_id, p.name, p.category, p.is_active, p.created_at;

COMMIT;