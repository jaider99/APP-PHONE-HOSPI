# DASHBOARD_STATS_SECURITY_DEFINER_ANALYSIS

## 1. Executive Summary

Supabase flagged `public.dashboard_stats_secure` as a `SECURITY DEFINER` view, which is unsafe in a multi-tenant SaaS because it can evaluate access using the creator's privileges instead of the querying user's RLS context.

In this repository, the intended design is already tenant-scoped:

- raw aggregate data lives in `public.dashboard_stats`, a materialized view over `public.sales`
- app roles are meant to read only through `public.dashboard_stats_secure`
- the secure view filters by `company_id = ANY(public.user_company_ids())`

The lint warning appears because the later hardening migration recreated the view without `security_invoker = true`, even though an earlier migration explicitly used it.

This is best treated as a security regression caused by migration drift, not as evidence that the dashboard architecture itself is wrong.

## 2. Current View Definition

Live database introspection SQL could not be executed from this workspace because direct database query access is not available here. The analysis therefore uses the migration history in the repository plus the Supabase lint finding as the source of truth.

Current repo definition from `supabase/migrations/20260524_lock_down_dashboard_stats.sql`:

```sql
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
```

Important observations:

- It filters by `company_id`.
- It depends on `public.user_company_ids()`.
- It does **not** set `security_invoker = true`.
- That omission is the likely reason Supabase reports the view as effectively running with definer semantics.

Earlier intended definition from `supabase/migrations/00009_multi_tenant_registration_fix.sql`:

```sql
CREATE VIEW dashboard_stats_secure
  WITH (security_invoker = true)
AS
  SELECT *
  FROM dashboard_stats
  WHERE company_id = ANY(public.user_company_ids());
```

## 3. Risk Analysis

The risk is real enough to fix.

Why this matters:

- `public.dashboard_stats` is a materialized view, so it cannot have RLS policies.
- Any protection must therefore come from:
  - restricted grants on the materialized view
  - a tenant-filtered wrapper view or RPC
  - safe helper functions

If `dashboard_stats_secure` executes with definer semantics, it may not respect the querying user's normal permission and RLS context. In a multi-tenant app, that is a cross-tenant exposure risk even if the view currently includes a `company_id` filter.

Why the current filter helps but is still insufficient as the final answer:

- the filter uses `public.user_company_ids()`
- that function is `SECURITY DEFINER`
- in the current repo definitions it does **not** fix `search_path`

So the actual risk is two-part:

1. the view itself is missing `security_invoker = true`
2. the helper function it relies on is `SECURITY DEFINER` without explicit `search_path` hardening

## 4. Base Tables Involved

Base object chain in the repo:

1. `public.sales`
2. `public.dashboard_stats` materialized view aggregating `sales`
3. `public.dashboard_stats_secure` regular view filtering `dashboard_stats`

`public.dashboard_stats` definition from `supabase/migrations/00007_realtime.sql`:

```sql
CREATE MATERIALIZED VIEW IF NOT EXISTS dashboard_stats AS
SELECT 
    company_id,
    SUM(CASE WHEN sale_date >= CURRENT_DATE - INTERVAL '30 days' THEN total_amount ELSE 0 END) AS sales_30d,
    SUM(CASE WHEN sale_date >= CURRENT_DATE - INTERVAL '7 days' THEN total_amount ELSE 0 END) AS sales_7d,
    SUM(CASE WHEN sale_date = CURRENT_DATE THEN total_amount ELSE 0 END) AS sales_today,
    COUNT(CASE WHEN sale_date >= CURRENT_DATE - INTERVAL '30 days' THEN 1 END) AS sales_count_30d
FROM sales
GROUP BY company_id;
```

RLS status from migration history:

- `supabase/migrations/00002_row_level_security.sql` enables RLS on `sales`
- the same migration also applies `FORCE ROW LEVEL SECURITY` broadly to core tenant tables including `sales`
- later multi-tenant hardening migrations switch most tenant policies to `company_id = ANY(public.user_company_ids())`

That means the underlying transactional table is intended to be tenant-safe; the materialized aggregate requires separate protection because RLS does not apply directly to it.

## 5. Root Cause

Root cause in repository history:

1. `00009_multi_tenant_registration_fix.sql` created `dashboard_stats_secure` correctly with `security_invoker = true`
2. `20260524_lock_down_dashboard_stats.sql` later dropped and recreated the view during security hardening
3. the replacement kept tenant filtering and grants, but omitted `security_invoker = true`

So the lint warning is most likely caused by this later migration replacing the previously safe view definition with a weaker one.

Secondary hardening gap:

- `public.user_company_ids()` is `SECURITY DEFINER`
- its repo definitions do not set `search_path`

That is not the direct lint item, but it is part of the same security boundary and should be fixed in the same migration.

## 6. Recommended Fix

Preferred fix:

1. recreate `public.dashboard_stats_secure` with:
   - `security_invoker = true`
   - `security_barrier = true`
2. preserve the exact existing view columns
3. keep explicit tenant filtering via `company_id = ANY(public.user_company_ids())`
4. harden `public.user_company_ids()` with `SET search_path = public, pg_temp`
5. keep raw `dashboard_stats` inaccessible to app roles
6. keep `dashboard_stats_secure` readable only by `authenticated`

RPC is **not** needed here because:

- the view is simple
- the current column set is stable
- the repository already uses the view pattern intentionally
- a safe invoker view plus helper hardening is enough

## 7. Migration Plan

Migration to apply:

- `supabase/migrations/20260602_fix_dashboard_stats_security_invoker.sql`

What it does:

1. recreates `public.user_company_ids()` as `SECURITY DEFINER` with fixed `search_path`
2. revokes public function execute access and grants execute only to `authenticated`
3. reasserts that raw `public.dashboard_stats` is not directly readable by app roles
4. recreates `public.dashboard_stats_secure` with both `security_invoker = true` and `security_barrier = true`
5. preserves the existing columns and tenant filter
6. revokes broad access and grants `SELECT` only to `authenticated`

## 8. Flutter Impact

Flutter impact is low.

Repository search result:

- no Flutter code references `dashboard_stats_secure` directly
- current dashboard code reads `documents` and `sales` directly in Dart repositories/services

Relevant files inspected:

- `lib/services/dashboard_service.dart`
- `lib/features/dashboard/presentation/viewmodels/dashboard_viewmodel.dart`
- `lib/features/dashboard/data/repositories/dashboard_grid_repository.dart`

Conclusion:

- current Flutter dashboard queries do not depend on this exact view name
- fixing the view is still correct for production safety because server-side consumers or future dashboard paths may rely on it
- no Flutter code changes are required for this lint remediation

## 9. Validation Checklist

After applying the migration:

1. Supabase lint no longer reports `Security Definer View` for `public.dashboard_stats_secure`
2. `SELECT * FROM public.dashboard_stats_secure` as tenant A returns only tenant A rows
3. `SELECT * FROM public.dashboard_stats_secure` as tenant B returns only tenant B rows
4. direct `SELECT * FROM public.dashboard_stats` as `authenticated` is denied
5. `anon` cannot read `public.dashboard_stats_secure`
6. helper `public.user_company_ids()` remains functional for tenant-scoped queries and RLS policies
7. dashboard screens still load without permission errors

## 10. Rollback Plan

Rollback is straightforward but restores the weaker security posture.

Rollback steps:

1. drop and recreate `public.dashboard_stats_secure` using the previous definition
2. remove the `search_path` hardening on `public.user_company_ids()` if absolutely necessary

This should only be done if the new migration causes an unexpected compatibility issue, because rolling back would reintroduce the linted security risk.