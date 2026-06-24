-- P2.5 / V-009: block direct app-role access to raw dashboard_stats.
-- dashboard_stats is a materialized view and cannot use RLS, so app roles must
-- read only through dashboard_stats_secure, which applies tenant filtering.

BEGIN;

REVOKE ALL ON TABLE public.dashboard_stats FROM anon;
REVOKE ALL ON TABLE public.dashboard_stats FROM authenticated;
REVOKE ALL ON TABLE public.dashboard_stats FROM PUBLIC;

DROP VIEW IF EXISTS public.dashboard_stats_secure;
CREATE VIEW public.dashboard_stats_secure
  WITH (security_barrier = true)
AS
SELECT
  company_id,
  sales_30d,
  sales_7d,
  sales_today,
  sales_count_30d
FROM public.dashboard_stats
WHERE company_id = ANY(public.user_company_ids());

REVOKE ALL ON TABLE public.dashboard_stats_secure FROM anon;
REVOKE ALL ON TABLE public.dashboard_stats_secure FROM PUBLIC;
GRANT SELECT ON TABLE public.dashboard_stats_secure TO authenticated;

COMMENT ON MATERIALIZED VIEW public.dashboard_stats IS
  'Raw dashboard aggregate materialized view. Direct app-role access is revoked; use dashboard_stats_secure.';
COMMENT ON VIEW public.dashboard_stats_secure IS
  'Tenant-filtered dashboard aggregate view for authenticated app users.';

COMMIT;
