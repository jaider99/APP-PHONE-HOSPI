-- ============================================================================
-- Migration 20260527: Force RLS on expense/category/supplier tenant tables
-- ============================================================================
-- P4.1 hardening: these tenant tables already had RLS policies, but FORCE ROW
-- LEVEL SECURITY was missing. Reassert policies with the project's active
-- tenant-membership helper so owner-context mistakes cannot bypass isolation.
-- ============================================================================

BEGIN;

ALTER TABLE public.categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.categories FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS categories_isolation ON public.categories;
CREATE POLICY categories_isolation ON public.categories
  FOR ALL
  TO authenticated
  USING (company_id = ANY(public.user_company_ids()))
  WITH CHECK (company_id = ANY(public.user_company_ids()));

ALTER TABLE public.expenses ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.expenses FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS expenses_isolation ON public.expenses;
CREATE POLICY expenses_isolation ON public.expenses
  FOR ALL
  TO authenticated
  USING (company_id = ANY(public.user_company_ids()))
  WITH CHECK (company_id = ANY(public.user_company_ids()));

ALTER TABLE public.supplier_aliases ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.supplier_aliases FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS supplier_aliases_tenant_isolation ON public.supplier_aliases;
CREATE POLICY supplier_aliases_tenant_isolation ON public.supplier_aliases
  FOR ALL
  TO authenticated
  USING (company_id = ANY(public.user_company_ids()))
  WITH CHECK (company_id = ANY(public.user_company_ids()));

COMMIT;