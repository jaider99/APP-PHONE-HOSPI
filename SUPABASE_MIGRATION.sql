ALTER TABLE public.documents
  ADD COLUMN IF NOT EXISTS rendered_image_url text;

CREATE OR REPLACE FUNCTION public.flag_stale_processing_documents()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public.documents
  SET
    status = 'flagged',
    notes = 'Extraction timed out. Tap Re-extract to retry.'
  WHERE status = 'processing'
    AND submitted_at IS NOT NULL
    AND submitted_at < NOW() - INTERVAL '5 minutes';
END;
$$;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = 'cron') THEN
    IF NOT EXISTS (
      SELECT 1
      FROM cron.job
      WHERE jobname = 'flag-stale-docs'
    ) THEN
      PERFORM cron.schedule(
        'flag-stale-docs',
        '*/5 * * * *',
        'SELECT public.flag_stale_processing_documents();'
      );
    END IF;
  END IF;
EXCEPTION
  WHEN undefined_table THEN
    NULL;
END;
$$;