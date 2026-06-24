-- ============================================================================
-- HospiDash P4.1: RLS and Storage Isolation Regression Harness
-- ============================================================================
-- Purpose:
--   Fail-fast tenant isolation checks for Supabase SQL Editor, local psql, or CI.
--
-- What this covers:
--   1) Every public table with a company_id column has RLS enabled and forced.
--   2) Every public table with a company_id column has at least one policy.
--   3) A Company A authenticated user cannot read, update, delete, or insert
--      representative Company B tenant rows.
--   4) The documents storage bucket policy allows Company A paths and blocks
--      Company B paths for a Company A user.
--
-- Execution notes:
--   - Run as a database owner/service role in a non-production or disposable
--     test database with all target migrations applied.
--   - The script runs inside a transaction and rolls back seeded fixtures.
--   - Any failed assertion raises an exception and aborts the transaction.
-- ============================================================================

BEGIN;

SET LOCAL statement_timeout = '30s';
SET LOCAL lock_timeout = '5s';

-- Fixed UUID fixtures make failures easy to trace and rollback safe.
CREATE TEMP TABLE p4_1_fixture (
  company_a uuid NOT NULL,
  company_b uuid NOT NULL,
  user_a uuid NOT NULL,
  user_b uuid NOT NULL,
  provider_a uuid NOT NULL,
  provider_b uuid NOT NULL,
  product_a uuid NOT NULL,
  product_b uuid NOT NULL,
  document_a uuid NOT NULL,
  document_b uuid NOT NULL,
  document_item_a uuid NOT NULL,
  document_item_b uuid NOT NULL,
  category_a uuid NOT NULL,
  category_b uuid NOT NULL,
  expense_a uuid NOT NULL,
  expense_b uuid NOT NULL,
  supplier_alias_a uuid NOT NULL,
  supplier_alias_b uuid NOT NULL
) ON COMMIT DROP;

INSERT INTO p4_1_fixture VALUES (
  '00000000-0000-0000-0000-00000000a001',
  '00000000-0000-0000-0000-00000000b001',
  '00000000-0000-0000-0000-00000000aa01',
  '00000000-0000-0000-0000-00000000bb01',
  '00000000-0000-0000-0000-00000000a101',
  '00000000-0000-0000-0000-00000000b101',
  '00000000-0000-0000-0000-00000000a201',
  '00000000-0000-0000-0000-00000000b201',
  '00000000-0000-0000-0000-00000000a301',
  '00000000-0000-0000-0000-00000000b301',
  '00000000-0000-0000-0000-00000000a401',
  '00000000-0000-0000-0000-00000000b401',
  '00000000-0000-0000-0000-00000000a501',
  '00000000-0000-0000-0000-00000000b501',
  '00000000-0000-0000-0000-00000000a601',
  '00000000-0000-0000-0000-00000000b601',
  '00000000-0000-0000-0000-00000000a701',
  '00000000-0000-0000-0000-00000000b701'
);

-- ---------------------------------------------------------------------------
-- Metadata assertions: all tenant tables must have enforced RLS and policies.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  missing_rls text;
  missing_force_rls text;
  missing_policy text;
BEGIN
  SELECT string_agg(format('%I.%I', n.nspname, c.relname), ', ' ORDER BY c.relname)
    INTO missing_rls
  FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
  JOIN pg_attribute a ON a.attrelid = c.oid
  WHERE n.nspname = 'public'
    AND c.relkind = 'r'
    AND a.attname = 'company_id'
    AND NOT a.attisdropped
    AND NOT c.relrowsecurity;

  IF missing_rls IS NOT NULL THEN
    RAISE EXCEPTION 'P4.1 failed: tenant tables missing RLS: %', missing_rls;
  END IF;

  SELECT string_agg(format('%I.%I', n.nspname, c.relname), ', ' ORDER BY c.relname)
    INTO missing_force_rls
  FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
  JOIN pg_attribute a ON a.attrelid = c.oid
  WHERE n.nspname = 'public'
    AND c.relkind = 'r'
    AND a.attname = 'company_id'
    AND NOT a.attisdropped
    AND NOT c.relforcerowsecurity;

  IF missing_force_rls IS NOT NULL THEN
    RAISE EXCEPTION 'P4.1 failed: tenant tables missing FORCE RLS: %', missing_force_rls;
  END IF;

  SELECT string_agg(format('%I.%I', n.nspname, c.relname), ', ' ORDER BY c.relname)
    INTO missing_policy
  FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
  JOIN pg_attribute a ON a.attrelid = c.oid
  WHERE n.nspname = 'public'
    AND c.relkind = 'r'
    AND a.attname = 'company_id'
    AND NOT a.attisdropped
    AND NOT EXISTS (
      SELECT 1
      FROM pg_policies p
      WHERE p.schemaname = n.nspname
        AND p.tablename = c.relname
    );

  IF missing_policy IS NOT NULL THEN
    RAISE EXCEPTION 'P4.1 failed: tenant tables missing policies: %', missing_policy;
  END IF;
END;
$$;

-- ---------------------------------------------------------------------------
-- Fixture seed as privileged role. This is rolled back at the end.
-- ---------------------------------------------------------------------------
INSERT INTO auth.users (
  id,
  instance_id,
  aud,
  role,
  email,
  encrypted_password,
  email_confirmed_at,
  created_at,
  updated_at
)
SELECT user_id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', email, '', now(), now(), now()
FROM (
  SELECT user_a AS user_id, 'p4-user-a@example.test' AS email FROM p4_1_fixture
  UNION ALL
  SELECT user_b AS user_id, 'p4-user-b@example.test' AS email FROM p4_1_fixture
) users
ON CONFLICT (id) DO NOTHING;

INSERT INTO companies (id, name, owner_id)
SELECT company_a, 'P4 Tenant A', user_a FROM p4_1_fixture
UNION ALL
SELECT company_b, 'P4 Tenant B', user_b FROM p4_1_fixture
ON CONFLICT (id) DO NOTHING;

INSERT INTO profiles (id, email, full_name, current_company_id)
SELECT user_a, 'p4-user-a@example.test', 'P4 User A', company_a FROM p4_1_fixture
UNION ALL
SELECT user_b, 'p4-user-b@example.test', 'P4 User B', company_b FROM p4_1_fixture
ON CONFLICT (id) DO NOTHING;

INSERT INTO company_users (company_id, user_id, role, is_active, joined_at)
SELECT company_a, user_a, 'owner', true, now() FROM p4_1_fixture
UNION ALL
SELECT company_b, user_b, 'owner', true, now() FROM p4_1_fixture
ON CONFLICT (company_id, user_id) DO NOTHING;

INSERT INTO categories (id, company_id, name, icon, sort_order)
SELECT category_a, company_a, 'P4 Category A', 'category', 9001 FROM p4_1_fixture
UNION ALL
SELECT category_b, company_b, 'P4 Category B', 'category', 9002 FROM p4_1_fixture
ON CONFLICT (id) DO NOTHING;

INSERT INTO providers (id, company_id, name, created_by)
SELECT provider_a, company_a, 'P4 Provider A', user_a FROM p4_1_fixture
UNION ALL
SELECT provider_b, company_b, 'P4 Provider B', user_b FROM p4_1_fixture
ON CONFLICT (id) DO NOTHING;

INSERT INTO supplier_aliases (id, company_id, provider_id, raw_name)
SELECT supplier_alias_a, company_a, provider_a, 'P4 Alias A' FROM p4_1_fixture
UNION ALL
SELECT supplier_alias_b, company_b, provider_b, 'P4 Alias B' FROM p4_1_fixture
ON CONFLICT (id) DO NOTHING;

INSERT INTO products (id, company_id, provider_id, name, created_by)
SELECT product_a, company_a, provider_a, 'P4 Product A', user_a FROM p4_1_fixture
UNION ALL
SELECT product_b, company_b, provider_b, 'P4 Product B', user_b FROM p4_1_fixture
ON CONFLICT (id) DO NOTHING;

INSERT INTO documents (
  id,
  company_id,
  provider_id,
  document_type,
  document_number,
  file_path,
  created_by
)
SELECT document_a, company_a, provider_a, 'invoice', 'P4-A-001', company_a || '/' || document_a || '/original.pdf', user_a FROM p4_1_fixture
UNION ALL
SELECT document_b, company_b, provider_b, 'invoice', 'P4-B-001', company_b || '/' || document_b || '/original.pdf', user_b FROM p4_1_fixture
ON CONFLICT (id) DO NOTHING;

INSERT INTO expenses (id, company_id, document_id, category_id, supplier_name, total_amount, status, created_by)
SELECT expense_a, company_a, document_a, category_a, 'P4 Supplier A', 10, 'completed', user_a FROM p4_1_fixture
UNION ALL
SELECT expense_b, company_b, document_b, category_b, 'P4 Supplier B', 20, 'completed', user_b FROM p4_1_fixture
ON CONFLICT (id) DO NOTHING;

INSERT INTO document_items (id, document_id, company_id, product_id, description, quantity, unit_price, line_total)
SELECT document_item_a, document_a, company_a, product_a, 'P4 Item A', 1, 10, 10 FROM p4_1_fixture
UNION ALL
SELECT document_item_b, document_b, company_b, product_b, 'P4 Item B', 1, 20, 20 FROM p4_1_fixture
ON CONFLICT (id) DO NOTHING;

INSERT INTO storage.buckets (id, name, public)
VALUES ('documents', 'documents', false)
ON CONFLICT (id) DO UPDATE SET public = false;

INSERT INTO storage.objects (bucket_id, name, metadata)
SELECT 'documents', company_a || '/' || document_a || '/original.pdf', '{}'::jsonb FROM p4_1_fixture
UNION ALL
SELECT 'documents', company_b || '/' || document_b || '/original.pdf', '{}'::jsonb FROM p4_1_fixture
ON CONFLICT (bucket_id, name) DO NOTHING;

-- ---------------------------------------------------------------------------
-- Runtime assertions as Company A authenticated user.
-- ---------------------------------------------------------------------------
SELECT set_config('request.jwt.claim.sub', user_a::text, true) FROM p4_1_fixture;
SELECT set_config('request.jwt.claim.role', 'authenticated', true);
SET LOCAL ROLE authenticated;

DO $$
DECLARE
  v_company_a uuid := '00000000-0000-0000-0000-00000000a001';
  v_company_b uuid := '00000000-0000-0000-0000-00000000b001';
  v_category_a uuid := '00000000-0000-0000-0000-00000000a501';
  v_provider_b uuid := '00000000-0000-0000-0000-00000000b101';
  v_category_b uuid := '00000000-0000-0000-0000-00000000b501';
  v_expense_a uuid := '00000000-0000-0000-0000-00000000a601';
  v_expense_b uuid := '00000000-0000-0000-0000-00000000b601';
  v_supplier_alias_a uuid := '00000000-0000-0000-0000-00000000a701';
  v_supplier_alias_b uuid := '00000000-0000-0000-0000-00000000b701';
  v_visible_count integer;
  v_rows integer;
BEGIN
  SELECT count(*) INTO v_visible_count FROM providers;
  IF v_visible_count <> 1 THEN
    RAISE EXCEPTION 'P4.1 failed: Company A should see exactly 1 provider, saw %', v_visible_count;
  END IF;

  SELECT count(*) INTO v_visible_count FROM providers WHERE company_id = v_company_b;
  IF v_visible_count <> 0 THEN
    RAISE EXCEPTION 'P4.1 failed: Company A can read Company B providers';
  END IF;

  SELECT count(*) INTO v_visible_count FROM documents WHERE company_id = v_company_b;
  IF v_visible_count <> 0 THEN
    RAISE EXCEPTION 'P4.1 failed: Company A can read Company B documents';
  END IF;

  SELECT count(*) INTO v_visible_count FROM document_items WHERE company_id = v_company_b;
  IF v_visible_count <> 0 THEN
    RAISE EXCEPTION 'P4.1 failed: Company A can read Company B document_items';
  END IF;

  SELECT count(*) INTO v_visible_count FROM products WHERE company_id = v_company_b;
  IF v_visible_count <> 0 THEN
    RAISE EXCEPTION 'P4.1 failed: Company A can read Company B products';
  END IF;

  SELECT count(*) INTO v_visible_count FROM categories WHERE id = v_category_a;
  IF v_visible_count <> 1 THEN
    RAISE EXCEPTION 'P4.1 failed: Company A cannot read its own category';
  END IF;

  SELECT count(*) INTO v_visible_count FROM categories WHERE company_id = v_company_b;
  IF v_visible_count <> 0 THEN
    RAISE EXCEPTION 'P4.1 failed: Company A can read Company B categories';
  END IF;

  SELECT count(*) INTO v_visible_count FROM expenses WHERE id = v_expense_a;
  IF v_visible_count <> 1 THEN
    RAISE EXCEPTION 'P4.1 failed: Company A cannot read its own expense';
  END IF;

  SELECT count(*) INTO v_visible_count FROM expenses WHERE company_id = v_company_b;
  IF v_visible_count <> 0 THEN
    RAISE EXCEPTION 'P4.1 failed: Company A can read Company B expenses';
  END IF;

  SELECT count(*) INTO v_visible_count FROM supplier_aliases WHERE id = v_supplier_alias_a;
  IF v_visible_count <> 1 THEN
    RAISE EXCEPTION 'P4.1 failed: Company A cannot read its own supplier_alias';
  END IF;

  SELECT count(*) INTO v_visible_count FROM supplier_aliases WHERE company_id = v_company_b;
  IF v_visible_count <> 0 THEN
    RAISE EXCEPTION 'P4.1 failed: Company A can read Company B supplier_aliases';
  END IF;

  UPDATE providers SET notes = 'p4-cross-tenant-update' WHERE id = v_provider_b;
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows <> 0 THEN
    RAISE EXCEPTION 'P4.1 failed: Company A updated % Company B provider rows', v_rows;
  END IF;

  UPDATE categories SET name = 'P4 Cross Tenant Category' WHERE id = v_category_b;
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows <> 0 THEN
    RAISE EXCEPTION 'P4.1 failed: Company A updated % Company B category rows', v_rows;
  END IF;

  UPDATE expenses SET notes = 'p4-cross-tenant-update' WHERE id = v_expense_b;
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows <> 0 THEN
    RAISE EXCEPTION 'P4.1 failed: Company A updated % Company B expense rows', v_rows;
  END IF;

  UPDATE supplier_aliases SET raw_name = 'P4 Cross Tenant Alias' WHERE id = v_supplier_alias_b;
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows <> 0 THEN
    RAISE EXCEPTION 'P4.1 failed: Company A updated % Company B supplier_alias rows', v_rows;
  END IF;

  DELETE FROM providers WHERE id = v_provider_b;
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows <> 0 THEN
    RAISE EXCEPTION 'P4.1 failed: Company A deleted % Company B provider rows', v_rows;
  END IF;

  DELETE FROM categories WHERE id = v_category_b;
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows <> 0 THEN
    RAISE EXCEPTION 'P4.1 failed: Company A deleted % Company B category rows', v_rows;
  END IF;

  DELETE FROM expenses WHERE id = v_expense_b;
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows <> 0 THEN
    RAISE EXCEPTION 'P4.1 failed: Company A deleted % Company B expense rows', v_rows;
  END IF;

  DELETE FROM supplier_aliases WHERE id = v_supplier_alias_b;
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows <> 0 THEN
    RAISE EXCEPTION 'P4.1 failed: Company A deleted % Company B supplier_alias rows', v_rows;
  END IF;

  BEGIN
    INSERT INTO providers (company_id, name) VALUES (v_company_b, 'P4 Malicious Provider');
    RAISE EXCEPTION 'P4.1 failed: Company A inserted a Company B provider';
  EXCEPTION
    WHEN insufficient_privilege OR check_violation OR with_check_option_violation THEN
      NULL;
  END;

  BEGIN
    INSERT INTO categories (company_id, name) VALUES (v_company_b, 'P4 Malicious Category');
    RAISE EXCEPTION 'P4.1 failed: Company A inserted a Company B category';
  EXCEPTION
    WHEN insufficient_privilege OR check_violation OR with_check_option_violation THEN
      NULL;
  END;

  BEGIN
    INSERT INTO expenses (company_id, supplier_name, total_amount) VALUES (v_company_b, 'P4 Malicious Expense', 99);
    RAISE EXCEPTION 'P4.1 failed: Company A inserted a Company B expense';
  EXCEPTION
    WHEN insufficient_privilege OR check_violation OR with_check_option_violation THEN
      NULL;
  END;

  BEGIN
    INSERT INTO supplier_aliases (company_id, provider_id, raw_name)
    VALUES (v_company_b, v_provider_b, 'P4 Malicious Alias');
    RAISE EXCEPTION 'P4.1 failed: Company A inserted a Company B supplier_alias';
  EXCEPTION
    WHEN insufficient_privilege OR check_violation OR with_check_option_violation OR foreign_key_violation THEN
      NULL;
  END;

  BEGIN
    INSERT INTO providers (company_id, name) VALUES (v_company_a, 'P4 Allowed Provider A');
  EXCEPTION
    WHEN OTHERS THEN
      RAISE EXCEPTION 'P4.1 failed: Company A could not insert its own provider: %', SQLERRM;
  END;
END;
$$;

DO $$
DECLARE
  v_company_a uuid := '00000000-0000-0000-0000-00000000a001';
  v_company_b uuid := '00000000-0000-0000-0000-00000000b001';
  v_document_a uuid := '00000000-0000-0000-0000-00000000a301';
  v_document_b uuid := '00000000-0000-0000-0000-00000000b301';
  v_visible_count integer;
BEGIN
  SELECT count(*) INTO v_visible_count
  FROM storage.objects
  WHERE bucket_id = 'documents'
    AND name = v_company_a || '/' || v_document_a || '/original.pdf';

  IF v_visible_count <> 1 THEN
    RAISE EXCEPTION 'P4.1 failed: Company A cannot read its own document storage object';
  END IF;

  SELECT count(*) INTO v_visible_count
  FROM storage.objects
  WHERE bucket_id = 'documents'
    AND name = v_company_b || '/' || v_document_b || '/original.pdf';

  IF v_visible_count <> 0 THEN
    RAISE EXCEPTION 'P4.1 failed: Company A can read Company B document storage object';
  END IF;

  BEGIN
    INSERT INTO storage.objects (bucket_id, name, metadata)
    VALUES ('documents', v_company_b || '/' || uuid_generate_v4() || '/malicious.pdf', '{}'::jsonb);
    RAISE EXCEPTION 'P4.1 failed: Company A inserted a Company B document storage object';
  EXCEPTION
    WHEN insufficient_privilege OR check_violation OR with_check_option_violation THEN
      NULL;
  END;
END;
$$;

RESET ROLE;

-- If the script reaches this point, all assertions passed. Keep the database
-- clean by rolling back the test fixtures.
ROLLBACK;