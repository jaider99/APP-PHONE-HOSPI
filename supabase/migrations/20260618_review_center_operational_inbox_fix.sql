-- ============================================================================
-- Migration 20260618: Review Center operational inbox fix
--
-- Repairs schema drift in sync_review_items_for_company and extends the inbox
-- to real sales/POS operational signals without weakening tenant isolation.
-- ============================================================================

BEGIN;

ALTER TABLE public.review_items
  DROP CONSTRAINT IF EXISTS review_items_type_check;

ALTER TABLE public.review_items
  ADD CONSTRAINT review_items_type_check CHECK (
    review_type IN (
      'low_confidence_field',
      'duplicate_document',
      'missing_category',
      'failed_extraction',
      'product_match_review',
      'supplier_match_review',
      'price_anomaly',
      'price_variation',
      'baseline_review',
      'document_needs_review',
      'unknown_supplier',
      'unknown_document_type',
      'failed_sales_import',
      'low_confidence_sales_report',
      'missing_sales_period',
      'pos_connection_issue'
    )
  );

ALTER TABLE public.review_items FORCE ROW LEVEL SECURITY;

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
      'normalized_supplier', d.normalized_supplier
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
      'supplier_name', COALESCE(d.normalized_supplier, d.extraction_clean->>'supplier_name', d.extraction_raw->>'supplier_name'),
      'provider_id', d.provider_id,
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
    AND (
      i.product_id IS NULL
      OR (
        i.confidence_score IS NOT NULL
        AND CASE
          WHEN i.confidence_score <= 1 THEN i.confidence_score < 0.75
          ELSE i.confidence_score < 75
        END
      )
    )
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
      'document_item_id', a.document_item_id,
      'product_price_id', a.product_price_id,
      'anomaly_type', a.anomaly_type,
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

  INSERT INTO public.review_items (
    company_id, review_type, severity, status, source_table, source_id,
    title, description, suggested_action, metadata
  )
  SELECT
    s.company_id,
    'failed_sales_import',
    'high',
    'open',
    'sales_imports',
    s.id,
    'Sales import failed',
    COALESCE(NULLIF(s.notes, ''), 'Sales import processing could not be completed.'),
    'Review sales import',
    jsonb_build_object(
      'source_type', s.source_type,
      'source_name', s.source_name,
      'provider_key', s.provider_key,
      'file_path', s.file_path,
      'status', s.status
    )
  FROM public.sales_imports s
  WHERE s.company_id = p_company_id
    AND lower(COALESCE(s.status, '')) = 'failed'
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
    s.company_id,
    'low_confidence_sales_report',
    'medium',
    'open',
    'sales_imports',
    s.id,
    'Sales report needs review',
    COALESCE(NULLIF(s.notes, ''), 'The imported sales report needs manual validation.'),
    'Review sales report',
    jsonb_build_object(
      'source_type', s.source_type,
      'source_name', s.source_name,
      'provider_key', s.provider_key,
      'status', s.status
    )
  FROM public.sales_imports s
  WHERE s.company_id = p_company_id
    AND lower(COALESCE(s.status, '')) IN ('flagged', 'needs_review', 'review', 'low_confidence')
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
    s.company_id,
    'missing_sales_period',
    'medium',
    'open',
    'sales_imports',
    s.id,
    'Sales import is missing its period',
    'Add the reporting period so sales analytics can use this import correctly.',
    'Set sales period',
    jsonb_build_object(
      'source_type', s.source_type,
      'source_name', s.source_name,
      'provider_key', s.provider_key,
      'period_start', s.period_start,
      'period_end', s.period_end,
      'status', s.status
    )
  FROM public.sales_imports s
  WHERE s.company_id = p_company_id
    AND lower(COALESCE(s.status, '')) IN ('completed', 'imported', 'processed', 'success', 'succeeded')
    AND (s.period_start IS NULL OR s.period_end IS NULL)
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
    c.company_id,
    'pos_connection_issue',
    'high',
    'open',
    'pos_connections',
    c.id,
    'POS connection needs attention',
    'Reconnect or update credentials so sales imports keep flowing.',
    'Review POS connection',
    jsonb_build_object(
      'provider', c.provider,
      'provider_name', c.provider_name,
      'provider_key', c.provider_key,
      'status', c.status,
      'sync_status', c.sync_status,
      'credentials_status', c.credentials_status,
      'connection_mode', c.connection_mode
    )
  FROM public.pos_connections c
  WHERE c.company_id = p_company_id
    AND c.deleted_at IS NULL
    AND (
      lower(COALESCE(c.status, '')) IN ('error', 'failed', 'disconnected', 'expired', 'requires_action', 'setup_required')
      OR lower(COALESCE(c.sync_status, '')) IN ('error', 'failed', 'stale', 'needs_attention')
      OR lower(COALESCE(c.credentials_status, '')) IN ('error', 'failed', 'expired', 'missing', 'invalid', 'requires_action')
    )
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
    r.company_id,
    'pos_connection_issue',
    CASE WHEN lower(COALESCE(r.status, '')) IN ('error', 'failed') THEN 'high' ELSE 'medium' END,
    'open',
    'pos_connection_requests',
    r.id,
    'POS setup request needs follow-up',
    'Complete the requested POS setup so this connection can start importing sales.',
    'Complete POS setup',
    jsonb_build_object(
      'provider_name', r.provider_name,
      'provider_key', r.provider_key,
      'country_code', r.country_code,
      'status', r.status,
      'metadata', r.metadata
    )
  FROM public.pos_connection_requests r
  WHERE r.company_id = p_company_id
    AND lower(COALESCE(r.status, '')) IN ('requested', 'pending', 'error', 'failed')
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
        AND (
          i.product_id IS NULL
          OR (
            i.confidence_score IS NOT NULL
            AND CASE
              WHEN i.confidence_score <= 1 THEN i.confidence_score < 0.75
              ELSE i.confidence_score < 75
            END
          )
        )
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

  UPDATE public.review_items ri
  SET status = 'resolved', resolved_at = now(), updated_at = now()
  WHERE ri.company_id = p_company_id
    AND ri.status = 'open'
    AND ri.review_type = 'failed_sales_import'
    AND ri.source_table = 'sales_imports'
    AND NOT EXISTS (
      SELECT 1 FROM public.sales_imports s
      WHERE s.id = ri.source_id
        AND s.company_id = ri.company_id
        AND lower(COALESCE(s.status, '')) = 'failed'
    );

  UPDATE public.review_items ri
  SET status = 'resolved', resolved_at = now(), updated_at = now()
  WHERE ri.company_id = p_company_id
    AND ri.status = 'open'
    AND ri.review_type = 'low_confidence_sales_report'
    AND ri.source_table = 'sales_imports'
    AND NOT EXISTS (
      SELECT 1 FROM public.sales_imports s
      WHERE s.id = ri.source_id
        AND s.company_id = ri.company_id
        AND lower(COALESCE(s.status, '')) IN ('flagged', 'needs_review', 'review', 'low_confidence')
    );

  UPDATE public.review_items ri
  SET status = 'resolved', resolved_at = now(), updated_at = now()
  WHERE ri.company_id = p_company_id
    AND ri.status = 'open'
    AND ri.review_type = 'missing_sales_period'
    AND ri.source_table = 'sales_imports'
    AND NOT EXISTS (
      SELECT 1 FROM public.sales_imports s
      WHERE s.id = ri.source_id
        AND s.company_id = ri.company_id
        AND lower(COALESCE(s.status, '')) IN ('completed', 'imported', 'processed', 'success', 'succeeded')
        AND (s.period_start IS NULL OR s.period_end IS NULL)
    );

  UPDATE public.review_items ri
  SET status = 'resolved', resolved_at = now(), updated_at = now()
  WHERE ri.company_id = p_company_id
    AND ri.status = 'open'
    AND ri.review_type = 'pos_connection_issue'
    AND ri.source_table = 'pos_connections'
    AND NOT EXISTS (
      SELECT 1 FROM public.pos_connections c
      WHERE c.id = ri.source_id
        AND c.company_id = ri.company_id
        AND c.deleted_at IS NULL
        AND (
          lower(COALESCE(c.status, '')) IN ('error', 'failed', 'disconnected', 'expired', 'requires_action', 'setup_required')
          OR lower(COALESCE(c.sync_status, '')) IN ('error', 'failed', 'stale', 'needs_attention')
          OR lower(COALESCE(c.credentials_status, '')) IN ('error', 'failed', 'expired', 'missing', 'invalid', 'requires_action')
        )
    );

  UPDATE public.review_items ri
  SET status = 'resolved', resolved_at = now(), updated_at = now()
  WHERE ri.company_id = p_company_id
    AND ri.status = 'open'
    AND ri.review_type = 'pos_connection_issue'
    AND ri.source_table = 'pos_connection_requests'
    AND NOT EXISTS (
      SELECT 1 FROM public.pos_connection_requests r
      WHERE r.id = ri.source_id
        AND r.company_id = ri.company_id
        AND lower(COALESCE(r.status, '')) IN ('requested', 'pending', 'error', 'failed')
    );

  SELECT count(*) INTO v_open_count
  FROM public.review_items
  WHERE company_id = p_company_id
    AND status = 'open';

  RETURN v_open_count;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.sync_review_items_for_company(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.sync_review_items_for_company(uuid) TO authenticated;

COMMIT;