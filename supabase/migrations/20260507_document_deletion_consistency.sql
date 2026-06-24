-- ============================================================================
-- Migration 20260507: Document deletion consistency + storage isolation
-- ============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.get_company_id_from_path(file_path TEXT)
RETURNS UUID
LANGUAGE plpgsql
IMMUTABLE
AS $$
BEGIN
    RETURN (string_to_array(file_path, '/'))[1]::UUID;
EXCEPTION
    WHEN OTHERS THEN
        RETURN NULL;
END;
$$;

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
  FROM documents d
  WHERE d.id = p_document_id
    AND d.company_id = p_company_id
    AND d.deleted_at IS NULL
  FOR UPDATE;

  IF v_document_id IS NULL THEN
    RAISE EXCEPTION 'Document not found or unauthorized';
  END IF;

  UPDATE documents
  SET duplicate_of = NULL,
      is_duplicate = FALSE
  WHERE company_id = p_company_id
    AND duplicate_of = p_document_id
    AND deleted_at IS NULL;

  DELETE FROM document_items
  WHERE document_id = p_document_id
    AND company_id = p_company_id;

  DELETE FROM expenses
  WHERE document_id = p_document_id
    AND company_id = p_company_id;

  UPDATE documents
  SET deleted_at = NOW(),
      duplicate_of = NULL
  WHERE id = p_document_id
    AND company_id = p_company_id
    AND deleted_at IS NULL;
END;
$$;

GRANT EXECUTE ON FUNCTION public.delete_document_cascade(uuid, uuid) TO authenticated;

DROP POLICY IF EXISTS "docs_storage_select" ON storage.objects;
DROP POLICY IF EXISTS "docs_storage_insert" ON storage.objects;
DROP POLICY IF EXISTS "docs_storage_update" ON storage.objects;
DROP POLICY IF EXISTS "docs_storage_delete" ON storage.objects;
DROP POLICY IF EXISTS "Company members can view documents" ON storage.objects;
DROP POLICY IF EXISTS "Company members can upload documents" ON storage.objects;
DROP POLICY IF EXISTS "Company members can update documents" ON storage.objects;
DROP POLICY IF EXISTS "Admins can delete documents" ON storage.objects;

CREATE POLICY "docs_storage_select" ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id = 'documents'
    AND public.get_company_id_from_path(name) = ANY(public.user_company_ids())
  );

CREATE POLICY "docs_storage_insert" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'documents'
    AND public.get_company_id_from_path(name) = ANY(public.user_company_ids())
  );

CREATE POLICY "docs_storage_update" ON storage.objects
  FOR UPDATE TO authenticated
  USING (
    bucket_id = 'documents'
    AND public.get_company_id_from_path(name) = ANY(public.user_company_ids())
  )
  WITH CHECK (
    bucket_id = 'documents'
    AND public.get_company_id_from_path(name) = ANY(public.user_company_ids())
  );

CREATE POLICY "docs_storage_delete" ON storage.objects
  FOR DELETE TO authenticated
  USING (
    bucket_id = 'documents'
    AND public.get_company_id_from_path(name) = ANY(public.user_company_ids())
  );

COMMIT;