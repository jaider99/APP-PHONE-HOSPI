BEGIN;

-- Harden helper used by tenant-scoped views/RLS. SECURITY DEFINER is justified
-- here to avoid recursive policy evaluation on company_users, but the function
-- must run with a fixed search_path.
CREATE OR REPLACE FUNCTION public.user_company_ids()
RETURNS uuid[]
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT COALESCE(array_agg(company_id), '{}')
  FROM public.company_users
  WHERE user_id = auth.uid() AND is_active = true;
$$;

REVOKE ALL ON FUNCTION public.user_company_ids() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.user_company_ids() TO authenticated;

-- Raw dashboard aggregates must never be readable by app roles because the
-- materialized view cannot enforce RLS directly.
REVOKE ALL ON TABLE public.dashboard_stats FROM anon;
REVOKE ALL ON TABLE public.dashboard_stats FROM authenticated;
REVOKE ALL ON TABLE public.dashboard_stats FROM PUBLIC;

DROP VIEW IF EXISTS public.dashboard_stats_secure;
CREATE VIEW public.dashboard_stats_secure
  WITH (security_invoker = true, security_barrier = true)
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
REVOKE ALL ON TABLE public.dashboard_stats_secure FROM authenticated;
GRANT SELECT ON TABLE public.dashboard_stats_secure TO authenticated;

COMMENT ON VIEW public.dashboard_stats_secure IS
  'Tenant-scoped dashboard stats view. Uses security_invoker=true so caller security context applies; filters rows by public.user_company_ids().';

COMMIT;