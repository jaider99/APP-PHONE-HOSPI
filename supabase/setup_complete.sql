-- ============================================================================
-- HOSPIDASH: Complete Database Setup
-- Version: 1.0.0
-- ============================================================================
-- Run this file in Supabase SQL Editor to set up the entire database.
-- 
-- IMPORTANT: Enable these extensions first:
-- CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
-- CREATE EXTENSION IF NOT EXISTS "pg_trgm";
-- CREATE EXTENSION IF NOT EXISTS "unaccent";
-- ============================================================================

-- ============================================================================
-- STEP 1: Enable Extensions
-- ============================================================================

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";
CREATE EXTENSION IF NOT EXISTS "unaccent";

-- ============================================================================
-- STEP 2: Run migrations in order
-- 
-- Copy the contents of each file from the migrations/ folder:
-- 
-- 1. 00001_multi_tenant_schema.sql
-- 2. 00002_row_level_security.sql
-- 3. 00003_auth_triggers.sql
-- 4. 00004_indexes.sql
-- 5. 00005_storage.sql
-- 6. 00006_provider_deduplication.sql
-- 7. 00007_realtime.sql
-- 8. 00008_fix_company_users_rls.sql
-- 9. 00009_multi_tenant_registration_fix.sql
-- 10. 00010_documents_schema_storage_fix.sql
-- 11. 00011_server_side_extraction.sql
-- 12. 20260330_create_registration_tables.sql
-- 13. 20260330_auth_signup_trigger_hotfix.sql
-- 14. 20260422_expenses_and_categories.sql
-- ============================================================================

-- ============================================================================
-- QUICK VERIFICATION QUERIES (Run after migrations)
-- ============================================================================

-- 1. Verify RLS is enabled on all tables
SELECT 
    tablename,
    rowsecurity AS rls_enabled
FROM pg_tables
WHERE schemaname = 'public'
AND tablename IN (
    'companies', 'profiles', 'company_users', 'providers', 
    'products', 'documents', 'document_items', 'orders', 
    'order_items', 'sales', 'activity_logs'
);

-- 2. Count RLS policies
SELECT 
    tablename,
    COUNT(*) AS policy_count
FROM pg_policies
WHERE schemaname = 'public'
GROUP BY tablename
ORDER BY tablename;

-- 3. Verify helper functions exist
SELECT 
    proname AS function_name
FROM pg_proc
WHERE pronamespace = 'public'::regnamespace
AND proname IN (
    'get_current_company_id',
    'create_company_with_owner',
    'switch_company',
    'get_user_companies',
    'get_user_context',
    'find_similar_providers',
    'create_or_match_provider'
);

-- 4. Verify storage buckets
SELECT id, name, public 
FROM storage.buckets
WHERE id IN ('documents', 'company-assets', 'avatars');

-- ============================================================================
-- SUCCESS! Database is ready.
-- ============================================================================
