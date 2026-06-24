-- ══════════════════════════════════════════════════════════════════════════════
-- Migration 00009: Multi-Tenant Registration Fix
-- 
-- FIXES:
--   1. Registration creates auth user but NEVER inserts into companies
--   2. Registration creates auth user but NEVER inserts into company_users
--   3. dashboard_stats has UNRESTRICTED RLS — critical data leak
--   4. Owner/Manager role selection does nothing
--   5. Missing company_id scoping on all data queries
--   6. No invite_code flow for managers joining existing companies
--
-- THIS MIGRATION:
--   a. Creates public.user_company_ids() SECURITY DEFINER helper
--   b. Adds missing columns to companies (invite_code, business_type, owner_id, timezone, currency)
--   c. Ensures company_users has proper constraints
--   d. Ensures user_preferences exists with active_company_id
--   e. Drops ALL old permissive/unrestricted policies
--   f. Creates new RLS policies for EVERY table using public.user_company_ids()
--   g. Fixes dashboard_stats specifically
-- ══════════════════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────────────────────────
-- STEP A: SECURITY DEFINER helper function
-- Returns array of company_ids for the current authenticated user.
-- Used by ALL RLS policies to avoid self-referencing recursion.
-- NOTE: Must be in public schema — Supabase restricts the auth schema.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.user_company_ids()
RETURNS uuid[] AS $$
  SELECT COALESCE(array_agg(company_id), '{}')
  FROM company_users
  WHERE user_id = auth.uid() AND is_active = true;
$$ LANGUAGE sql SECURITY DEFINER STABLE;

-- ─────────────────────────────────────────────────────────────────────────────
-- STEP B: Ensure companies table has all required columns
-- ─────────────────────────────────────────────────────────────────────────────

-- Add invite_code column (auto-generated 8-char code for manager joins)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'companies' AND column_name = 'invite_code'
  ) THEN
    ALTER TABLE companies ADD COLUMN invite_code text UNIQUE 
      DEFAULT upper(substring(gen_random_uuid()::text, 1, 8));
  END IF;
END $$;

-- Add business_type column
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'companies' AND column_name = 'business_type'
  ) THEN
    ALTER TABLE companies ADD COLUMN business_type text NOT NULL DEFAULT 'restaurant'
      CHECK (business_type IN ('restaurant','bar','cafe','bakery','other'));
  END IF;
END $$;

-- Add owner_id column
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'companies' AND column_name = 'owner_id'
  ) THEN
    ALTER TABLE companies ADD COLUMN owner_id uuid REFERENCES auth.users(id);
  END IF;
END $$;

-- Add timezone column
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'companies' AND column_name = 'timezone'
  ) THEN
    ALTER TABLE companies ADD COLUMN timezone text NOT NULL DEFAULT 'Europe/Madrid';
  END IF;
END $$;

-- Add currency column (may already exist)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'companies' AND column_name = 'currency'
  ) THEN
    ALTER TABLE companies ADD COLUMN currency text NOT NULL DEFAULT 'EUR';
  END IF;
END $$;

-- Add is_active column (may already exist)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'companies' AND column_name = 'is_active'
  ) THEN
    ALTER TABLE companies ADD COLUMN is_active boolean DEFAULT true;
  END IF;
END $$;

-- Generate invite_codes for existing companies that don't have one
UPDATE companies SET invite_code = upper(substring(gen_random_uuid()::text, 1, 8))
WHERE invite_code IS NULL;

-- ─────────────────────────────────────────────────────────────────────────────
-- STEP C: Ensure company_users has proper schema
-- ─────────────────────────────────────────────────────────────────────────────

-- Add joined_at if missing
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'company_users' AND column_name = 'joined_at'
  ) THEN
    ALTER TABLE company_users ADD COLUMN joined_at timestamptz DEFAULT now();
  END IF;
END $$;

-- Add invited_by if missing
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'company_users' AND column_name = 'invited_by'
  ) THEN
    ALTER TABLE company_users ADD COLUMN invited_by uuid REFERENCES auth.users(id);
  END IF;
END $$;

-- Ensure unique constraint on (company_id, user_id)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint 
    WHERE conname = 'company_users_company_id_user_id_key'
  ) THEN
    ALTER TABLE company_users ADD CONSTRAINT company_users_company_id_user_id_key 
      UNIQUE (company_id, user_id);
  END IF;
EXCEPTION 
  WHEN duplicate_object THEN NULL;
END $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- STEP D: Ensure user_preferences table exists
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS user_preferences (
  user_id           uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  active_company_id uuid REFERENCES companies(id) ON DELETE SET NULL,
  updated_at        timestamptz DEFAULT now()
);

-- Add active_company_id if table exists but column doesn't
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'user_preferences' AND column_name = 'active_company_id'
  ) THEN
    ALTER TABLE user_preferences ADD COLUMN active_company_id uuid REFERENCES companies(id) ON DELETE SET NULL;
  END IF;
END $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- STEP E: Drop ALL old permissive/unrestricted policies
-- Safe to run even if policy doesn't exist (IF EXISTS)
-- ─────────────────────────────────────────────────────────────────────────────

-- companies
DROP POLICY IF EXISTS "companies_member_select" ON companies;
DROP POLICY IF EXISTS "companies_owner_insert" ON companies;
DROP POLICY IF EXISTS "companies_owner_update" ON companies;
DROP POLICY IF EXISTS "companies_no_delete" ON companies;
DROP POLICY IF EXISTS "Companies are viewable by members" ON companies;
DROP POLICY IF EXISTS "Users can view own companies" ON companies;
DROP POLICY IF EXISTS "Owner can update company" ON companies;
DROP POLICY IF EXISTS "Admins can update company" ON companies;
DROP POLICY IF EXISTS "Allow authenticated insert" ON companies;

-- company_users
DROP POLICY IF EXISTS "company_users_member_select" ON company_users;
DROP POLICY IF EXISTS "company_users_insert" ON company_users;
DROP POLICY IF EXISTS "company_users_owner_update" ON company_users;
DROP POLICY IF EXISTS "Users can view own memberships" ON company_users;
DROP POLICY IF EXISTS "Users can view company co-members" ON company_users;
DROP POLICY IF EXISTS "Users can join or admins can invite" ON company_users;
DROP POLICY IF EXISTS "Admins can update members" ON company_users;
DROP POLICY IF EXISTS "Admins can remove members" ON company_users;
DROP POLICY IF EXISTS "company_users_select" ON company_users;
DROP POLICY IF EXISTS "company_users_insert_own" ON company_users;
DROP POLICY IF EXISTS "company_users_update" ON company_users;
DROP POLICY IF EXISTS "company_users_delete" ON company_users;

-- dashboard_stats — MATERIALIZED VIEW: cannot have policies, skip
-- (Security enforced via dashboard_stats_secure view instead)

-- documents
DROP POLICY IF EXISTS "documents_isolation" ON documents;
DROP POLICY IF EXISTS "Documents are viewable by company members" ON documents;
DROP POLICY IF EXISTS "Users can insert documents" ON documents;
DROP POLICY IF EXISTS "Users can update own documents" ON documents;
DROP POLICY IF EXISTS "documents_select" ON documents;
DROP POLICY IF EXISTS "documents_insert" ON documents;
DROP POLICY IF EXISTS "documents_update" ON documents;
DROP POLICY IF EXISTS "documents_delete" ON documents;

-- document_items
DROP POLICY IF EXISTS "document_items_isolation" ON document_items;
DROP POLICY IF EXISTS "document_items_select" ON document_items;
DROP POLICY IF EXISTS "document_items_insert" ON document_items;
DROP POLICY IF EXISTS "document_items_update" ON document_items;
DROP POLICY IF EXISTS "document_items_delete" ON document_items;

-- orders
DROP POLICY IF EXISTS "orders_isolation" ON orders;
DROP POLICY IF EXISTS "orders_select" ON orders;
DROP POLICY IF EXISTS "orders_insert" ON orders;
DROP POLICY IF EXISTS "orders_update" ON orders;
DROP POLICY IF EXISTS "orders_delete" ON orders;

-- order_items
DROP POLICY IF EXISTS "order_items_isolation" ON order_items;
DROP POLICY IF EXISTS "order_items_select" ON order_items;
DROP POLICY IF EXISTS "order_items_insert" ON order_items;
DROP POLICY IF EXISTS "order_items_update" ON order_items;
DROP POLICY IF EXISTS "order_items_delete" ON order_items;

-- products
DROP POLICY IF EXISTS "products_isolation" ON products;
DROP POLICY IF EXISTS "products_select" ON products;
DROP POLICY IF EXISTS "products_insert" ON products;
DROP POLICY IF EXISTS "products_update" ON products;
DROP POLICY IF EXISTS "products_delete" ON products;

-- providers
DROP POLICY IF EXISTS "providers_isolation" ON providers;
DROP POLICY IF EXISTS "providers_select" ON providers;
DROP POLICY IF EXISTS "providers_insert" ON providers;
DROP POLICY IF EXISTS "providers_update" ON providers;
DROP POLICY IF EXISTS "providers_delete" ON providers;

-- sales
DROP POLICY IF EXISTS "sales_isolation" ON sales;
DROP POLICY IF EXISTS "sales_select" ON sales;
DROP POLICY IF EXISTS "sales_insert" ON sales;
DROP POLICY IF EXISTS "sales_update" ON sales;
DROP POLICY IF EXISTS "sales_delete" ON sales;

-- activity_logs
DROP POLICY IF EXISTS "activity_logs_isolation" ON activity_logs;
DROP POLICY IF EXISTS "activity_logs_select" ON activity_logs;
DROP POLICY IF EXISTS "activity_logs_insert" ON activity_logs;

-- profiles
DROP POLICY IF EXISTS "profiles_own" ON profiles;
DROP POLICY IF EXISTS "Users can view own profile" ON profiles;
DROP POLICY IF EXISTS "Users can update own profile" ON profiles;
DROP POLICY IF EXISTS "profiles_select" ON profiles;
DROP POLICY IF EXISTS "profiles_insert" ON profiles;
DROP POLICY IF EXISTS "profiles_update" ON profiles;

-- user_preferences
DROP POLICY IF EXISTS "user_preferences_own" ON user_preferences;
DROP POLICY IF EXISTS "user_preferences_select" ON user_preferences;
DROP POLICY IF EXISTS "user_preferences_insert" ON user_preferences;
DROP POLICY IF EXISTS "user_preferences_update" ON user_preferences;
DROP POLICY IF EXISTS "Users can manage own preferences" ON user_preferences;

-- ─────────────────────────────────────────────────────────────────────────────
-- STEP F: Enable RLS on ALL tables and create new policies
-- ─────────────────────────────────────────────────────────────────────────────

-- ═══════════════════════════════════════════════
-- COMPANIES
-- ═══════════════════════════════════════════════
ALTER TABLE companies ENABLE ROW LEVEL SECURITY;

CREATE POLICY "companies_member_select" ON companies
  FOR SELECT USING (id = ANY(public.user_company_ids()));

-- Owner can insert during registration (self-service)
CREATE POLICY "companies_owner_insert" ON companies
  FOR INSERT WITH CHECK (
    auth.uid() IS NOT NULL AND owner_id = auth.uid()
  );

CREATE POLICY "companies_owner_update" ON companies
  FOR UPDATE USING (owner_id = auth.uid());

CREATE POLICY "companies_no_delete" ON companies
  FOR DELETE USING (false);

-- ═══════════════════════════════════════════════
-- COMPANY_USERS
-- ═══════════════════════════════════════════════
ALTER TABLE company_users ENABLE ROW LEVEL SECURITY;

-- Members can see co-members; pending users can see own row
CREATE POLICY "company_users_member_select" ON company_users
  FOR SELECT USING (
    company_id = ANY(public.user_company_ids()) 
    OR user_id = auth.uid()
  );

-- Owner self-insert during registration OR existing owners adding members
CREATE POLICY "company_users_insert" ON company_users
  FOR INSERT WITH CHECK (
    (user_id = auth.uid() AND role = 'owner')
    OR
    (user_id = auth.uid() AND role IN ('manager', 'staff'))
    OR
    company_id IN (
      SELECT cu.company_id FROM company_users cu
      WHERE cu.user_id = auth.uid() 
        AND cu.role = 'owner' AND cu.is_active = true
    )
  );

-- Only owners can update members (approve/deactivate)
CREATE POLICY "company_users_owner_update" ON company_users
  FOR UPDATE USING (
    company_id IN (
      SELECT cu.company_id FROM company_users cu
      WHERE cu.user_id = auth.uid() 
        AND cu.role = 'owner' AND cu.is_active = true
    )
  );

-- ═══════════════════════════════════════════════
-- DASHBOARD_STATS — THE CRITICAL SECURITY FIX
-- dashboard_stats is a MATERIALIZED VIEW, so RLS
-- cannot be applied directly. Instead, create a
-- secure regular view that filters by company_id.
-- App code should query dashboard_stats_secure.
-- ═══════════════════════════════════════════════
DROP VIEW IF EXISTS dashboard_stats_secure;
CREATE VIEW dashboard_stats_secure
  WITH (security_invoker = true)
AS
  SELECT *
  FROM dashboard_stats
  WHERE company_id = ANY(public.user_company_ids());

-- ═══════════════════════════════════════════════
-- DOCUMENTS
-- ═══════════════════════════════════════════════
ALTER TABLE documents ENABLE ROW LEVEL SECURITY;

CREATE POLICY "documents_isolation" ON documents
  FOR ALL USING (company_id = ANY(public.user_company_ids()))
  WITH CHECK (company_id = ANY(public.user_company_ids()));

-- ═══════════════════════════════════════════════
-- DOCUMENT_ITEMS
-- ═══════════════════════════════════════════════
ALTER TABLE document_items ENABLE ROW LEVEL SECURITY;

CREATE POLICY "document_items_isolation" ON document_items
  FOR ALL USING (company_id = ANY(public.user_company_ids()))
  WITH CHECK (company_id = ANY(public.user_company_ids()));

-- ═══════════════════════════════════════════════
-- ORDERS
-- ═══════════════════════════════════════════════
ALTER TABLE orders ENABLE ROW LEVEL SECURITY;

CREATE POLICY "orders_isolation" ON orders
  FOR ALL USING (company_id = ANY(public.user_company_ids()))
  WITH CHECK (company_id = ANY(public.user_company_ids()));

-- ═══════════════════════════════════════════════
-- ORDER_ITEMS
-- ═══════════════════════════════════════════════
ALTER TABLE order_items ENABLE ROW LEVEL SECURITY;

CREATE POLICY "order_items_isolation" ON order_items
  FOR ALL USING (company_id = ANY(public.user_company_ids()))
  WITH CHECK (company_id = ANY(public.user_company_ids()));

-- ═══════════════════════════════════════════════
-- PRODUCTS
-- ═══════════════════════════════════════════════
ALTER TABLE products ENABLE ROW LEVEL SECURITY;

CREATE POLICY "products_isolation" ON products
  FOR ALL USING (company_id = ANY(public.user_company_ids()))
  WITH CHECK (company_id = ANY(public.user_company_ids()));

-- ═══════════════════════════════════════════════
-- PROVIDERS
-- ═══════════════════════════════════════════════
ALTER TABLE providers ENABLE ROW LEVEL SECURITY;

CREATE POLICY "providers_isolation" ON providers
  FOR ALL USING (company_id = ANY(public.user_company_ids()))
  WITH CHECK (company_id = ANY(public.user_company_ids()));

-- ═══════════════════════════════════════════════
-- SALES
-- ═══════════════════════════════════════════════
ALTER TABLE sales ENABLE ROW LEVEL SECURITY;

CREATE POLICY "sales_isolation" ON sales
  FOR ALL USING (company_id = ANY(public.user_company_ids()))
  WITH CHECK (company_id = ANY(public.user_company_ids()));

-- ═══════════════════════════════════════════════
-- ACTIVITY_LOGS
-- ═══════════════════════════════════════════════
ALTER TABLE activity_logs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "activity_logs_isolation" ON activity_logs
  FOR ALL USING (company_id = ANY(public.user_company_ids()));

-- Allow insert for logging (any authenticated user for their own company)
CREATE POLICY "activity_logs_insert" ON activity_logs
  FOR INSERT WITH CHECK (company_id = ANY(public.user_company_ids()));

-- ═══════════════════════════════════════════════
-- PROFILES
-- ═══════════════════════════════════════════════
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;

CREATE POLICY "profiles_own" ON profiles
  FOR ALL USING (id = auth.uid())
  WITH CHECK (id = auth.uid());

-- ═══════════════════════════════════════════════
-- USER_PREFERENCES
-- ═══════════════════════════════════════════════
ALTER TABLE user_preferences ENABLE ROW LEVEL SECURITY;

CREATE POLICY "user_preferences_own" ON user_preferences
  FOR ALL USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

-- ─────────────────────────────────────────────────────────────────────────────
-- STEP G: Performance indexes for new columns
-- ─────────────────────────────────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_companies_invite_code ON companies(invite_code);
CREATE INDEX IF NOT EXISTS idx_companies_owner_id ON companies(owner_id);
CREATE INDEX IF NOT EXISTS idx_companies_tax_id ON companies(tax_id);
CREATE INDEX IF NOT EXISTS idx_company_users_user_active ON company_users(user_id, is_active);
CREATE INDEX IF NOT EXISTS idx_user_preferences_active_company ON user_preferences(active_company_id);

-- ─────────────────────────────────────────────────────────────────────────────
-- STEP H: RPC Functions for ATOMIC registration
--
-- These bypass RLS (SECURITY DEFINER) so the chicken-and-egg problem
-- (companies INSERT needs company_users for SELECT policy) is eliminated.
-- Each function runs in a single transaction — all or nothing.
-- ─────────────────────────────────────────────────────────────────────────────

-- ═══════════════════════════════════════════════
-- OWNER REGISTRATION: create company + membership + profile in ONE call
-- Drop ALL old overloads to avoid ambiguity
-- ═══════════════════════════════════════════════
DROP FUNCTION IF EXISTS public.create_company_with_owner(text, text, text);
DROP FUNCTION IF EXISTS public.create_company_with_owner(uuid, text, text, text, text, text, text, text, text, text);

CREATE OR REPLACE FUNCTION public.create_company_with_owner(
  p_user_id         uuid,
  p_company_name    text,
  p_legal_name      text,
  p_tax_id          text,
  p_city            text    DEFAULT '',
  p_country         text    DEFAULT '',
  p_currency        text    DEFAULT 'EUR',
  p_timezone        text    DEFAULT 'Europe/Madrid',
  p_business_type   text    DEFAULT 'restaurant',
  p_full_name       text    DEFAULT '',
  p_email           text    DEFAULT ''
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company_id uuid;
  v_invite_code text;
  v_result jsonb;
BEGIN
  -- Validate user exists in auth
  IF NOT EXISTS (SELECT 1 FROM auth.users WHERE id = p_user_id) THEN
    RAISE EXCEPTION 'User not found: %', p_user_id;
  END IF;

  -- Check duplicate tax_id
  IF EXISTS (SELECT 1 FROM companies WHERE tax_id = p_tax_id) THEN
    RAISE EXCEPTION 'DUPLICATE_TAX_ID: A business with tax ID % already exists', p_tax_id;
  END IF;

  -- Generate invite code
  v_invite_code := upper(substring(gen_random_uuid()::text, 1, 8));

  -- 1. Insert company
  INSERT INTO companies (
    name, legal_name, tax_id, city, country, currency, timezone,
    business_type, owner_id, invite_code, is_active
  ) VALUES (
    p_company_name, p_legal_name, p_tax_id, p_city, p_country, p_currency,
    p_timezone, p_business_type, p_user_id, v_invite_code, true
  )
  RETURNING id INTO v_company_id;

  -- 2. Insert company_users (owner, active)
  INSERT INTO company_users (company_id, user_id, role, is_active)
  VALUES (v_company_id, p_user_id, 'owner', true);

  -- 3. Upsert user_preferences
  INSERT INTO user_preferences (user_id, active_company_id)
  VALUES (p_user_id, v_company_id)
  ON CONFLICT (user_id) DO UPDATE SET active_company_id = v_company_id;

  -- 4. Upsert profile
  INSERT INTO profiles (id, email, full_name, current_company_id)
  VALUES (p_user_id, p_email, p_full_name, v_company_id)
  ON CONFLICT (id) DO UPDATE SET
    full_name = EXCLUDED.full_name,
    current_company_id = v_company_id;

  -- Build return JSON
  v_result := jsonb_build_object(
    'company_id', v_company_id,
    'company_name', p_company_name,
    'invite_code', v_invite_code,
    'role', 'owner'
  );

  RETURN v_result;
END;
$$;

-- ═══════════════════════════════════════════════
-- MANAGER REGISTRATION: join company via invite code
-- Drop old overload without p_email
-- ═══════════════════════════════════════════════
DROP FUNCTION IF EXISTS public.join_company_as_manager(uuid, text, text);

CREATE OR REPLACE FUNCTION public.join_company_as_manager(
  p_user_id     uuid,
  p_invite_code text,
  p_full_name   text DEFAULT '',
  p_email       text DEFAULT ''
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company_id   uuid;
  v_company_name text;
  v_is_active    boolean;
  v_result       jsonb;
BEGIN
  -- Validate user exists
  IF NOT EXISTS (SELECT 1 FROM auth.users WHERE id = p_user_id) THEN
    RAISE EXCEPTION 'User not found: %', p_user_id;
  END IF;

  -- Resolve invite code
  SELECT id, name, is_active
  INTO v_company_id, v_company_name, v_is_active
  FROM companies
  WHERE invite_code = upper(trim(p_invite_code));

  IF v_company_id IS NULL THEN
    RAISE EXCEPTION 'INVALID_INVITE_CODE: No company found for invite code %', p_invite_code;
  END IF;

  IF NOT v_is_active THEN
    RAISE EXCEPTION 'COMPANY_INACTIVE: This business account is not active';
  END IF;

  -- Check not already a member
  IF EXISTS (
    SELECT 1 FROM company_users
    WHERE company_id = v_company_id AND user_id = p_user_id
  ) THEN
    RAISE EXCEPTION 'ALREADY_MEMBER: User is already a member of this company';
  END IF;

  -- 1. Insert company_users (manager, INACTIVE = pending approval)
  INSERT INTO company_users (company_id, user_id, role, is_active)
  VALUES (v_company_id, p_user_id, 'manager', false);

  -- 2. Upsert profile (no current_company_id — pending)
  INSERT INTO profiles (id, email, full_name)
  VALUES (p_user_id, p_email, p_full_name)
  ON CONFLICT (id) DO UPDATE SET full_name = EXCLUDED.full_name;

  -- 3. Log the access request
  BEGIN
    INSERT INTO activity_logs (company_id, user_id, action, entity_type, new_data)
    VALUES (
      v_company_id, p_user_id, 'manager_access_requested', 'company_users',
      jsonb_build_object('full_name', p_full_name)
    );
  EXCEPTION WHEN OTHERS THEN
    -- Non-critical, don't fail registration
    NULL;
  END;

  v_result := jsonb_build_object(
    'company_id', v_company_id,
    'company_name', v_company_name,
    'role', 'manager',
    'is_active', false
  );

  RETURN v_result;
END;
$$;

-- Grant execute to authenticated users (needed for Supabase PostgREST)
-- Must specify full signature to avoid ambiguity with any old overloads
GRANT EXECUTE ON FUNCTION public.create_company_with_owner(
  uuid, text, text, text, text, text, text, text, text, text, text
) TO authenticated;
GRANT EXECUTE ON FUNCTION public.join_company_as_manager(
  uuid, text, text, text
) TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- DONE
-- ─────────────────────────────────────────────────────────────────────────────
