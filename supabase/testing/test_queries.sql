-- ============================================================================
-- HOSPIDASH: Testing & Debugging Queries
-- Version: 1.0.0
-- ============================================================================
-- Use these queries to verify RLS policies and test data isolation
-- Run in Supabase SQL Editor or local psql
-- ============================================================================

-- ============================================================================
-- PART 1: VERIFY RLS IS ENABLED
-- ============================================================================

-- Check RLS status on all tables
SELECT 
    schemaname,
    tablename,
    rowsecurity AS rls_enabled,
    forcerowsecurity AS rls_forced
FROM pg_tables
WHERE schemaname = 'public'
ORDER BY tablename;

-- Expected: All tables should have rls_enabled = true and rls_forced = true

-- ============================================================================
-- PART 2: LIST ALL RLS POLICIES
-- ============================================================================

SELECT 
    schemaname,
    tablename,
    policyname,
    permissive,
    roles,
    cmd,
    qual AS using_expression,
    with_check
FROM pg_policies
WHERE schemaname = 'public'
ORDER BY tablename, policyname;

-- ============================================================================
-- PART 3: TEST DATA ISOLATION
-- ============================================================================

-- Create test data (run as service_role or with RLS disabled)
/*
-- Create two test companies
INSERT INTO companies (id, name) VALUES 
    ('11111111-1111-1111-1111-111111111111', 'Test Company A'),
    ('22222222-2222-2222-2222-222222222222', 'Test Company B');

-- Create test users (must exist in auth.users first)
-- Then add them to companies:
INSERT INTO company_users (company_id, user_id, role) VALUES
    ('11111111-1111-1111-1111-111111111111', 'user-a-uuid', 'owner'),
    ('22222222-2222-2222-2222-222222222222', 'user-b-uuid', 'owner');

-- Create test providers for each company
INSERT INTO providers (company_id, name) VALUES
    ('11111111-1111-1111-1111-111111111111', 'Provider A1'),
    ('11111111-1111-1111-1111-111111111111', 'Provider A2'),
    ('22222222-2222-2222-2222-222222222222', 'Provider B1'),
    ('22222222-2222-2222-2222-222222222222', 'Provider B2');
*/

-- ============================================================================
-- PART 4: VERIFY ISOLATION (Run as authenticated user)
-- ============================================================================

-- This should ONLY return data from user's current company
SELECT * FROM providers;
SELECT * FROM documents;
SELECT * FROM orders;
SELECT * FROM sales;

-- This should return the user's current context
SELECT * FROM get_user_context();

-- This should return all companies user belongs to
SELECT * FROM get_user_companies();

-- ============================================================================
-- PART 5: TEST CROSS-COMPANY ACCESS (Should FAIL)
-- ============================================================================

-- Try to access another company's data directly (should return 0 rows)
/*
-- Set user context to Company A, then try to query Company B data:
SELECT * FROM providers WHERE company_id = '22222222-2222-2222-2222-222222222222';
-- Expected: 0 rows (RLS blocks access)

-- Try to insert into another company (should fail with policy violation)
INSERT INTO providers (company_id, name) 
VALUES ('22222222-2222-2222-2222-222222222222', 'Malicious Provider');
-- Expected: ERROR: new row violates row-level security policy
*/

-- ============================================================================
-- PART 6: VERIFY INDEX USAGE
-- ============================================================================

-- Check if queries use indexes (run EXPLAIN)
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT * FROM providers WHERE company_id = '11111111-1111-1111-1111-111111111111';

-- Expected: Should show "Index Scan" not "Seq Scan"

-- Check query plan for RLS-filtered query
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT * FROM documents WHERE company_id = (SELECT get_current_company_id());

-- ============================================================================
-- PART 7: FIND MISSING INDEXES ON FOREIGN KEYS
-- ============================================================================

SELECT
    conrelid::regclass AS table_name,
    a.attname AS fk_column,
    pg_size_pretty(pg_relation_size(conrelid)) AS table_size
FROM pg_constraint c
JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = ANY(c.conkey)
WHERE c.contype = 'f'
AND NOT EXISTS (
    SELECT 1 FROM pg_index i
    WHERE i.indrelid = c.conrelid AND a.attnum = ANY(i.indkey)
)
ORDER BY pg_relation_size(conrelid) DESC;

-- Expected: Empty result (all FKs should be indexed)

-- ============================================================================
-- PART 8: CHECK TABLE SIZES AND INDEX USAGE
-- ============================================================================

SELECT
    relname AS table_name,
    pg_size_pretty(pg_total_relation_size(relid)) AS total_size,
    pg_size_pretty(pg_relation_size(relid)) AS table_size,
    pg_size_pretty(pg_total_relation_size(relid) - pg_relation_size(relid)) AS index_size,
    n_tup_ins AS rows_inserted,
    n_tup_upd AS rows_updated,
    n_tup_del AS rows_deleted,
    seq_scan AS sequential_scans,
    idx_scan AS index_scans
FROM pg_stat_user_tables
WHERE schemaname = 'public'
ORDER BY pg_total_relation_size(relid) DESC;

-- ============================================================================
-- PART 9: VERIFY HELPER FUNCTIONS
-- ============================================================================

-- Test provider deduplication
SELECT * FROM find_similar_providers(
    '11111111-1111-1111-1111-111111111111',
    'Comercial Bastida S.L.',
    70
);

-- Test name normalization
SELECT 
    'Comercial Bastida S.L.' AS original,
    normalize_business_name('Comercial Bastida S.L.') AS normalized;

SELECT 
    'COMERCIAL BASTIDA' AS original,
    normalize_business_name('COMERCIAL BASTIDA') AS normalized;

-- Should show both normalize to same value

-- ============================================================================
-- PART 10: COMMON ISSUES & FIXES
-- ============================================================================

/*
ISSUE 1: "permission denied for table X"
FIX: User role doesn't have access. Check:
  - User is authenticated
  - User has a profile with current_company_id set
  - User is member of that company in company_users
  - company_users.is_active = true

ISSUE 2: Query returns 0 rows when data exists
FIX: RLS is filtering out rows. Check:
  - profiles.current_company_id matches the data's company_id
  - User is active member of that company

ISSUE 3: "new row violates row-level security policy"
FIX: Check:
  - INSERT has company_id = user's current company
  - User has appropriate role (owner/admin/manager/member)

ISSUE 4: Slow queries
FIX:
  - Run EXPLAIN ANALYZE on the query
  - Check for Seq Scan instead of Index Scan
  - Verify index exists on company_id and filter columns
  - Check if RLS helper functions are being called per-row (use (SELECT ...) pattern)

ISSUE 5: Can't switch companies
FIX: Verify user is member of target company:
  SELECT * FROM company_users WHERE user_id = auth.uid() AND company_id = 'target-id';
*/

-- ============================================================================
-- PART 11: RESET TEST DATA (Use with caution!)
-- ============================================================================

/*
-- DELETE ALL DATA (development only!)
TRUNCATE 
    activity_logs,
    document_items,
    order_items,
    sales,
    documents,
    orders,
    products,
    providers,
    company_users,
    profiles,
    companies
CASCADE;
*/
