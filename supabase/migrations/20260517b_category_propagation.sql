-- ============================================================================
-- Migration 20260517b: Category ↔ Supplier propagation
--
-- Problem: when a user sets a category on one document from supplier X, all
-- other documents from the same supplier remain uncategorized.
--
-- Fix:
--   1) sync_provider_category_trigger_fn — AFTER UPDATE on documents; fires
--      when category_id or provider_id changes.  Propagates a confirmed
--      category to every uncategorized sibling from the same provider.
--   2) backfill_provider_categories() — one-shot backfill RPC that applies
--      the same logic to all existing completed documents.
--   3) Calls backfill at migration time to fix data right now.
--
-- Safety guarantees:
--   - Only touches documents WHERE category_id IS NULL  (never overwrites)
--   - Always scoped by company_id  (no cross-tenant leakage)
--   - Trigger is re-entrant safe  (second-level calls are always no-ops)
-- ============================================================================

BEGIN;

-- ============================================================================
-- 1) TRIGGER FUNCTION
-- ============================================================================

CREATE OR REPLACE FUNCTION sync_provider_category_trigger_fn()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_category UUID;
BEGIN
    -- Nothing to do without a resolved provider
    IF NEW.provider_id IS NULL THEN
        RETURN NEW;
    END IF;

    -- ── Determine which category to propagate ───────────────────────────

    IF NEW.category_id IS NOT NULL THEN
        -- Case A: this document already has a category (set at upload or by
        -- user edit) — push it to uncategorized siblings.
        v_category := NEW.category_id;

    ELSIF OLD.provider_id IS DISTINCT FROM NEW.provider_id THEN
        -- Case B: provider was just resolved (NULL → id).  The document
        -- itself has no category yet — pull from the most recently
        -- categorized sibling, if any.
        SELECT d.category_id
          INTO v_category
          FROM documents d
         WHERE d.company_id  = NEW.company_id
           AND d.provider_id = NEW.provider_id
           AND d.category_id IS NOT NULL
           AND d.id          <> NEW.id
           AND d.deleted_at  IS NULL
         ORDER BY d.created_at DESC
         LIMIT 1;
    END IF;

    IF v_category IS NULL THEN
        RETURN NEW;
    END IF;

    -- ── Propagate to all uncategorized documents from this provider ──────

    UPDATE documents
       SET category_id = v_category
     WHERE company_id  = NEW.company_id
       AND provider_id = NEW.provider_id
       AND category_id IS NULL
       AND deleted_at  IS NULL;
    -- (This UPDATE includes NEW.id itself when v_category came from siblings.)

    -- ── Propagate to linked expenses ─────────────────────────────────────
    -- expenses.document_id → documents.id

    UPDATE expenses e
       SET category_id = v_category
      FROM documents d
     WHERE d.id          = e.document_id
       AND d.company_id  = NEW.company_id
       AND d.provider_id = NEW.provider_id
       AND e.category_id IS NULL;

    RETURN NEW;
END;
$$;

-- ============================================================================
-- 2) ATTACH TRIGGER
--    Fires AFTER UPDATE when either category_id or provider_id changes.
--    • category_id changes: user set/changed a category → push to siblings
--    • provider_id changes: auto_resolve_supplier just resolved the provider
--      → pull category from existing siblings (if any)
-- ============================================================================

DROP TRIGGER IF EXISTS sync_provider_category ON documents;
CREATE TRIGGER sync_provider_category
    AFTER UPDATE OF category_id, provider_id ON documents
    FOR EACH ROW
    EXECUTE FUNCTION sync_provider_category_trigger_fn();

-- ============================================================================
-- 3) BACKFILL RPC
--    Applies the same propagation logic to all already-completed documents.
--    Can be called again any time to re-sync (idempotent).
--    Callable from Flutter: supabase.rpc('backfill_provider_categories')
-- ============================================================================

CREATE OR REPLACE FUNCTION backfill_provider_categories(
    p_company_id UUID DEFAULT NULL
)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_total INTEGER := 0;
    v_rows  INTEGER;
    v_resolved_company_id UUID;
BEGIN
    -- When called by an authenticated user, resolve and verify the company.
    -- Skip the check when running as the migration/admin role.
    IF current_user NOT IN ('postgres', 'supabase_admin') THEN
        -- Require an explicit company_id from authenticated callers.
        IF p_company_id IS NULL THEN
            RAISE EXCEPTION 'company_id is required';
        END IF;
        -- Verify the caller belongs to this company.
        IF NOT (p_company_id = ANY(public.user_company_ids())) THEN
            RAISE EXCEPTION 'Unauthorized';
        END IF;
    END IF;

    v_resolved_company_id := p_company_id;

    -- Step 1: for each (company, provider) pair that has at least one
    -- document with a confirmed category, apply that category (most
    -- recently set) to all other documents from the same provider that
    -- have no category yet.

    WITH confirmed AS (
        -- Most recently confirmed category per company+provider
        SELECT DISTINCT ON (company_id, provider_id)
               company_id,
               provider_id,
               category_id
          FROM documents
         WHERE (v_resolved_company_id IS NULL OR company_id = v_resolved_company_id)
           AND provider_id  IS NOT NULL
           AND category_id  IS NOT NULL
           AND deleted_at   IS NULL
         ORDER BY company_id, provider_id, created_at DESC
    )
    UPDATE documents d
       SET category_id = c.category_id
      FROM confirmed c
     WHERE d.company_id  = c.company_id
       AND d.provider_id = c.provider_id
       AND d.category_id IS NULL
       AND d.deleted_at  IS NULL;

    GET DIAGNOSTICS v_rows = ROW_COUNT;
    v_total := v_total + v_rows;

    -- Step 2: propagate into linked expenses as well.

    UPDATE expenses e
       SET category_id = d.category_id
      FROM documents d
     WHERE d.id          = e.document_id
       AND (v_resolved_company_id IS NULL OR d.company_id = v_resolved_company_id)
       AND d.provider_id IS NOT NULL
       AND d.category_id IS NOT NULL
       AND e.category_id IS NULL;

    GET DIAGNOSTICS v_rows = ROW_COUNT;
    v_total := v_total + v_rows;

    RETURN v_total;
END;
$$;

GRANT EXECUTE ON FUNCTION backfill_provider_categories(UUID) TO authenticated;

-- ============================================================================
-- 4) RUN BACKFILL NOW — fixes all existing documents immediately
-- ============================================================================

DO $$
DECLARE
    v_count INTEGER;
BEGIN
    SELECT backfill_provider_categories() INTO v_count;
    RAISE NOTICE 'backfill_provider_categories: updated % rows', v_count;
END;
$$;

COMMIT;
