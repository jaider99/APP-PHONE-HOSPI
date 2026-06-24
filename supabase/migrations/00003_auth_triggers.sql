-- ============================================================================
-- HOSPIDASH: Auth Triggers & User Management
-- Version: 1.0.0
-- ============================================================================
-- Handles automatic profile creation, company setup, and user-company linking
-- ============================================================================

-- ============================================================================
-- PART 1: AUTO-CREATE PROFILE ON SIGNUP
-- ============================================================================

-- Function: Create profile when user signs up
CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    INSERT INTO profiles (id, email, full_name, avatar_url)
    VALUES (
        NEW.id,
        NEW.email,
        COALESCE(NEW.raw_user_meta_data->>'full_name', split_part(NEW.email, '@', 1)),
        NEW.raw_user_meta_data->>'avatar_url'
    );
    RETURN NEW;
END;
$$;

-- Trigger: Execute after user creation
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW
    EXECUTE FUNCTION handle_new_user();

-- ============================================================================
-- PART 2: COMPANY CREATION WITH OWNER
-- ============================================================================

-- Function: Create a new company and set user as owner
CREATE OR REPLACE FUNCTION create_company_with_owner(
    p_company_name TEXT,
    p_legal_name TEXT DEFAULT NULL,
    p_tax_id TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_company_id UUID;
    v_user_id UUID;
BEGIN
    v_user_id := auth.uid();
    
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'User must be authenticated';
    END IF;
    
    -- Create the company
    INSERT INTO companies (name, legal_name, tax_id)
    VALUES (p_company_name, p_legal_name, p_tax_id)
    RETURNING id INTO v_company_id;
    
    -- Add user as owner
    INSERT INTO company_users (company_id, user_id, role, joined_at)
    VALUES (v_company_id, v_user_id, 'owner', NOW());
    
    -- Set as user's current company
    UPDATE profiles
    SET current_company_id = v_company_id
    WHERE id = v_user_id;
    
    RETURN v_company_id;
END;
$$;

-- ============================================================================
-- PART 3: SWITCH CURRENT COMPANY
-- ============================================================================

-- Function: Switch user's active company
CREATE OR REPLACE FUNCTION switch_company(p_company_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id UUID;
    v_is_member BOOLEAN;
BEGIN
    v_user_id := auth.uid();
    
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'User must be authenticated';
    END IF;
    
    -- Check if user belongs to this company
    SELECT EXISTS (
        SELECT 1 FROM company_users
        WHERE company_id = p_company_id
        AND user_id = v_user_id
        AND is_active = TRUE
    ) INTO v_is_member;
    
    IF NOT v_is_member THEN
        RAISE EXCEPTION 'User is not a member of this company';
    END IF;
    
    -- Update current company
    UPDATE profiles
    SET current_company_id = p_company_id
    WHERE id = v_user_id;
    
    RETURN TRUE;
END;
$$;

-- ============================================================================
-- PART 4: INVITE USER TO COMPANY
-- ============================================================================

-- Function: Invite a user to join a company
CREATE OR REPLACE FUNCTION invite_user_to_company(
    p_email TEXT,
    p_company_id UUID,
    p_role TEXT DEFAULT 'member'
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_inviter_id UUID;
    v_invitee_id UUID;
    v_company_user_id UUID;
BEGIN
    v_inviter_id := auth.uid();
    
    -- Check inviter has permission
    IF NOT user_is_company_admin(p_company_id) THEN
        RAISE EXCEPTION 'Only admins can invite users';
    END IF;
    
    -- Find or create the user profile
    SELECT id INTO v_invitee_id
    FROM profiles
    WHERE email = p_email;
    
    -- If user doesn't exist, they'll need to sign up first
    IF v_invitee_id IS NULL THEN
        -- Return NULL to indicate invite email should be sent
        RETURN NULL;
    END IF;
    
    -- Check if already a member
    IF EXISTS (
        SELECT 1 FROM company_users
        WHERE company_id = p_company_id AND user_id = v_invitee_id
    ) THEN
        RAISE EXCEPTION 'User is already a member of this company';
    END IF;
    
    -- Add user to company
    INSERT INTO company_users (company_id, user_id, role, invited_by, joined_at)
    VALUES (p_company_id, v_invitee_id, p_role, v_inviter_id, NOW())
    RETURNING id INTO v_company_user_id;
    
    RETURN v_company_user_id;
END;
$$;

-- ============================================================================
-- PART 5: GET USER'S COMPANIES
-- ============================================================================

-- Function: Get all companies a user belongs to
CREATE OR REPLACE FUNCTION get_user_companies()
RETURNS TABLE (
    company_id UUID,
    company_name TEXT,
    role TEXT,
    is_current BOOLEAN
)
LANGUAGE SQL
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT 
        c.id AS company_id,
        c.name AS company_name,
        cu.role,
        c.id = p.current_company_id AS is_current
    FROM companies c
    INNER JOIN company_users cu ON cu.company_id = c.id
    INNER JOIN profiles p ON p.id = cu.user_id
    WHERE cu.user_id = (SELECT auth.uid())
    AND cu.is_active = TRUE
    ORDER BY is_current DESC, c.name;
$$;

-- ============================================================================
-- PART 6: GET CURRENT USER CONTEXT
-- ============================================================================

-- Function: Get current user's full context
CREATE OR REPLACE FUNCTION get_user_context()
RETURNS JSON
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_result JSON;
BEGIN
    SELECT json_build_object(
        'user_id', p.id,
        'email', p.email,
        'full_name', p.full_name,
        'avatar_url', p.avatar_url,
        'current_company_id', p.current_company_id,
        'current_company_name', c.name,
        'role', cu.role,
        'permissions', cu.permissions
    ) INTO v_result
    FROM profiles p
    LEFT JOIN companies c ON c.id = p.current_company_id
    LEFT JOIN company_users cu ON cu.company_id = p.current_company_id AND cu.user_id = p.id
    WHERE p.id = (SELECT auth.uid());
    
    RETURN v_result;
END;
$$;

-- ============================================================================
-- PART 7: ACTIVITY LOGGING TRIGGER
-- ============================================================================

-- Function: Automatically log changes to important tables
CREATE OR REPLACE FUNCTION log_activity()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    -- Only log for company-scoped tables
    IF TG_OP = 'INSERT' THEN
        INSERT INTO activity_logs (company_id, user_id, action, entity_type, entity_id, new_data)
        VALUES (
            NEW.company_id,
            (SELECT auth.uid()),
            'create',
            TG_TABLE_NAME,
            NEW.id,
            to_jsonb(NEW)
        );
    ELSIF TG_OP = 'UPDATE' THEN
        INSERT INTO activity_logs (company_id, user_id, action, entity_type, entity_id, old_data, new_data)
        VALUES (
            NEW.company_id,
            (SELECT auth.uid()),
            'update',
            TG_TABLE_NAME,
            NEW.id,
            to_jsonb(OLD),
            to_jsonb(NEW)
        );
    ELSIF TG_OP = 'DELETE' THEN
        INSERT INTO activity_logs (company_id, user_id, action, entity_type, entity_id, old_data)
        VALUES (
            OLD.company_id,
            (SELECT auth.uid()),
            'delete',
            TG_TABLE_NAME,
            OLD.id,
            to_jsonb(OLD)
        );
    END IF;
    
    RETURN COALESCE(NEW, OLD);
END;
$$;

-- Apply activity logging to key tables
CREATE TRIGGER log_documents_activity
    AFTER INSERT OR UPDATE OR DELETE ON documents
    FOR EACH ROW EXECUTE FUNCTION log_activity();

CREATE TRIGGER log_orders_activity
    AFTER INSERT OR UPDATE OR DELETE ON orders
    FOR EACH ROW EXECUTE FUNCTION log_activity();

CREATE TRIGGER log_providers_activity
    AFTER INSERT OR UPDATE OR DELETE ON providers
    FOR EACH ROW EXECUTE FUNCTION log_activity();

-- ============================================================================
-- PART 8: GRANT EXECUTE ON FUNCTIONS
-- ============================================================================

GRANT EXECUTE ON FUNCTION create_company_with_owner TO authenticated;
GRANT EXECUTE ON FUNCTION switch_company TO authenticated;
GRANT EXECUTE ON FUNCTION invite_user_to_company TO authenticated;
GRANT EXECUTE ON FUNCTION get_user_companies TO authenticated;
GRANT EXECUTE ON FUNCTION get_user_context TO authenticated;
GRANT EXECUTE ON FUNCTION get_current_company_id TO authenticated;
GRANT EXECUTE ON FUNCTION user_belongs_to_company TO authenticated;
GRANT EXECUTE ON FUNCTION user_has_role_in_company TO authenticated;
GRANT EXECUTE ON FUNCTION user_is_company_admin TO authenticated;
