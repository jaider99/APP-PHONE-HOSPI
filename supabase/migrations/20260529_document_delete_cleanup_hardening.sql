-- ============================================================================
-- Migration 20260529: Harden tenant-scoped document deletion cleanup
-- ============================================================================

CREATE OR REPLACE FUNCTION public.delete_document_cascade(
  p_document_id uuid,
  p_company_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_document_id uuid;
BEGIN
  SELECT d.id
    INTO v_document_id
  FROM public.documents d
  WHERE d.id = p_document_id
    AND d.company_id = p_company_id
    AND d.deleted_at IS NULL
  FOR UPDATE;

  IF v_document_id IS NULL THEN
    PERFORM public.record_security_audit_event(
      p_company_id,
      'security.document.delete',
      'document',
      p_document_id,
      'denied',
      NULL,
      jsonb_build_object('reason', 'not_found_or_unauthorized')
    );
    RAISE EXCEPTION 'Document not found or unauthorized';
  END IF;

  UPDATE public.documents
  SET duplicate_of = NULL,
      is_duplicate = FALSE
  WHERE company_id = p_company_id
    AND duplicate_of = p_document_id
    AND deleted_at IS NULL;

  IF to_regclass('public.document_merges') IS NOT NULL THEN
    EXECUTE '
      UPDATE public.document_merges
         SET source_document_id = CASE WHEN source_document_id = $1 THEN NULL ELSE source_document_id END,
             target_document_id = CASE WHEN target_document_id = $1 THEN NULL ELSE target_document_id END
       WHERE company_id = $2
         AND (source_document_id = $1 OR target_document_id = $1)'
    USING p_document_id, p_company_id;
  END IF;

  IF to_regclass('public.price_anomalies') IS NOT NULL THEN
    EXECUTE '
      DELETE FROM public.price_anomalies
       WHERE company_id = $2
         AND (
           document_id = $1
           OR product_price_id IN (
             SELECT id FROM public.product_prices
              WHERE company_id = $2 AND document_id = $1
           )
         )'
    USING p_document_id, p_company_id;
  END IF;

  IF to_regclass('public.product_purchase_fingerprints') IS NOT NULL THEN
    EXECUTE '
      DELETE FROM public.product_purchase_fingerprints
       WHERE document_id = $1
         AND company_id = $2'
    USING p_document_id, p_company_id;
  END IF;

  IF to_regclass('public.product_prices') IS NOT NULL THEN
    EXECUTE '
      DELETE FROM public.product_prices
       WHERE document_id = $1
         AND company_id = $2'
    USING p_document_id, p_company_id;
  END IF;

  DELETE FROM public.document_items
  WHERE document_id = p_document_id
    AND company_id = p_company_id;

  DELETE FROM public.expenses
  WHERE document_id = p_document_id
    AND company_id = p_company_id;

  UPDATE public.documents
  SET deleted_at = now(),
      duplicate_of = NULL
  WHERE id = p_document_id
    AND company_id = p_company_id
    AND deleted_at IS NULL;

  PERFORM public.record_security_audit_event(
    p_company_id,
    'security.document.delete',
    'document',
    p_document_id,
    'success',
    NULL,
    jsonb_build_object('soft_deleted', true)
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.delete_document_cascade(uuid, uuid) TO authenticated;