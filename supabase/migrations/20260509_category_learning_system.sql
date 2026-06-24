-- ============================================================================
-- Migration 20260509: Self-learning expense categories per company
--
-- Adds:
--   1) category metadata columns on documents
--   2) tenant-scoped category_learning table
--   3) correction and accuracy RPCs guarded by company membership
-- ============================================================================

BEGIN;

ALTER TABLE categories
  ADD COLUMN IF NOT EXISTS color text;

UPDATE categories
   SET color = COALESCE(color, color_hex)
 WHERE color IS NULL
   AND color_hex IS NOT NULL;

ALTER TABLE documents
  ADD COLUMN IF NOT EXISTS category_id uuid REFERENCES categories(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS ai_category_id uuid REFERENCES categories(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS category_confidence double precision;

CREATE INDEX IF NOT EXISTS idx_documents_company_category
  ON documents (company_id, category_id)
  WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_documents_company_ai_category
  ON documents (company_id, ai_category_id)
  WHERE deleted_at IS NULL;

CREATE TABLE IF NOT EXISTS category_learning (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  document_id uuid REFERENCES documents(id) ON DELETE SET NULL,
  supplier_name text,
  normalized_supplier text,
  keywords text[] NOT NULL DEFAULT '{}',
  predicted_category_id uuid REFERENCES categories(id) ON DELETE SET NULL,
  confirmed_category_id uuid REFERENCES categories(id) ON DELETE CASCADE,
  confidence_score double precision NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT category_learning_confidence_range
    CHECK (confidence_score >= 0 AND confidence_score <= 1)
);

CREATE INDEX IF NOT EXISTS idx_category_learning_company_created
  ON category_learning (company_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_category_learning_supplier
  ON category_learning (company_id, normalized_supplier, created_at DESC)
  WHERE normalized_supplier IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_category_learning_confirmed
  ON category_learning (company_id, confirmed_category_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_category_learning_predicted
  ON category_learning (company_id, predicted_category_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_category_learning_keywords_gin
  ON category_learning USING gin (keywords);

ALTER TABLE category_learning ENABLE ROW LEVEL SECURITY;
ALTER TABLE category_learning FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS category_learning_isolation ON category_learning;
CREATE POLICY category_learning_isolation ON category_learning
  FOR ALL
  TO authenticated
  USING (company_id = ANY(public.user_company_ids()))
  WITH CHECK (company_id = ANY(public.user_company_ids()));

CREATE OR REPLACE FUNCTION public.normalize_category_learning_supplier(p_raw text)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT NULLIF(regexp_replace(lower(trim(COALESCE(p_raw, ''))), '\s+', ' ', 'g'), '');
$$;

CREATE OR REPLACE FUNCTION public.record_category_learning(
  p_document_id uuid,
  p_supplier_name text DEFAULT NULL,
  p_keywords text[] DEFAULT '{}',
  p_predicted_category_id uuid DEFAULT NULL,
  p_confirmed_category_id uuid DEFAULT NULL,
  p_confidence_score double precision DEFAULT 0.2
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company_id uuid;
  v_learning_id uuid;
BEGIN
  SELECT d.company_id
    INTO v_company_id
    FROM documents d
   WHERE d.id = p_document_id
     AND d.deleted_at IS NULL
     AND d.company_id = ANY(public.user_company_ids());

  IF v_company_id IS NULL THEN
    RAISE EXCEPTION 'Document not found or unauthorized';
  END IF;

  INSERT INTO category_learning (
    company_id,
    document_id,
    supplier_name,
    normalized_supplier,
    keywords,
    predicted_category_id,
    confirmed_category_id,
    confidence_score
  )
  VALUES (
    v_company_id,
    p_document_id,
    NULLIF(trim(p_supplier_name), ''),
    public.normalize_category_learning_supplier(p_supplier_name),
    COALESCE(
      ARRAY(
        SELECT DISTINCT lower(trim(keyword_value))
          FROM unnest(COALESCE(p_keywords, '{}')) AS keyword_value
         WHERE NULLIF(trim(keyword_value), '') IS NOT NULL
      ),
      '{}'
    ),
    p_predicted_category_id,
    p_confirmed_category_id,
    GREATEST(0, LEAST(COALESCE(p_confidence_score, 0.2), 1))
  )
  RETURNING id INTO v_learning_id;

  RETURN v_learning_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.record_category_learning(uuid, text, text[], uuid, uuid, double precision) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_category_accuracy(p_company_id uuid)
RETURNS TABLE (
  total_predictions bigint,
  correct_predictions bigint,
  accuracy double precision
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    COUNT(*)::bigint AS total_predictions,
    COUNT(*) FILTER (
      WHERE predicted_category_id IS NOT NULL
        AND predicted_category_id = confirmed_category_id
    )::bigint AS correct_predictions,
    COALESCE(
      COUNT(*) FILTER (
        WHERE predicted_category_id IS NOT NULL
          AND predicted_category_id = confirmed_category_id
      )::double precision / NULLIF(COUNT(*)::double precision, 0),
      0
    ) AS accuracy
  FROM category_learning
  WHERE company_id = p_company_id
    AND p_company_id = ANY(public.user_company_ids());
$$;

GRANT EXECUTE ON FUNCTION public.get_category_accuracy(uuid) TO authenticated;

COMMIT;