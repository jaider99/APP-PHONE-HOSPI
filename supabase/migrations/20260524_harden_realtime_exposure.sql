-- P3.3 / V-012: reduce realtime exposure to tables actively used by the app.
-- Realtime respects RLS, but full replica identity can broadcast rich UPDATE/DELETE
-- row payloads to policy-authorized subscribers. Keep sensitive tables out of the
-- realtime publication unless there is an active, tenant-filtered client need.

BEGIN;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
    IF EXISTS (
      SELECT 1
      FROM pg_publication_tables
      WHERE pubname = 'supabase_realtime'
        AND schemaname = 'public'
        AND tablename = 'sales'
    ) THEN
      ALTER PUBLICATION supabase_realtime DROP TABLE public.sales;
    END IF;

    IF EXISTS (
      SELECT 1
      FROM pg_publication_tables
      WHERE pubname = 'supabase_realtime'
        AND schemaname = 'public'
        AND tablename = 'orders'
    ) THEN
      ALTER PUBLICATION supabase_realtime DROP TABLE public.orders;
    END IF;
  END IF;
END;
$$;

ALTER TABLE IF EXISTS public.sales REPLICA IDENTITY DEFAULT;
ALTER TABLE IF EXISTS public.orders REPLICA IDENTITY DEFAULT;

COMMENT ON TABLE public.documents IS
  'Tenant table used by the app with company_id-filtered realtime subscriptions; avoid broadcasting document contents in realtime handlers.';
COMMENT ON TABLE public.sales IS
  'Tenant table. Realtime publication removed because the Flutter app does not subscribe to sales changes.';
COMMENT ON TABLE public.orders IS
  'Tenant table. Realtime publication removed because the Flutter app does not subscribe to order changes.';

COMMIT;
