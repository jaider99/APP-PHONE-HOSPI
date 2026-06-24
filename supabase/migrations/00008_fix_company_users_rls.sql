-- ============================================================================
-- FIX: Infinite recursion in company_users SELECT policy
-- The old policy queried company_users FROM company_users, causing PostgreSQL
-- error 42P17 "infinite recursion detected in policy for relation company_users"
-- ============================================================================

-- Drop ALL potentially recursive company_users policies
DROP POLICY IF EXISTS "Company users viewable by company members" ON public.company_users;
DROP POLICY IF EXISTS "Users can view company members"            ON public.company_users;
DROP POLICY IF EXISTS "Company users insertable by admins"        ON public.company_users;
DROP POLICY IF EXISTS "Admins can add company members"            ON public.company_users;
DROP POLICY IF EXISTS "Company users updatable by admins"         ON public.company_users;
DROP POLICY IF EXISTS "Admins can update company members"         ON public.company_users;
DROP POLICY IF EXISTS "Company users deletable by admins"         ON public.company_users;
DROP POLICY IF EXISTS "Admins can remove company members"         ON public.company_users;

-- ============================================================================
-- NON-RECURSIVE POLICIES using auth.uid() directly
-- ============================================================================

-- SELECT: Users can see their own membership rows
-- For viewing OTHER members of the same company, use the SECURITY DEFINER function
CREATE POLICY "Users can view own memberships" ON public.company_users
    FOR SELECT TO authenticated
    USING (user_id = auth.uid());

-- SELECT: Users can also see other members of companies they belong to
-- Uses SECURITY DEFINER function to avoid recursion
CREATE POLICY "Users can view company co-members" ON public.company_users
    FOR SELECT TO authenticated
    USING (
        (SELECT user_belongs_to_company(company_id))
    );

-- INSERT: Users can create their own membership (registration) OR admins can invite
CREATE POLICY "Users can join or admins can invite" ON public.company_users
    FOR INSERT TO authenticated
    WITH CHECK (
        user_id = auth.uid()
        OR (SELECT user_is_company_admin(company_id))
    );

-- UPDATE: Only admins/owners can update memberships
CREATE POLICY "Admins can update memberships" ON public.company_users
    FOR UPDATE TO authenticated
    USING ((SELECT user_is_company_admin(company_id)))
    WITH CHECK ((SELECT user_is_company_admin(company_id)));

-- DELETE: Only admins/owners can remove members (but not owners)
CREATE POLICY "Admins can remove members" ON public.company_users
    FOR DELETE TO authenticated
    USING (
        (SELECT user_is_company_admin(company_id))
        AND role != 'owner'
    );
