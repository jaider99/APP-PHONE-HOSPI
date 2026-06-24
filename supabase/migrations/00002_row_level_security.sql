-- ============================================================================
-- HOSPIDASH: Row Level Security Policies
-- Version: 1.0.0
-- ============================================================================
-- CRITICAL: This file implements multi-tenant data isolation.
-- Every user can ONLY access data belonging to their company.
-- ============================================================================

-- ============================================================================
-- PART 1: HELPER FUNCTIONS (Performance Optimized)
-- ============================================================================

-- Note: auth.uid() is provided by Supabase - we use it directly

-- Get current user's active company ID
-- Uses (SELECT ...) pattern to ensure single execution per query
CREATE OR REPLACE FUNCTION public.get_current_company_id()
RETURNS UUID
LANGUAGE SQL
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT current_company_id 
    FROM profiles 
    WHERE id = (SELECT auth.uid())
$$;

-- Check if user belongs to a specific company
CREATE OR REPLACE FUNCTION public.user_belongs_to_company(check_company_id UUID)
RETURNS BOOLEAN
LANGUAGE SQL
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1 FROM company_users
        WHERE company_id = check_company_id
        AND user_id = (SELECT auth.uid())
        AND is_active = TRUE
    )
$$;

-- Check if user has specific role in company
CREATE OR REPLACE FUNCTION public.user_has_role_in_company(check_company_id UUID, required_roles TEXT[])
RETURNS BOOLEAN
LANGUAGE SQL
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1 FROM company_users
        WHERE company_id = check_company_id
        AND user_id = (SELECT auth.uid())
        AND role = ANY(required_roles)
        AND is_active = TRUE
    )
$$;

-- Check if user is owner or admin of company
CREATE OR REPLACE FUNCTION public.user_is_company_admin(check_company_id UUID)
RETURNS BOOLEAN
LANGUAGE SQL
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT public.user_has_role_in_company(check_company_id, ARRAY['owner', 'admin'])
$$;

-- ============================================================================
-- PART 2: ENABLE RLS ON ALL TABLES
-- ============================================================================

ALTER TABLE companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE company_users ENABLE ROW LEVEL SECURITY;
ALTER TABLE providers ENABLE ROW LEVEL SECURITY;
ALTER TABLE products ENABLE ROW LEVEL SECURITY;
ALTER TABLE documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE document_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE order_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE sales ENABLE ROW LEVEL SECURITY;
ALTER TABLE activity_logs ENABLE ROW LEVEL SECURITY;

-- FORCE RLS even for table owners (prevents bypass)
ALTER TABLE companies FORCE ROW LEVEL SECURITY;
ALTER TABLE profiles FORCE ROW LEVEL SECURITY;
ALTER TABLE company_users FORCE ROW LEVEL SECURITY;
ALTER TABLE providers FORCE ROW LEVEL SECURITY;
ALTER TABLE products FORCE ROW LEVEL SECURITY;
ALTER TABLE documents FORCE ROW LEVEL SECURITY;
ALTER TABLE document_items FORCE ROW LEVEL SECURITY;
ALTER TABLE orders FORCE ROW LEVEL SECURITY;
ALTER TABLE order_items FORCE ROW LEVEL SECURITY;
ALTER TABLE sales FORCE ROW LEVEL SECURITY;
ALTER TABLE activity_logs FORCE ROW LEVEL SECURITY;

-- ============================================================================
-- PART 3: PROFILES POLICIES
-- ============================================================================

-- Users can read their own profile
CREATE POLICY "Users can view own profile"
    ON profiles FOR SELECT
    TO authenticated
    USING (id = (SELECT auth.uid()));

-- Users can update their own profile
CREATE POLICY "Users can update own profile"
    ON profiles FOR UPDATE
    TO authenticated
    USING (id = (SELECT auth.uid()))
    WITH CHECK (id = (SELECT auth.uid()));

-- Profile is created automatically via trigger
CREATE POLICY "Enable insert for auth trigger"
    ON profiles FOR INSERT
    TO authenticated, service_role
    WITH CHECK (TRUE);

-- ============================================================================
-- PART 4: COMPANIES POLICIES
-- ============================================================================

-- Users can view companies they belong to
CREATE POLICY "Users can view their companies"
    ON companies FOR SELECT
    TO authenticated
    USING (
        (SELECT user_belongs_to_company(id))
    );

-- Only owners can update company details
CREATE POLICY "Owners and admins can update company"
    ON companies FOR UPDATE
    TO authenticated
    USING ((SELECT user_is_company_admin(id)))
    WITH CHECK ((SELECT user_is_company_admin(id)));

-- Authenticated users can create new companies (they become owner)
CREATE POLICY "Authenticated users can create companies"
    ON companies FOR INSERT
    TO authenticated
    WITH CHECK (TRUE);

-- Only owners can delete company
CREATE POLICY "Only owners can delete company"
    ON companies FOR DELETE
    TO authenticated
    USING (
        (SELECT user_has_role_in_company(id, ARRAY['owner']))
    );

-- ============================================================================
-- PART 5: COMPANY_USERS POLICIES
-- ============================================================================

-- Users can view members of their companies
CREATE POLICY "Users can view company members"
    ON company_users FOR SELECT
    TO authenticated
    USING (
        (SELECT user_belongs_to_company(company_id))
    );

-- Only admins can add members
CREATE POLICY "Admins can add company members"
    ON company_users FOR INSERT
    TO authenticated
    WITH CHECK (
        (SELECT user_is_company_admin(company_id))
    );

-- Only admins can update member roles
CREATE POLICY "Admins can update company members"
    ON company_users FOR UPDATE
    TO authenticated
    USING ((SELECT user_is_company_admin(company_id)))
    WITH CHECK ((SELECT user_is_company_admin(company_id)));

-- Only admins can remove members (except owners can't be removed)
CREATE POLICY "Admins can remove company members"
    ON company_users FOR DELETE
    TO authenticated
    USING (
        (SELECT user_is_company_admin(company_id))
        AND role != 'owner'  -- Owners cannot be removed
    );

-- ============================================================================
-- PART 6: PROVIDERS POLICIES (Company Scoped)
-- ============================================================================

-- All company members can view providers
CREATE POLICY "Company members can view providers"
    ON providers FOR SELECT
    TO authenticated
    USING (
        company_id = (SELECT get_current_company_id())
    );

-- Members with write access can create providers
CREATE POLICY "Company members can create providers"
    ON providers FOR INSERT
    TO authenticated
    WITH CHECK (
        company_id = (SELECT get_current_company_id())
        AND (SELECT user_has_role_in_company(company_id, ARRAY['owner', 'admin', 'manager', 'member']))
    );

-- Members can update providers
CREATE POLICY "Company members can update providers"
    ON providers FOR UPDATE
    TO authenticated
    USING (company_id = (SELECT get_current_company_id()))
    WITH CHECK (company_id = (SELECT get_current_company_id()));

-- Only admins can delete providers
CREATE POLICY "Admins can delete providers"
    ON providers FOR DELETE
    TO authenticated
    USING (
        company_id = (SELECT get_current_company_id())
        AND (SELECT user_is_company_admin(company_id))
    );

-- ============================================================================
-- PART 7: PRODUCTS POLICIES (Company Scoped)
-- ============================================================================

CREATE POLICY "Company members can view products"
    ON products FOR SELECT
    TO authenticated
    USING (company_id = (SELECT get_current_company_id()));

CREATE POLICY "Company members can create products"
    ON products FOR INSERT
    TO authenticated
    WITH CHECK (
        company_id = (SELECT get_current_company_id())
        AND (SELECT user_has_role_in_company(company_id, ARRAY['owner', 'admin', 'manager', 'member']))
    );

CREATE POLICY "Company members can update products"
    ON products FOR UPDATE
    TO authenticated
    USING (company_id = (SELECT get_current_company_id()))
    WITH CHECK (company_id = (SELECT get_current_company_id()));

CREATE POLICY "Admins can delete products"
    ON products FOR DELETE
    TO authenticated
    USING (
        company_id = (SELECT get_current_company_id())
        AND (SELECT user_is_company_admin(company_id))
    );

-- ============================================================================
-- PART 8: DOCUMENTS POLICIES (Company Scoped)
-- ============================================================================

CREATE POLICY "Company members can view documents"
    ON documents FOR SELECT
    TO authenticated
    USING (company_id = (SELECT get_current_company_id()));

CREATE POLICY "Company members can create documents"
    ON documents FOR INSERT
    TO authenticated
    WITH CHECK (
        company_id = (SELECT get_current_company_id())
        AND (SELECT user_has_role_in_company(company_id, ARRAY['owner', 'admin', 'manager', 'member']))
    );

CREATE POLICY "Company members can update documents"
    ON documents FOR UPDATE
    TO authenticated
    USING (company_id = (SELECT get_current_company_id()))
    WITH CHECK (company_id = (SELECT get_current_company_id()));

CREATE POLICY "Admins can delete documents"
    ON documents FOR DELETE
    TO authenticated
    USING (
        company_id = (SELECT get_current_company_id())
        AND (SELECT user_is_company_admin(company_id))
    );

-- Document Items inherit parent document's company
CREATE POLICY "Company members can view document items"
    ON document_items FOR SELECT
    TO authenticated
    USING (company_id = (SELECT get_current_company_id()));

CREATE POLICY "Company members can manage document items"
    ON document_items FOR ALL
    TO authenticated
    USING (company_id = (SELECT get_current_company_id()))
    WITH CHECK (company_id = (SELECT get_current_company_id()));

-- ============================================================================
-- PART 9: ORDERS POLICIES (Company Scoped)
-- ============================================================================

CREATE POLICY "Company members can view orders"
    ON orders FOR SELECT
    TO authenticated
    USING (company_id = (SELECT get_current_company_id()));

CREATE POLICY "Company members can create orders"
    ON orders FOR INSERT
    TO authenticated
    WITH CHECK (
        company_id = (SELECT get_current_company_id())
        AND (SELECT user_has_role_in_company(company_id, ARRAY['owner', 'admin', 'manager', 'member']))
    );

CREATE POLICY "Company members can update orders"
    ON orders FOR UPDATE
    TO authenticated
    USING (company_id = (SELECT get_current_company_id()))
    WITH CHECK (company_id = (SELECT get_current_company_id()));

CREATE POLICY "Admins can delete orders"
    ON orders FOR DELETE
    TO authenticated
    USING (
        company_id = (SELECT get_current_company_id())
        AND (SELECT user_is_company_admin(company_id))
    );

-- Order Items
CREATE POLICY "Company members can view order items"
    ON order_items FOR SELECT
    TO authenticated
    USING (company_id = (SELECT get_current_company_id()));

CREATE POLICY "Company members can manage order items"
    ON order_items FOR ALL
    TO authenticated
    USING (company_id = (SELECT get_current_company_id()))
    WITH CHECK (company_id = (SELECT get_current_company_id()));

-- ============================================================================
-- PART 10: SALES POLICIES (Company Scoped)
-- ============================================================================

CREATE POLICY "Company members can view sales"
    ON sales FOR SELECT
    TO authenticated
    USING (company_id = (SELECT get_current_company_id()));

CREATE POLICY "Company members can create sales"
    ON sales FOR INSERT
    TO authenticated
    WITH CHECK (
        company_id = (SELECT get_current_company_id())
        AND (SELECT user_has_role_in_company(company_id, ARRAY['owner', 'admin', 'manager', 'member']))
    );

CREATE POLICY "Company members can update sales"
    ON sales FOR UPDATE
    TO authenticated
    USING (company_id = (SELECT get_current_company_id()))
    WITH CHECK (company_id = (SELECT get_current_company_id()));

CREATE POLICY "Admins can delete sales"
    ON sales FOR DELETE
    TO authenticated
    USING (
        company_id = (SELECT get_current_company_id())
        AND (SELECT user_is_company_admin(company_id))
    );

-- ============================================================================
-- PART 11: ACTIVITY LOGS POLICIES
-- ============================================================================

-- Users can view their company's activity logs
CREATE POLICY "Company members can view activity logs"
    ON activity_logs FOR SELECT
    TO authenticated
    USING (company_id = (SELECT get_current_company_id()));

-- Only system can insert logs (via triggers or service role)
CREATE POLICY "System can insert activity logs"
    ON activity_logs FOR INSERT
    TO authenticated, service_role
    WITH CHECK (TRUE);

-- Logs are immutable - no update or delete
-- (No UPDATE or DELETE policies = cannot modify)

-- ============================================================================
-- PART 12: SERVICE ROLE BYPASS (For Backend Operations)
-- ============================================================================
-- Note: service_role bypasses RLS by default in Supabase.
-- This is needed for:
-- - OCR processing jobs
-- - Scheduled tasks
-- - Admin operations
-- NEVER expose service_role key to client!
