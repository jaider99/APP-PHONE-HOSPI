-- ============================================================================
-- MULTI-TENANT COMPANY REGISTRATION - SUPABASE SQL SETUP
-- ============================================================================
-- Run this in Supabase SQL Editor: Dashboard > SQL Editor > New Query
-- ALIGNED TO EXISTING SCHEMA (00001_multi_tenant_schema.sql)
-- ============================================================================

-- ============================================================================
-- STEP 0: VERIFY EXISTING SCHEMA (skip table creation - already exists)
-- ============================================================================
-- Your DB already has: companies, profiles, company_users from migration 00001
-- This script ONLY adds:
--   - Missing RLS policies
--   - Helper functions with proper security
--   - The register_company RPC function
--   - Grants for authenticated users

-- ============================================================================
-- STEP 1: ADD INDEXES FOR RLS PERFORMANCE (idempotent)
-- ============================================================================

-- Covering index for RLS policy lookups
CREATE INDEX IF NOT EXISTS idx_company_users_rls 
ON public.company_users(user_id, company_id, is_active, role);

-- Index for current_company lookup
CREATE INDEX IF NOT EXISTS idx_profiles_current_company 
ON public.profiles(current_company_id);

-- Index for tax_id lookups (company identifier)
CREATE INDEX IF NOT EXISTS idx_companies_tax_id 
ON public.companies(country, tax_id) WHERE tax_id IS NOT NULL;

-- ============================================================================
-- STEP 2: GRANTS FOR AUTHENTICATED USERS
-- ============================================================================
-- RLS filters access; grants enable the operations

GRANT SELECT, INSERT, UPDATE ON public.companies TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.company_users TO authenticated;
GRANT SELECT, UPDATE ON public.profiles TO authenticated;

-- ============================================================================
-- STEP 3: ROW LEVEL SECURITY (RLS) POLICIES
-- ============================================================================

-- Enable RLS on companies (idempotent)
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;

-- Enable RLS on company_users (idempotent)
ALTER TABLE public.company_users ENABLE ROW LEVEL SECURITY;

-- Drop existing policies first (idempotent)
DROP POLICY IF EXISTS "Companies are viewable by members" ON public.companies;
DROP POLICY IF EXISTS "Companies can be created by authenticated users" ON public.companies;
DROP POLICY IF EXISTS "Companies can be updated by admins" ON public.companies;

DROP POLICY IF EXISTS "Company users viewable by company members" ON public.company_users;
DROP POLICY IF EXISTS "Company users insertable by admins" ON public.company_users;
DROP POLICY IF EXISTS "Company users updatable by admins" ON public.company_users;
DROP POLICY IF EXISTS "Company users deletable by admins" ON public.company_users;

-- Companies: Users can only see companies they are members of
CREATE POLICY "Companies are viewable by members" ON public.companies
    FOR SELECT TO authenticated
    USING (
        id IN (
            SELECT company_id FROM public.company_users 
            WHERE user_id = (SELECT id FROM public.profiles WHERE id = auth.uid())
            AND is_active = TRUE
        )
    );

-- Companies: Any authenticated user can create a company
CREATE POLICY "Companies can be created by authenticated users" ON public.companies
    FOR INSERT TO authenticated
    WITH CHECK (auth.uid() IS NOT NULL);

-- Companies: Only owners/admins can update (with WITH CHECK)
CREATE POLICY "Companies can be updated by admins" ON public.companies
    FOR UPDATE TO authenticated
    USING (
        id IN (
            SELECT company_id FROM public.company_users 
            WHERE user_id = (SELECT id FROM public.profiles WHERE id = auth.uid())
            AND role IN ('owner', 'admin') 
            AND is_active = TRUE
        )
    )
    WITH CHECK (
        id IN (
            SELECT company_id FROM public.company_users 
            WHERE user_id = (SELECT id FROM public.profiles WHERE id = auth.uid())
            AND role IN ('owner', 'admin') 
            AND is_active = TRUE
        )
    );

-- Company Users: Members can view their company's users
CREATE POLICY "Company users viewable by company members" ON public.company_users
    FOR SELECT TO authenticated
    USING (
        company_id IN (
            SELECT company_id FROM public.company_users 
            WHERE user_id = (SELECT id FROM public.profiles WHERE id = auth.uid())
            AND is_active = TRUE
        )
    );

-- Company Users: Authenticated users can create their own record or admins can invite
CREATE POLICY "Company users insertable by admins" ON public.company_users
    FOR INSERT TO authenticated
    WITH CHECK (
        -- Allow if user is creating their own record (registering a company)
        (user_id = (SELECT id FROM public.profiles WHERE id = auth.uid()))
        OR
        -- Or if user is admin/owner of the company (inviting others)
        company_id IN (
            SELECT company_id FROM public.company_users 
            WHERE user_id = (SELECT id FROM public.profiles WHERE id = auth.uid())
            AND role IN ('owner', 'admin') 
            AND is_active = TRUE
        )
    );

-- Company Users: Only admins can update (with WITH CHECK)
CREATE POLICY "Company users updatable by admins" ON public.company_users
    FOR UPDATE TO authenticated
    USING (
        company_id IN (
            SELECT company_id FROM public.company_users 
            WHERE user_id = (SELECT id FROM public.profiles WHERE id = auth.uid())
            AND role IN ('owner', 'admin') 
            AND is_active = TRUE
        )
    )
    WITH CHECK (
        company_id IN (
            SELECT company_id FROM public.company_users 
            WHERE user_id = (SELECT id FROM public.profiles WHERE id = auth.uid())
            AND role IN ('owner', 'admin') 
            AND is_active = TRUE
        )
    );

-- Company Users: Only owners can delete
CREATE POLICY "Company users deletable by admins" ON public.company_users
    FOR DELETE TO authenticated
    USING (
        company_id IN (
            SELECT company_id FROM public.company_users 
            WHERE user_id = (SELECT id FROM public.profiles WHERE id = auth.uid())
            AND role = 'owner' 
            AND is_active = TRUE
        )
    );

-- ============================================================================
-- STEP 4: HELPER FUNCTIONS (with proper security hardening)
-- ============================================================================

-- Function to get user's current company ID from profiles
-- SECURITY: SET search_path = '' prevents search_path injection
CREATE OR REPLACE FUNCTION public.get_current_company_id()
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    RETURN (
        SELECT current_company_id 
        FROM public.profiles 
        WHERE id = auth.uid()
    );
END;
$$;

-- Revoke public access and grant only to authenticated
REVOKE ALL ON FUNCTION public.get_current_company_id() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_current_company_id() TO authenticated;

-- Function to check if user is member of a company
CREATE OR REPLACE FUNCTION public.is_company_member(target_company_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM public.company_users cu
        JOIN public.profiles p ON p.id = cu.user_id
        WHERE cu.company_id = target_company_id 
        AND p.id = auth.uid()
        AND cu.is_active = TRUE
    );
END;
$$;

REVOKE ALL ON FUNCTION public.is_company_member(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_company_member(UUID) TO authenticated;

-- Function to get user's role in a company
CREATE OR REPLACE FUNCTION public.get_user_role(target_company_id UUID)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    RETURN (
        SELECT cu.role FROM public.company_users cu
        JOIN public.profiles p ON p.id = cu.user_id
        WHERE cu.company_id = target_company_id 
        AND p.id = auth.uid()
        AND cu.is_active = TRUE
        LIMIT 1
    );
END;
$$;

REVOKE ALL ON FUNCTION public.get_user_role(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_user_role(UUID) TO authenticated;

-- ============================================================================
-- STEP 5: ATOMIC COMPANY REGISTRATION FUNCTION
-- ============================================================================
-- Uses EXISTING schema columns: name, legal_name, tax_id, country, etc.
-- NOTE: company_users.user_id references profiles(id), not auth.users(id)

CREATE OR REPLACE FUNCTION public.register_company(
    p_user_id UUID,
    p_name TEXT,
    p_legal_name TEXT DEFAULT NULL,
    p_tax_id TEXT DEFAULT NULL,
    p_country TEXT DEFAULT 'ES',
    p_address TEXT DEFAULT NULL,
    p_city TEXT DEFAULT NULL,
    p_postal_code TEXT DEFAULT NULL,
    p_email TEXT DEFAULT NULL,
    p_phone TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_company_id UUID;
    v_company JSONB;
    v_profile_exists BOOLEAN;
BEGIN
    -- Verify user has a profile (required for company_users FK)
    SELECT EXISTS(SELECT 1 FROM public.profiles WHERE id = p_user_id) INTO v_profile_exists;
    IF NOT v_profile_exists THEN
        RAISE EXCEPTION 'User profile does not exist. Please complete profile setup first.';
    END IF;

    -- Check if tax_id already exists for this country (if provided)
    IF p_tax_id IS NOT NULL AND p_tax_id != '' THEN
        IF EXISTS (
            SELECT 1 FROM public.companies 
            WHERE country = p_country 
            AND tax_id = p_tax_id
        ) THEN
            RAISE EXCEPTION 'Company with this tax ID already exists in %', p_country;
        END IF;
    END IF;

    -- Create company using EXISTING schema columns
    INSERT INTO public.companies (
        name, 
        legal_name, 
        tax_id, 
        country,
        address, 
        city, 
        postal_code, 
        email, 
        phone,
        subscription_plan,
        subscription_status
    ) VALUES (
        p_name, 
        p_legal_name, 
        p_tax_id, 
        p_country,
        p_address, 
        p_city, 
        p_postal_code, 
        p_email, 
        p_phone,
        'free',
        'active'
    )
    RETURNING id INTO v_company_id;

    -- Create company_user relationship (user_id references profiles.id)
    INSERT INTO public.company_users (
        company_id, 
        user_id, 
        role, 
        is_active,
        joined_at
    ) VALUES (
        v_company_id, 
        p_user_id, 
        'owner', 
        TRUE,
        NOW()
    );

    -- Update profile with current company
    UPDATE public.profiles 
    SET current_company_id = v_company_id, updated_at = NOW()
    WHERE id = p_user_id;

    -- Return the created company
    SELECT to_jsonb(c.*) INTO v_company
    FROM public.companies c
    WHERE c.id = v_company_id;

    RETURN v_company;
END;
$$;

REVOKE ALL ON FUNCTION public.register_company(UUID, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.register_company(UUID, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT) TO authenticated;

-- ============================================================================
-- STEP 6: TRIGGERS FOR UPDATED_AT (idempotent)
-- ============================================================================
-- Note: The trigger function likely already exists from 00001 migration

CREATE OR REPLACE FUNCTION public.update_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;

-- Create triggers if they don't exist
DROP TRIGGER IF EXISTS companies_updated_at ON public.companies;
CREATE TRIGGER companies_updated_at
    BEFORE UPDATE ON public.companies
    FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();

DROP TRIGGER IF EXISTS company_users_updated_at ON public.company_users;
CREATE TRIGGER company_users_updated_at
    BEFORE UPDATE ON public.company_users
    FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();

DROP TRIGGER IF EXISTS profiles_updated_at ON public.profiles;
CREATE TRIGGER profiles_updated_at
    BEFORE UPDATE ON public.profiles
    FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();

-- ============================================================================
-- STEP 7: RLS TEMPLATE FOR DATA TABLES (just documentation)
-- ============================================================================
-- Use this pattern for any table that needs company isolation:
/*
CREATE TABLE public.your_table (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    -- ... other columns
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_your_table_company ON public.your_table(company_id);
ALTER TABLE public.your_table ENABLE ROW LEVEL SECURITY;

CREATE POLICY "your_table viewable by company members" ON public.your_table
    FOR SELECT TO authenticated
    USING (public.is_company_member(company_id));

CREATE POLICY "your_table insertable by company members" ON public.your_table
    FOR INSERT TO authenticated
    WITH CHECK (public.is_company_member(company_id));
*/

-- ============================================================================
-- VERIFICATION QUERIES
-- ============================================================================

-- Check tables exist
SELECT table_name FROM information_schema.tables 
WHERE table_schema = 'public' AND table_name IN ('companies', 'company_users', 'profiles');

-- Check RLS is enabled
SELECT tablename, rowsecurity FROM pg_tables 
WHERE schemaname = 'public' AND tablename IN ('companies', 'company_users');

-- Check policies exist
SELECT tablename, policyname FROM pg_policies 
WHERE schemaname = 'public' AND tablename IN ('companies', 'company_users');

-- Check functions exist
SELECT routine_name FROM information_schema.routines 
WHERE routine_schema = 'public' 
AND routine_name IN ('register_company', 'is_company_member', 'get_user_role', 'get_current_company_id');

-- Check existing columns in companies table
SELECT column_name, data_type FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'companies'
ORDER BY ordinal_position;

-- ============================================================================
-- DONE!
-- ============================================================================
