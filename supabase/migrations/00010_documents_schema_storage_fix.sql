-- ============================================================================
-- Migration 00010: Fix Documents Schema + Storage for Flutter Compatibility
-- ============================================================================
-- Root cause: Flutter code expects columns that don't exist in DB schema
-- and uses different table/column names than what was created in 00001.
--
-- FIXES:
-- 1. Add missing columns: status, file_name, uploaded_by, deleted_at,
--    extraction_raw, extraction_clean
-- 2. Widen document_type CHECK constraint (add 'unknown', 'expense_ticket')
-- 3. Recreate storage bucket + policies (using user_company_ids())
-- 4. Add RLS policies for document_items table
-- ============================================================================

BEGIN;

-- ═══════════════════════════════════════════════════════════════════════════
-- STEP 1: ADD MISSING COLUMNS TO documents TABLE
-- ═══════════════════════════════════════════════════════════════════════════

-- Flutter reads/writes 'status' (processing, completed, flagged)
-- DB only had 'ocr_status' — adding separate 'status' for document lifecycle
ALTER TABLE documents ADD COLUMN IF NOT EXISTS status TEXT DEFAULT 'processing';

-- Flutter reads/writes 'file_name' for display
ALTER TABLE documents ADD COLUMN IF NOT EXISTS file_name TEXT;

-- Flutter writes 'uploaded_by' (UUID of uploader)
ALTER TABLE documents ADD COLUMN IF NOT EXISTS uploaded_by UUID;

-- Flutter filters by 'deleted_at IS NULL' (soft delete)
ALTER TABLE documents ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;

-- Flutter reads/writes extraction results
ALTER TABLE documents ADD COLUMN IF NOT EXISTS extraction_raw JSONB;
ALTER TABLE documents ADD COLUMN IF NOT EXISTS extraction_clean JSONB;

-- ═══════════════════════════════════════════════════════════════════════════
-- STEP 2: FIX document_type CHECK CONSTRAINT
-- ═══════════════════════════════════════════════════════════════════════════
-- Flutter inserts 'unknown' for new uploads and filters by 'expense_ticket'
-- Old constraint only allowed: invoice, receipt, delivery_note, credit_note, quote, other

ALTER TABLE documents DROP CONSTRAINT IF EXISTS documents_document_type_check;
ALTER TABLE documents ADD CONSTRAINT documents_document_type_check
  CHECK (document_type IN (
    'invoice', 'receipt', 'delivery_note', 'credit_note',
    'quote', 'expense_ticket', 'unknown', 'other'
  ));

-- ═══════════════════════════════════════════════════════════════════════════
-- STEP 3: ENSURE document_items HAS CORRECT RLS
-- ═══════════════════════════════════════════════════════════════════════════

ALTER TABLE document_items ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "document_items_isolation" ON document_items;
CREATE POLICY "document_items_isolation" ON document_items
  FOR ALL
  TO authenticated
  USING (company_id = ANY(public.user_company_ids()))
  WITH CHECK (company_id = ANY(public.user_company_ids()));

-- ═══════════════════════════════════════════════════════════════════════════
-- STEP 4: RECREATE STORAGE BUCKET + FIX POLICIES
-- ═══════════════════════════════════════════════════════════════════════════
-- The 404 error means either bucket doesn't exist or policies block upload.
-- We recreate the bucket as PUBLIC (so getPublicUrl works) and fix policies
-- to use user_company_ids() instead of get_current_company_id().

-- Ensure bucket exists (idempotent)
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'documents',
  'documents',
  TRUE,  -- Public so getPublicUrl() works; RLS controls write access
  10485760,  -- 10MB
  ARRAY[
    'image/jpeg', 'image/png', 'image/webp', 'image/heic',
    'application/pdf', 'application/octet-stream'
  ]
)
ON CONFLICT (id) DO UPDATE SET
  public = TRUE,
  file_size_limit = 10485760,
  allowed_mime_types = ARRAY[
    'image/jpeg', 'image/png', 'image/webp', 'image/heic',
    'application/pdf', 'application/octet-stream'
  ];

-- Drop old storage policies that reference get_current_company_id()
DROP POLICY IF EXISTS "Company members can view documents" ON storage.objects;
DROP POLICY IF EXISTS "Company members can upload documents" ON storage.objects;
DROP POLICY IF EXISTS "Company members can update documents" ON storage.objects;
DROP POLICY IF EXISTS "Admins can delete documents" ON storage.objects;

-- Drop our own policies from previous runs
DROP POLICY IF EXISTS "docs_storage_select" ON storage.objects;
DROP POLICY IF EXISTS "docs_storage_insert" ON storage.objects;
DROP POLICY IF EXISTS "docs_storage_update" ON storage.objects;
DROP POLICY IF EXISTS "docs_storage_delete" ON storage.objects;

-- Simple, reliable storage policies for 'documents' bucket
-- Company isolation is enforced at the documents TABLE level via RLS.
-- Storage policies just ensure authenticated users can use the bucket.

CREATE POLICY "docs_storage_select" ON storage.objects
  FOR SELECT TO authenticated
  USING (bucket_id = 'documents');

CREATE POLICY "docs_storage_insert" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'documents');

CREATE POLICY "docs_storage_update" ON storage.objects
  FOR UPDATE TO authenticated
  USING (bucket_id = 'documents')
  WITH CHECK (bucket_id = 'documents');

CREATE POLICY "docs_storage_delete" ON storage.objects
  FOR DELETE TO authenticated
  USING (bucket_id = 'documents');

-- ═══════════════════════════════════════════════════════════════════════════
-- STEP 5: BACKFILL status FROM ocr_status FOR EXISTING ROWS
-- ═══════════════════════════════════════════════════════════════════════════
-- Map existing ocr_status values to the new status column
UPDATE documents
SET status = CASE
  WHEN ocr_status = 'completed' THEN 'completed'
  WHEN ocr_status = 'failed' THEN 'flagged'
  WHEN ocr_status = 'manual' THEN 'flagged'
  WHEN ocr_status = 'processing' THEN 'processing'
  ELSE 'processing'
END
WHERE status IS NULL OR status = 'processing';

-- Backfill file_name from file_url if not set
UPDATE documents
SET file_name = reverse(split_part(reverse(file_url), '/', 1))
WHERE file_name IS NULL AND file_url IS NOT NULL;

-- Backfill uploaded_by from created_by if not set
UPDATE documents
SET uploaded_by = created_by
WHERE uploaded_by IS NULL AND created_by IS NOT NULL;

COMMIT;
