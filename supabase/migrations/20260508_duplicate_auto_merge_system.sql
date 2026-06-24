-- ============================================================================
-- Migration 20260507: Duplicate Auto-Merge System with Confidence Scoring
-- ============================================================================

BEGIN;

ALTER TABLE documents
    ADD COLUMN IF NOT EXISTS merge_status TEXT NOT NULL DEFAULT 'none',
    ADD COLUMN IF NOT EXISTS merge_confidence DOUBLE PRECISION NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS merged_into UUID NULL REFERENCES documents(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS merge_group_id UUID NULL;

ALTER TABLE documents
    DROP CONSTRAINT IF EXISTS documents_merge_status_check;

ALTER TABLE documents
    ADD CONSTRAINT documents_merge_status_check
    CHECK (merge_status IN ('none', 'merged', 'review'));

CREATE INDEX IF NOT EXISTS idx_documents_merge_status
    ON documents (company_id, merge_status)
    WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_documents_merge_group
    ON documents (company_id, merge_group_id)
    WHERE merge_group_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_documents_supplier_recent
    ON documents (company_id, normalized_supplier, created_at DESC)
    WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_documents_recent
    ON documents (company_id, created_at DESC)
    WHERE deleted_at IS NULL;

CREATE TABLE IF NOT EXISTS document_merges (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    source_document_id UUID REFERENCES documents(id) ON DELETE SET NULL,
    target_document_id UUID REFERENCES documents(id) ON DELETE SET NULL,
    confidence DOUBLE PRECISION NOT NULL DEFAULT 0,
    method TEXT NOT NULL,
    reason TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT document_merges_method_check
      CHECK (method IN ('deterministic', 'heuristic', 'ai', 'manual'))
);

CREATE INDEX IF NOT EXISTS idx_document_merges_company_created
    ON document_merges (company_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_document_merges_source
    ON document_merges (company_id, source_document_id)
    WHERE source_document_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_document_merges_target
    ON document_merges (company_id, target_document_id)
    WHERE target_document_id IS NOT NULL;

ALTER TABLE document_merges ENABLE ROW LEVEL SECURITY;
ALTER TABLE document_merges FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS document_merges_isolation ON document_merges;
CREATE POLICY document_merges_isolation ON document_merges
  FOR ALL
  TO authenticated
  USING (company_id = ANY(public.user_company_ids()))
  WITH CHECK (company_id = ANY(public.user_company_ids()));

CREATE OR REPLACE FUNCTION public.merge_documents_for_company(
    p_company_id UUID,
    p_source_document_id UUID,
    p_target_document_id UUID,
    p_confidence DOUBLE PRECISION,
    p_method TEXT,
    p_reason TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
    v_source documents%ROWTYPE;
    v_target documents%ROWTYPE;
    v_group_id UUID;
BEGIN
    IF p_source_document_id = p_target_document_id THEN
        RAISE EXCEPTION 'Source and target documents must be different';
    END IF;

    SELECT *
      INTO v_source
      FROM documents
     WHERE id = p_source_document_id
       AND company_id = p_company_id
       AND deleted_at IS NULL
     FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Source document not found or unauthorized';
    END IF;

    SELECT *
      INTO v_target
      FROM documents
     WHERE id = p_target_document_id
       AND company_id = p_company_id
       AND deleted_at IS NULL
     FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Target document not found or unauthorized';
    END IF;

    v_group_id := COALESCE(v_target.merge_group_id, v_source.merge_group_id, gen_random_uuid());

    UPDATE documents
       SET merge_group_id = v_group_id,
           merge_status = CASE WHEN id = p_target_document_id THEN 'none' ELSE merge_status END,
           merge_confidence = CASE WHEN id = p_target_document_id THEN GREATEST(COALESCE(merge_confidence, 0), COALESCE(p_confidence, 0)) ELSE merge_confidence END
     WHERE id = p_target_document_id
       AND company_id = p_company_id;

    UPDATE document_items
       SET document_id = p_target_document_id
     WHERE company_id = p_company_id
       AND document_id = p_source_document_id;

    UPDATE expenses
       SET document_id = p_target_document_id,
           updated_at = NOW()
     WHERE company_id = p_company_id
       AND document_id = p_source_document_id;

    UPDATE documents
       SET is_duplicate = TRUE,
           duplicate_of = p_target_document_id,
           merge_status = 'merged',
           merge_confidence = GREATEST(COALESCE(p_confidence, 0), merge_confidence),
           merged_into = p_target_document_id,
           merge_group_id = v_group_id
     WHERE id = p_source_document_id
       AND company_id = p_company_id;

    INSERT INTO document_merges (
        company_id,
        source_document_id,
        target_document_id,
        confidence,
        method,
        reason
    ) VALUES (
        p_company_id,
        p_source_document_id,
        p_target_document_id,
        COALESCE(p_confidence, 0),
        p_method,
        p_reason
    );

    RETURN v_group_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.merge_documents_for_company(UUID, UUID, UUID, DOUBLE PRECISION, TEXT, TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION public.keep_document_separate(
    p_company_id UUID,
    p_document_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
BEGIN
    UPDATE documents
       SET merge_status = 'none',
           merge_confidence = 0,
           merged_into = NULL,
           merge_group_id = NULL
     WHERE id = p_document_id
       AND company_id = p_company_id
       AND deleted_at IS NULL;
END;
$$;

GRANT EXECUTE ON FUNCTION public.keep_document_separate(UUID, UUID) TO authenticated;

COMMIT;