-- ============================================================================
-- HOSPIDASH: Secure Registration RPC Session Fix
-- Date: 2026-06-15
--
-- Fixes owner/manager registration after email-confirmation signup by requiring
-- authenticated JWT context and deriving user ownership from auth.uid().
-- ============================================================================

BEGIN;

-- Pending manager self-requests need an audit path before they are active
-- company members. Keep the exception narrow: only the target user may record
-- the self access-request event for their own pending company_users row.
CREATE OR REPLACE FUNCTION public.record_security_audit_event(
  p_company_id uuid,
  p_action text,
  p_entity_type text,
  p_entity_id uuid DEFAULT NULL,
  p_outcome text DEFAULT 'success',
  p_correlation_id text DEFAULT NULL,
  p_metadata jsonb DEFAULT '{}'::jsonb
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_log_id uuid;
  v_actor_id uuid := auth.uid();
  v_role text := coalesce(current_setting('role', true), '');
  v_is_self_pending_member boolean := false;
BEGIN
  IF p_outcome NOT IN ('success', 'failure', 'denied') THEN
    RAISE EXCEPTION 'Invalid audit outcome';
  END IF;

  IF v_role NOT IN ('postgres', 'service_role', 'supabase_admin') THEN
    IF v_actor_id IS NULL THEN
      RAISE EXCEPTION 'Unauthorized';
    END IF;

    IF NOT (p_company_id = ANY(public.user_company_ids())) THEN
      SELECT EXISTS (
        SELECT 1
        FROM public.company_users cu
        WHERE cu.company_id = p_company_id
          AND cu.user_id = v_actor_id
          AND cu.is_active = false
          AND p_action = 'security.member.access_request'
          AND p_entity_type = 'company_user'
          AND p_metadata->>'target_user_id' = v_actor_id::text
      ) INTO v_is_self_pending_member;

      IF NOT v_is_self_pending_member THEN
        RAISE EXCEPTION 'Unauthorized';
      END IF;
    END IF;
  END IF;

  INSERT INTO public.activity_logs (
    company_id,
    user_id,
    action,
    entity_type,
    entity_id,
    outcome,
    correlation_id,
    metadata,
    new_data
  ) VALUES (
    p_company_id,
    v_actor_id,
    p_action,
    p_entity_type,
    p_entity_id,
    p_outcome,
    NULLIF(left(coalesce(p_correlation_id, ''), 128), ''),
    public.redact_audit_payload(coalesce(p_metadata, '{}'::jsonb)),
    public.redact_audit_payload(coalesce(p_metadata, '{}'::jsonb))
  )
  RETURNING id INTO v_log_id;

  RETURN v_log_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.audit_company_sensitive_changes()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_action text;
  v_metadata jsonb;
BEGIN
  IF TG_TABLE_NAME = 'company_users' THEN
    IF TG_OP = 'INSERT' THEN
      IF NEW.user_id = auth.uid() AND NEW.is_active = false THEN
        v_action := 'security.member.access_request';
      ELSE
        v_action := 'security.member.invite';
      END IF;
      v_metadata := jsonb_build_object('role', NEW.role, 'target_user_id', NEW.user_id);
    ELSIF TG_OP = 'UPDATE' AND OLD.role IS DISTINCT FROM NEW.role THEN
      v_action := 'security.member.role_change';
      v_metadata := jsonb_build_object('old_role', OLD.role, 'new_role', NEW.role, 'target_user_id', NEW.user_id);
    ELSIF TG_OP = 'UPDATE' AND OLD.is_active IS DISTINCT FROM NEW.is_active AND NEW.is_active = false THEN
      v_action := 'security.member.remove';
      v_metadata := jsonb_build_object('role', OLD.role, 'target_user_id', OLD.user_id);
    ELSE
      RETURN NEW;
    END IF;

    PERFORM public.record_security_audit_event(NEW.company_id, v_action, 'company_user', NEW.id, 'success', NULL, v_metadata);
    RETURN NEW;
  END IF;

  IF TG_TABLE_NAME = 'companies' AND TG_OP = 'UPDATE' THEN
    IF to_jsonb(OLD) = to_jsonb(NEW) THEN
      RETURN NEW;
    END IF;

    v_metadata := jsonb_build_object(
      'changed_fields', (
        SELECT jsonb_agg(key ORDER BY key)
        FROM jsonb_each(to_jsonb(NEW)) AS n(key, value)
        WHERE n.value IS DISTINCT FROM to_jsonb(OLD)->n.key
          AND n.key NOT IN ('updated_at')
      )
    );

    IF v_metadata->'changed_fields' IS NOT NULL THEN
      PERFORM public.record_security_audit_event(NEW.id, 'security.company.settings_change', 'company', NEW.id, 'success', NULL, v_metadata);
    END IF;
    RETURN NEW;
  END IF;

  RETURN coalesce(NEW, OLD);
END;
$$;

DROP FUNCTION IF EXISTS public.create_company_with_owner(text, text, text);
DROP FUNCTION IF EXISTS public.create_company_with_owner(uuid, text, text, text, text, text, text, text, text, text, text);
DROP FUNCTION IF EXISTS public.create_company_with_owner(text, text, text, text, text, text, text, text, text, text);

CREATE OR REPLACE FUNCTION public.create_company_with_owner(
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
SET search_path = public, auth
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_company_id uuid;
  v_invite_code text;
  v_result jsonb;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  SELECT c.id, c.invite_code
  INTO v_company_id, v_invite_code
  FROM public.companies c
  WHERE c.tax_id = p_tax_id
    AND c.owner_id = v_user_id
  LIMIT 1;

  IF v_company_id IS NOT NULL THEN
    INSERT INTO public.company_users (company_id, user_id, role, is_active, joined_at)
    VALUES (v_company_id, v_user_id, 'owner', true, now())
    ON CONFLICT (company_id, user_id) DO UPDATE SET
      role = 'owner',
      is_active = true,
      joined_at = coalesce(public.company_users.joined_at, now()),
      updated_at = now();

    INSERT INTO public.user_preferences (user_id, active_company_id)
    VALUES (v_user_id, v_company_id)
    ON CONFLICT (user_id) DO UPDATE SET
      active_company_id = excluded.active_company_id,
      updated_at = now();

    INSERT INTO public.profiles (id, email, full_name, current_company_id)
    VALUES (v_user_id, NULLIF(trim(p_email), ''), NULLIF(trim(p_full_name), ''), v_company_id)
    ON CONFLICT (id) DO UPDATE SET
      email = coalesce(NULLIF(trim(EXCLUDED.email), ''), public.profiles.email),
      full_name = coalesce(NULLIF(trim(EXCLUDED.full_name), ''), public.profiles.full_name),
      current_company_id = v_company_id,
      updated_at = now();

    RETURN jsonb_build_object(
      'company_id', v_company_id,
      'company_name', p_company_name,
      'invite_code', v_invite_code,
      'role', 'owner'
    );
  END IF;

  IF EXISTS (SELECT 1 FROM public.companies WHERE tax_id = p_tax_id) THEN
    RAISE EXCEPTION 'DUPLICATE_TAX_ID: A business with tax ID % already exists', p_tax_id;
  END IF;

  v_invite_code := upper(substring(gen_random_uuid()::text, 1, 8));

  INSERT INTO public.companies (
    name, legal_name, tax_id, city, country, currency, timezone,
    business_type, owner_id, invite_code, is_active
  ) VALUES (
    p_company_name, p_legal_name, p_tax_id, p_city, p_country, p_currency,
    p_timezone, p_business_type, v_user_id, v_invite_code, true
  )
  RETURNING id INTO v_company_id;

  INSERT INTO public.company_users (company_id, user_id, role, is_active, joined_at)
  VALUES (v_company_id, v_user_id, 'owner', true, now());

  INSERT INTO public.user_preferences (user_id, active_company_id)
  VALUES (v_user_id, v_company_id)
  ON CONFLICT (user_id) DO UPDATE SET
    active_company_id = excluded.active_company_id,
    updated_at = now();

  INSERT INTO public.profiles (id, email, full_name, current_company_id)
  VALUES (v_user_id, NULLIF(trim(p_email), ''), NULLIF(trim(p_full_name), ''), v_company_id)
  ON CONFLICT (id) DO UPDATE SET
    email = coalesce(NULLIF(trim(EXCLUDED.email), ''), public.profiles.email),
    full_name = coalesce(NULLIF(trim(EXCLUDED.full_name), ''), public.profiles.full_name),
    current_company_id = v_company_id,
    updated_at = now();

  v_result := jsonb_build_object(
    'company_id', v_company_id,
    'company_name', p_company_name,
    'invite_code', v_invite_code,
    'role', 'owner'
  );

  RETURN v_result;
END;
$$;

DROP FUNCTION IF EXISTS public.join_company_as_manager(uuid, text, text);
DROP FUNCTION IF EXISTS public.join_company_as_manager(uuid, text, text, text);
DROP FUNCTION IF EXISTS public.join_company_as_manager(text, text, text);

CREATE OR REPLACE FUNCTION public.join_company_as_manager(
  p_invite_code text,
  p_full_name   text DEFAULT '',
  p_email       text DEFAULT ''
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_company_id uuid;
  v_company_name text;
  v_is_active boolean;
  v_membership_active boolean;
  v_result jsonb;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  SELECT id, name, is_active
  INTO v_company_id, v_company_name, v_is_active
  FROM public.companies
  WHERE invite_code = upper(trim(p_invite_code));

  IF v_company_id IS NULL THEN
    RAISE EXCEPTION 'INVALID_INVITE_CODE: No company found for invite code %', p_invite_code;
  END IF;

  IF NOT v_is_active THEN
    RAISE EXCEPTION 'COMPANY_INACTIVE: This business account is not active';
  END IF;

  SELECT cu.is_active
  INTO v_membership_active
  FROM public.company_users cu
  WHERE cu.company_id = v_company_id
    AND cu.user_id = v_user_id
  LIMIT 1;

  IF FOUND THEN
    RETURN jsonb_build_object(
      'company_id', v_company_id,
      'company_name', v_company_name,
      'role', 'manager',
      'is_active', coalesce(v_membership_active, false)
    );
  END IF;

  INSERT INTO public.company_users (company_id, user_id, role, is_active)
  VALUES (v_company_id, v_user_id, 'manager', false);

  INSERT INTO public.profiles (id, email, full_name)
  VALUES (v_user_id, NULLIF(trim(p_email), ''), NULLIF(trim(p_full_name), ''))
  ON CONFLICT (id) DO UPDATE SET
    email = coalesce(NULLIF(trim(EXCLUDED.email), ''), public.profiles.email),
    full_name = coalesce(NULLIF(trim(EXCLUDED.full_name), ''), public.profiles.full_name),
    updated_at = now();

  v_result := jsonb_build_object(
    'company_id', v_company_id,
    'company_name', v_company_name,
    'role', 'manager',
    'is_active', false
  );

  RETURN v_result;
END;
$$;

REVOKE ALL ON FUNCTION public.create_company_with_owner(text, text, text, text, text, text, text, text, text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.create_company_with_owner(text, text, text, text, text, text, text, text, text, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.create_company_with_owner(text, text, text, text, text, text, text, text, text, text) TO authenticated;

REVOKE ALL ON FUNCTION public.join_company_as_manager(text, text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.join_company_as_manager(text, text, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.join_company_as_manager(text, text, text) TO authenticated;

NOTIFY pgrst, 'reload schema';

COMMIT;
