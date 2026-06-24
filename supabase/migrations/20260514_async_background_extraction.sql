ALTER TABLE public.documents
ADD COLUMN IF NOT EXISTS extraction_started_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS documents_company_processing_started_idx
ON public.documents (company_id, status, extraction_started_at);