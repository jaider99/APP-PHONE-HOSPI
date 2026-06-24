# Supabase Security Testing

This folder contains database-side checks for HospiDash tenant isolation and storage policy regressions.

## P4.1 RLS and Storage Isolation

Run `p4_1_rls_storage_isolation.sql` against a disposable local database, staging database, or Supabase SQL Editor session after applying the target migrations, including `supabase/migrations/20260527_force_rls_expense_supplier_tables.sql`.

The script:

- seeds two companies and two users inside a transaction
- switches to the `authenticated` role with a simulated Company A JWT subject
- verifies Company A cannot read, update, delete, or insert Company B rows for representative tenant tables
- includes direct coverage for `categories`, `expenses`, and `supplier_aliases`, which must use `public.user_company_ids()` policies and `FORCE ROW LEVEL SECURITY`
- verifies Company A can read its own document storage object but cannot read or insert a Company B document path
- checks all public tables with `company_id` have RLS enabled, `FORCE ROW LEVEL SECURITY`, and at least one policy
- rolls back all seeded test data when assertions pass

Expected outcome: the script completes with `ROLLBACK`. Any `P4.1 failed:` exception is a security regression or an unapplied hardening migration that needs review.

If the harness reports missing `FORCE ROW LEVEL SECURITY` for `categories`, `expenses`, or `supplier_aliases`, apply `supabase/migrations/20260527_force_rls_expense_supplier_tables.sql` and rerun the script.

Current workspace note: local `psql`/Supabase DB tooling is unavailable, so this suite is authored and statically checked here; execution must happen in a database environment.