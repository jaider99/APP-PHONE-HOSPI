-- ============================================================================
-- Migration 20260602: Review Center / Action Inbox
--
-- Adds a tenant-scoped operational inbox generated from existing document,
-- category, product-match, duplicate, supplier, and price anomaly signals.
-- ============================================================================

BEGIN;

CREATE TABLE IF NOT EXISTS public.review_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,

  review_type text NOT NULL,
  severity text NOT NULL DEFAULT 'medium',
  status text NOT NULL DEFAULT 'open',

  source_table text NOT NULL,
  source_id uuid NOT NULL,

  title text NOT NULL,
  description text,
  suggested_action text,

  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,

  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  resolved_at timestamptz,
  resolved_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,

  ignored_at timestamptz,
  ignored_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,

  CONSTRAINT review_items_status_check CHECK (
    status IN ('open', 'resolved', 'ignored', 'dismissed', 'retrying')
  ),

  CONSTRAINT review_items_severity_check CHECK (
    severity IN ('low', 'medium', 'high', 'critical')
  ),

  CONSTRAINT review_items_type_check CHECK (
    review_type IN (
      'low_confidence_field',
      'duplicate_document',
      'missing_category',
      'failed_extraction',
      'product_match_review',
      'supplier_match_review',
      'price_anomaly',
      'document_needs_review',
      'unknown_supplier',
      'unknown_document_type'
    )
  ),

  CONSTRAINT review_items_unique_source UNIQUE (
    company_id,
    review_type,
    source_table,
    source_id
  )
);

CREATE INDEX IF NOT EXISTS idx_review_items_company_status_created
  ON public.review_items(company_id, status, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_review_items_company_type_status
  ON public.review_items(company_id, review_type, status);

CREATE INDEX IF NOT EXISTS idx_review_items_company_severity_status
  ON public.review_items(company_id, severity, status);

CREATE INDEX IF NOT EXISTS idx_review_items_source
  ON public.review_items(company_id, source_table, source_id);

DROP TRIGGER IF EXISTS update_review_items_updated_at ON public.review_items;
CREATE TRIGGER update_review_items_updated_at
  BEFORE UPDATE ON public.review_items
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at_column();

ALTER TABLE public.review_items ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS review_items_select ON public.review_items;
CREATE POLICY review_items_select ON public.review_items
  FOR SELECT
  TO authenticated
  USING (company_id = ANY(public.user_company_ids()));

DROP POLICY IF EXISTS review_items_insert ON public.review_items;
CREATE POLICY review_items_insert ON public.review_items
  FOR INSERT
  TO authenticated
  WITH CHECK (company_id = ANY(public.user_company_ids()));

DROP POLICY IF EXISTS review_items_update ON public.review_items;
CREATE POLICY review_items_update ON public.review_items
  FOR UPDATE
  TO authenticated
  USING (company_id = ANY(public.user_company_ids()))
  WITH CHECK (company_id = ANY(public.user_company_ids()));

CREATE OR REPLACE FUNCTION public.sync_review_items_for_company(p_company_id uuid)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_open_count integer := 0;
BEGIN
  IF NOT (p_company_id = ANY(public.user_company_ids())) THEN
    RAISE EXCEPTION 'Access denied for company %', p_company_id USING ERRCODE = '42501';
  END IF;

  INSERT INTO public.review_items (
    company_id,
    review_type,
    severity,
    status,
    source_table,
    source_id,
    title,
    description,
    suggested_action,
    metadata
  )
  SELECT
    d.company_id,
    'failed_extraction',
    CASE WHEN d.status = 'failed' THEN 'high' ELSE 'medium' END,
    'open',
    'documents',
    d.id,
    CASE WHEN d.status = 'failed' THEN 'Document extraction failed' ELSE 'Document needs extraction review' END,
    NULLIF(d.notes, ''),
    'Retry extraction or edit the document manually',
    jsonb_build_object(
      'document_type', d.document_type,
      'status', d.status,
      'file_name', d.file_name
    )
  FROM public.documents d
  WHERE d.company_id = p_company_id
    AND d.deleted_at IS NULL
    AND d.status IN ('failed', 'flagged')
  ON CONFLICT (company_id, review_type, source_table, source_id)
  DO UPDATE SET
    severity = EXCLUDED.severity,
    status = CASE
      WHEN public.review_items.status IN ('ignored', 'dismissed') THEN public.review_items.status
      ELSE 'open'
    END,
    title = EXCLUDED.title,
    description = EXCLUDED.description,
    suggested_action = EXCLUDED.suggested_action,
    metadata = EXCLUDED.metadata,
    resolved_at = CASE
      WHEN public.review_items.status IN ('ignored', 'dismissed') THEN public.review_items.resolved_at
      ELSE NULL
    END,
    resolved_by = CASE
      WHEN public.review_items.status IN ('ignored', 'dismissed') THEN public.review_items.resolved_by
      ELSE NULL
    END,
    ignored_at = public.review_items.ignored_at,
    ignored_by = public.review_items.ignored_by,
    updated_at = now();

  INSERT INTO public.review_items (
    company_id, review_type, severity, status, source_table, source_id,
    title, description, suggested_action, metadata
  )
  SELECT
    d.company_id,
    'missing_category',
    CASE WHEN COALESCE(d.category_confidence, 1) < 0.6 THEN 'high' ELSE 'medium' END,
    'open',
    'documents',
    d.id,
    'Document is missing a category',
    CASE
      WHEN d.ai_category_id IS NOT NULL THEN 'AI suggested a category that still needs confirmation.'
      ELSE 'Assign a category so expenses and reporting stay accurate.'
    END,
    'Assign category',
    jsonb_build_object(
      'document_type', d.document_type,
      'ai_category_id', d.ai_category_id,
      'category_confidence', d.category_confidence,
      'total_amount', d.total_amount
    )
  FROM public.documents d
  WHERE d.company_id = p_company_id
    AND d.deleted_at IS NULL
    AND d.status = 'completed'
    AND d.category_id IS NULL
  ON CONFLICT (company_id, review_type, source_table, source_id)
  DO UPDATE SET
    severity = EXCLUDED.severity,
    status = CASE
      WHEN public.review_items.status IN ('ignored', 'dismissed') THEN public.review_items.status
      ELSE 'open'
    END,
    title = EXCLUDED.title,
    description = EXCLUDED.description,
    suggested_action = EXCLUDED.suggested_action,
    metadata = EXCLUDED.metadata,
    resolved_at = CASE
      WHEN public.review_items.status IN ('ignored', 'dismissed') THEN public.review_items.resolved_at
      ELSE NULL
    END,
    resolved_by = CASE
      WHEN public.review_items.status IN ('ignored', 'dismissed') THEN public.review_items.resolved_by
      ELSE NULL
    END,
    ignored_at = public.review_items.ignored_at,
    ignored_by = public.review_items.ignored_by,
    updated_at = now();

  INSERT INTO public.review_items (
    company_id, review_type, severity, status, source_table, source_id,
    title, description, suggested_action, metadata
  )
  SELECT
    d.company_id,
    'duplicate_document',
    'high',
    'open',
    'documents',
    d.id,
    'Possible duplicate document',
    'This document may already exist. Review it before deleting or merging anything.',
    'Review duplicate',
    jsonb_build_object(
      'duplicate_of', d.duplicate_of,
      'merge_status', d.merge_status,
      'merge_confidence', d.merge_confidence,
      'document_number', d.document_number,
      'supplier_name', d.supplier_name
    )
  FROM public.documents d
  WHERE d.company_id = p_company_id
    AND d.deleted_at IS NULL
    AND (d.is_duplicate = true OR d.merge_status = 'review')
  ON CONFLICT (company_id, review_type, source_table, source_id)
  DO UPDATE SET
    severity = EXCLUDED.severity,
    status = CASE
      WHEN public.review_items.status IN ('ignored', 'dismissed') THEN public.review_items.status
      ELSE 'open'
    END,
    title = EXCLUDED.title,
    description = EXCLUDED.description,
    suggested_action = EXCLUDED.suggested_action,
    metadata = EXCLUDED.metadata,
    resolved_at = CASE
      WHEN public.review_items.status IN ('ignored', 'dismissed') THEN public.review_items.resolved_at
      ELSE NULL
    END,
    resolved_by = CASE
      WHEN public.review_items.status IN ('ignored', 'dismissed') THEN public.review_items.resolved_by
      ELSE NULL
    END,
    ignored_at = public.review_items.ignored_at,
    ignored_by = public.review_items.ignored_by,
    updated_at = now();

  INSERT INTO public.review_items (
    company_id, review_type, severity, status, source_table, source_id,
    title, description, suggested_action, metadata
  )
  SELECT
    d.company_id,
    'unknown_document_type',
    'medium',
    'open',
    'documents',
    d.id,
    'Document type is unknown',
    'Confirm whether this is an invoice, delivery note, ticket, or another document type.',
    'Review fields',
    jsonb_build_object('status', d.status, 'file_name', d.file_name)
  FROM public.documents d
  WHERE d.company_id = p_company_id
    AND d.deleted_at IS NULL
    AND d.status <> 'processing'
    AND (d.document_type IS NULL OR d.document_type = 'unknown')
  ON CONFLICT (company_id, review_type, source_table, source_id)
  DO UPDATE SET
    severity = EXCLUDED.severity,
    status = CASE
      WHEN public.review_items.status IN ('ignored', 'dismissed') THEN public.review_items.status
      ELSE 'open'
    END,
    title = EXCLUDED.title,
    description = EXCLUDED.description,
    suggested_action = EXCLUDED.suggested_action,
    metadata = EXCLUDED.metadata,
    resolved_at = CASE
      WHEN public.review_items.status IN ('ignored', 'dismissed') THEN public.review_items.resolved_at
      ELSE NULL
    END,
    resolved_by = CASE
      WHEN public.review_items.status IN ('ignored', 'dismissed') THEN public.review_items.resolved_by
      ELSE NULL
    END,
    ignored_at = public.review_items.ignored_at,
    ignored_by = public.review_items.ignored_by,
    updated_at = now();

  INSERT INTO public.review_items (
    company_id, review_type, severity, status, source_table, source_id,
    title, description, suggested_action, metadata
  )
  SELECT
    d.company_id,
    'unknown_supplier',
    'medium',
    'open',
    'documents',
    d.id,
    'Supplier is not matched',
    'Match the detected supplier to a provider record or create a new provider.',
    'Match supplier',
    jsonb_build_object(
      'supplier_name', d.supplier_name,
      'document_type', d.document_type,
      'total_amount', d.total_amount
    )
  FROM public.documents d
  WHERE d.company_id = p_company_id
    AND d.deleted_at IS NULL
    AND d.status = 'completed'
    AND d.provider_id IS NULL
  ON CONFLICT (company_id, review_type, source_table, source_id)
  DO UPDATE SET
    severity = EXCLUDED.severity,
    status = CASE
      WHEN public.review_items.status IN ('ignored', 'dismissed') THEN public.review_items.status
      ELSE 'open'
    END,
    title = EXCLUDED.title,
    description = EXCLUDED.description,
    suggested_action = EXCLUDED.suggested_action,
    metadata = EXCLUDED.metadata,
    resolved_at = CASE
      WHEN public.review_items.status IN ('ignored', 'dismissed') THEN public.review_items.resolved_at
      ELSE NULL
    END,
    resolved_by = CASE
      WHEN public.review_items.status IN ('ignored', 'dismissed') THEN public.review_items.resolved_by
      ELSE NULL
    END,
    ignored_at = public.review_items.ignored_at,
    ignored_by = public.review_items.ignored_by,
    updated_at = now();

  INSERT INTO public.review_items (
    company_id, review_type, severity, status, source_table, source_id,
    title, description, suggested_action, metadata
  )
  SELECT
    d.company_id,
    'low_confidence_field',
    'medium',
    'open',
    'documents',
    d.id,
    'Document total is missing',
    'Review extracted fields and add the missing total amount.',
    'Review fields',
    jsonb_build_object('document_type', d.document_type, 'status', d.status)
  FROM public.documents d
  WHERE d.company_id = p_company_id
    AND d.deleted_at IS NULL
    AND d.status = 'completed'
    AND d.total_amount IS NULL
  ON CONFLICT (company_id, review_type, source_table, source_id)
  DO UPDATE SET
    severity = EXCLUDED.severity,
    status = CASE
      WHEN public.review_items.status IN ('ignored', 'dismissed') THEN public.review_items.status
      ELSE 'open'
    END,
    title = EXCLUDED.title,
    description = EXCLUDED.description,
    suggested_action = EXCLUDED.suggested_action,
    metadata = EXCLUDED.metadata,
    resolved_at = CASE
      WHEN public.review_items.status IN ('ignored', 'dismissed') THEN public.review_items.resolved_at
      ELSE NULL
    END,
    resolved_by = CASE
      WHEN public.review_items.status IN ('ignored', 'dismissed') THEN public.review_items.resolved_by
      ELSE NULL
    END,
    ignored_at = public.review_items.ignored_at,
    ignored_by = public.review_items.ignored_by,
    updated_at = now();

  INSERT INTO public.review_items (
    company_id, review_type, severity, status, source_table, source_id,
    title, description, suggested_action, metadata
  )
  SELECT
    i.company_id,
    'product_match_review',
    CASE WHEN i.product_id IS NULL THEN 'high' ELSE 'medium' END,
    'open',
    'document_items',
    i.id,
    CASE WHEN i.product_id IS NULL THEN 'Line item needs product match' ELSE 'Confirm product match' END,
    COALESCE(NULLIF(i.description, ''), 'A document line item needs product review.'),
    'Match product',
    jsonb_build_object(
      'document_id', i.document_id,
      'description', i.description,
      'confidence_score', i.confidence_score,
      'matched_automatically', i.matched_automatically
    )
  FROM public.document_items i
  JOIN public.documents d ON d.id = i.document_id AND d.company_id = i.company_id
  WHERE i.company_id = p_company_id
    AND d.deleted_at IS NULL
    AND d.status = 'completed'
    AND (i.product_id IS NULL OR COALESCE(i.confidence_score, 100) < 75)
  ON CONFLICT (company_id, review_type, source_table, source_id)
  DO UPDATE SET
    severity = EXCLUDED.severity,
    status = CASE
      WHEN public.review_items.status IN ('ignored', 'dismissed') THEN public.review_items.status
      ELSE 'open'
    END,
    title = EXCLUDED.title,
    description = EXCLUDED.description,
    suggested_action = EXCLUDED.suggested_action,
    metadata = EXCLUDED.metadata,
    resolved_at = CASE
      WHEN public.review_items.status IN ('ignored', 'dismissed') THEN public.review_items.resolved_at
      ELSE NULL
    END,
    resolved_by = CASE
      WHEN public.review_items.status IN ('ignored', 'dismissed') THEN public.review_items.resolved_by
      ELSE NULL
    END,
    ignored_at = public.review_items.ignored_at,
    ignored_by = public.review_items.ignored_by,
    updated_at = now();

  INSERT INTO public.review_items (
    company_id, review_type, severity, status, source_table, source_id,
    title, description, suggested_action, metadata
  )
  SELECT
    a.company_id,
    'price_anomaly',
    a.severity::text,
    'open',
    'price_anomalies',
    a.id,
    'Price anomaly detected',
    COALESCE(a.explanation, 'A product price is outside the usual range.'),
    'Review price',
    jsonb_build_object(
      'product_id', a.product_id,
      'supplier_id', a.supplier_id,
      'document_id', a.document_id,
      'current_price', a.current_price,
      'expected_price', a.expected_price,
      'deviation_percent', a.deviation_percent,
      'resolution_status', a.resolution_status
    )
  FROM public.price_anomalies a
  WHERE a.company_id = p_company_id
    AND a.resolved = false
    AND a.resolution_status = 'open'
  ON CONFLICT (company_id, review_type, source_table, source_id)
  DO UPDATE SET
    severity = EXCLUDED.severity,
    status = CASE
      WHEN public.review_items.status IN ('ignored', 'dismissed') THEN public.review_items.status
      ELSE 'open'
    END,
    title = EXCLUDED.title,
    description = EXCLUDED.description,
    suggested_action = EXCLUDED.suggested_action,
    metadata = EXCLUDED.metadata,
    resolved_at = CASE
      WHEN public.review_items.status IN ('ignored', 'dismissed') THEN public.review_items.resolved_at
      ELSE NULL
    END,
    resolved_by = CASE
      WHEN public.review_items.status IN ('ignored', 'dismissed') THEN public.review_items.resolved_by
      ELSE NULL
    END,
    ignored_at = public.review_items.ignored_at,
    ignored_by = public.review_items.ignored_by,
    updated_at = now();

  UPDATE public.review_items ri
  SET status = 'resolved', resolved_at = now(), updated_at = now()
  WHERE ri.company_id = p_company_id
    AND ri.status = 'open'
    AND ri.review_type = 'failed_extraction'
    AND ri.source_table = 'documents'
    AND NOT EXISTS (
      SELECT 1 FROM public.documents d
      WHERE d.id = ri.source_id
        AND d.company_id = ri.company_id
        AND d.deleted_at IS NULL
        AND d.status IN ('failed', 'flagged')
    );

  UPDATE public.review_items ri
  SET status = 'resolved', resolved_at = now(), updated_at = now()
  WHERE ri.company_id = p_company_id
    AND ri.status = 'open'
    AND ri.review_type = 'missing_category'
    AND ri.source_table = 'documents'
    AND NOT EXISTS (
      SELECT 1 FROM public.documents d
      WHERE d.id = ri.source_id
        AND d.company_id = ri.company_id
        AND d.deleted_at IS NULL
        AND d.status = 'completed'
        AND d.category_id IS NULL
    );

  UPDATE public.review_items ri
  SET status = 'resolved', resolved_at = now(), updated_at = now()
  WHERE ri.company_id = p_company_id
    AND ri.status = 'open'
    AND ri.review_type = 'duplicate_document'
    AND ri.source_table = 'documents'
    AND NOT EXISTS (
      SELECT 1 FROM public.documents d
      WHERE d.id = ri.source_id
        AND d.company_id = ri.company_id
        AND d.deleted_at IS NULL
        AND (d.is_duplicate = true OR d.merge_status = 'review')
    );

  UPDATE public.review_items ri
  SET status = 'resolved', resolved_at = now(), updated_at = now()
  WHERE ri.company_id = p_company_id
    AND ri.status = 'open'
    AND ri.review_type = 'unknown_document_type'
    AND ri.source_table = 'documents'
    AND NOT EXISTS (
      SELECT 1 FROM public.documents d
      WHERE d.id = ri.source_id
        AND d.company_id = ri.company_id
        AND d.deleted_at IS NULL
        AND d.status <> 'processing'
        AND (d.document_type IS NULL OR d.document_type = 'unknown')
    );

  UPDATE public.review_items ri
  SET status = 'resolved', resolved_at = now(), updated_at = now()
  WHERE ri.company_id = p_company_id
    AND ri.status = 'open'
    AND ri.review_type = 'unknown_supplier'
    AND ri.source_table = 'documents'
    AND NOT EXISTS (
      SELECT 1 FROM public.documents d
      WHERE d.id = ri.source_id
        AND d.company_id = ri.company_id
        AND d.deleted_at IS NULL
        AND d.status = 'completed'
        AND d.provider_id IS NULL
    );

  UPDATE public.review_items ri
  SET status = 'resolved', resolved_at = now(), updated_at = now()
  WHERE ri.company_id = p_company_id
    AND ri.status = 'open'
    AND ri.review_type = 'low_confidence_field'
    AND ri.source_table = 'documents'
    AND NOT EXISTS (
      SELECT 1 FROM public.documents d
      WHERE d.id = ri.source_id
        AND d.company_id = ri.company_id
        AND d.deleted_at IS NULL
        AND d.status = 'completed'
        AND d.total_amount IS NULL
    );

  UPDATE public.review_items ri
  SET status = 'resolved', resolved_at = now(), updated_at = now()
  WHERE ri.company_id = p_company_id
    AND ri.status = 'open'
    AND ri.review_type = 'product_match_review'
    AND ri.source_table = 'document_items'
    AND NOT EXISTS (
      SELECT 1 FROM public.document_items i
      JOIN public.documents d ON d.id = i.document_id AND d.company_id = i.company_id
      WHERE i.id = ri.source_id
        AND i.company_id = ri.company_id
        AND d.deleted_at IS NULL
        AND d.status = 'completed'
        AND (i.product_id IS NULL OR COALESCE(i.confidence_score, 100) < 75)
    );

  UPDATE public.review_items ri
  SET status = 'resolved', resolved_at = now(), updated_at = now()
  WHERE ri.company_id = p_company_id
    AND ri.status = 'open'
    AND ri.review_type = 'price_anomaly'
    AND ri.source_table = 'price_anomalies'
    AND NOT EXISTS (
      SELECT 1 FROM public.price_anomalies a
      WHERE a.id = ri.source_id
        AND a.company_id = ri.company_id
        AND a.resolved = false
        AND a.resolution_status = 'open'
    );

  SELECT count(*) INTO v_open_count
  FROM public.review_items
  WHERE company_id = p_company_id
    AND status = 'open';

  RETURN v_open_count;
END;
$$;

CREATE OR REPLACE FUNCTION public.sync_review_items_for_document(p_document_id uuid)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_company_id uuid;
BEGIN
  SELECT company_id INTO v_company_id
  FROM public.documents
  WHERE id = p_document_id
    AND deleted_at IS NULL;

  IF v_company_id IS NULL THEN
    RETURN 0;
  END IF;

  IF NOT (v_company_id = ANY(public.user_company_ids())) THEN
    RAISE EXCEPTION 'Access denied for document %', p_document_id USING ERRCODE = '42501';
  END IF;

  RETURN public.sync_review_items_for_company(v_company_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.resolve_review_item(
  p_review_item_id uuid,
  p_action text DEFAULT 'resolved',
  p_payload jsonb DEFAULT '{}'::jsonb
)
RETURNS public.review_items
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_item public.review_items;
  v_normalized_action text := lower(trim(COALESCE(p_action, 'resolved')));
BEGIN
  SELECT * INTO v_item
  FROM public.review_items
  WHERE id = p_review_item_id
    AND company_id = ANY(public.user_company_ids());

  IF v_item.id IS NULL THEN
    RAISE EXCEPTION 'Review item not found or access denied' USING ERRCODE = '42501';
  END IF;

  IF v_normalized_action IN ('resolve', 'resolved', 'mark_resolved') THEN
    UPDATE public.review_items
    SET status = 'resolved',
        resolved_at = now(),
        resolved_by = auth.uid(),
        ignored_at = NULL,
        ignored_by = NULL,
        metadata = metadata || jsonb_build_object('resolution_payload', p_payload),
        updated_at = now()
    WHERE id = p_review_item_id
    RETURNING * INTO v_item;
  ELSIF v_normalized_action IN ('ignore', 'ignored') THEN
    UPDATE public.review_items
    SET status = 'ignored',
        ignored_at = now(),
        ignored_by = auth.uid(),
        metadata = metadata || jsonb_build_object('ignore_payload', p_payload),
        updated_at = now()
    WHERE id = p_review_item_id
    RETURNING * INTO v_item;
  ELSIF v_normalized_action IN ('dismiss', 'dismissed') THEN
    UPDATE public.review_items
    SET status = 'dismissed',
        metadata = metadata || jsonb_build_object('dismiss_payload', p_payload),
        updated_at = now()
    WHERE id = p_review_item_id
    RETURNING * INTO v_item;
  ELSIF v_normalized_action IN ('retry', 'retrying') THEN
    UPDATE public.review_items
    SET status = 'retrying',
        metadata = metadata || jsonb_build_object('retry_payload', p_payload),
        updated_at = now()
    WHERE id = p_review_item_id
    RETURNING * INTO v_item;
  ELSE
    RAISE EXCEPTION 'Unsupported review item action: %', p_action USING ERRCODE = '22023';
  END IF;

  PERFORM public.record_security_audit_event(
    v_item.company_id,
    'review_item.' || v_normalized_action,
    'review_item',
    v_item.id,
    'success',
    NULL,
    jsonb_build_object(
      'review_type', v_item.review_type,
      'source_table', v_item.source_table,
      'source_id', v_item.source_id,
      'status', v_item.status,
      'payload', p_payload
    )
  );

  RETURN v_item;
END;
$$;

GRANT SELECT, INSERT, UPDATE ON public.review_items TO authenticated;
GRANT EXECUTE ON FUNCTION public.sync_review_items_for_company(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.sync_review_items_for_document(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.resolve_review_item(uuid, text, jsonb) TO authenticated;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
    IF NOT EXISTS (
      SELECT 1
      FROM pg_publication_tables
      WHERE pubname = 'supabase_realtime'
        AND schemaname = 'public'
        AND tablename = 'review_items'
    ) THEN
      ALTER PUBLICATION supabase_realtime ADD TABLE public.review_items;
    END IF;
  END IF;
END $$;

COMMIT;
