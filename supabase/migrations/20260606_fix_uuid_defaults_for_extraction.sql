-- Fix extraction UUID defaults that can fail under restricted search_path.
-- gen_random_uuid() is available from pg_catalog/pgcrypto and is already used
-- by newer HospiDash migrations.

CREATE EXTENSION IF NOT EXISTS pgcrypto;

ALTER TABLE IF EXISTS public.activity_logs
  ALTER COLUMN id SET DEFAULT gen_random_uuid();

ALTER TABLE IF EXISTS public.documents
  ALTER COLUMN id SET DEFAULT gen_random_uuid();

ALTER TABLE IF EXISTS public.document_items
  ALTER COLUMN id SET DEFAULT gen_random_uuid();

ALTER TABLE IF EXISTS public.products
  ALTER COLUMN id SET DEFAULT gen_random_uuid();
