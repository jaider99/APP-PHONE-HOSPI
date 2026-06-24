-- Migration 00011: Server-side extraction pipeline support
-- Adds 'failed' status and file_path column.
-- The Edge Function is invoked directly from Flutter, not via DB trigger.

-- ─── 1. Add 'failed' to document status constraint ──────────────────────────
-- Drop old check constraint if it exists, then add one that includes 'failed'
DO $$
BEGIN
  -- Drop existing check constraint on status (name may vary)
  ALTER TABLE documents DROP CONSTRAINT IF EXISTS documents_status_check;
  ALTER TABLE documents DROP CONSTRAINT IF EXISTS chk_documents_status;
EXCEPTION WHEN OTHERS THEN
  NULL;
END $$;

ALTER TABLE documents
  ADD CONSTRAINT chk_documents_status
  CHECK (status IN ('processing', 'completed', 'flagged', 'failed'));

-- ─── 2. Ensure file_path column exists ──────────────────────────────────────
DO $$
BEGIN
  ALTER TABLE documents ADD COLUMN IF NOT EXISTS file_path text;
EXCEPTION WHEN duplicate_column THEN
  NULL;
END $$;

-- ─── 3. Index on status for quick "processing"/"failed" queries ─────────────
CREATE INDEX IF NOT EXISTS idx_documents_status ON documents (status);
CREATE INDEX IF NOT EXISTS idx_documents_company_status ON documents (company_id, status);
