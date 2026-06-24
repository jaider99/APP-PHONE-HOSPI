-- ============================================================================
-- P4.4: Tenant-scoped audit logging for sensitive operations
-- ============================================================================

BEGIN;

ALTER TABLE public.activity_logs
  ADD COLUMN IF NOT EXISTS outcome text NOT NULL DEFAULT 'success',
  ADD COLUMN IF NOT EXISTS correlation_id text,
  ADD COLUMN IF NOT EXISTS metadata jsonb NOT NULL DEFAULT '{}'::jsonb;

ALTER TABLE public.activity_logs
  DROP CONSTRAINT IF EXISTS activity_logs_outcome_check;

ALTER TABLE public.activity_logs
  ADD CONSTRAINT activity_logs_outcome_check
  CHECK (outcome IN ('success', 'failure', 'denied'));

CREATE INDEX IF NOT EXISTS idx_activity_logs_correlation
  ON public.activity_logs (company_id, correlation_id)
  WHERE correlation_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_activity_logs_security_actions
  ON public.activity_logs (company_id, action, created_at DESC)
  WHERE action LIKE 'security.%';

CREATE OR REPLACE FUNCTION public.redact_audit_payload(p_payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v_payload jsonb := coalesce(p_payload, '{}'::jsonb);
BEGIN
  RETURN v_payload
    - 'file_url'
    - 'signed_url'
    - 'signedUrl'
    - 'signedURL'
    - 'token'
    - 'jwt'
    - 'authorization'
    - 'api_key'
    - 'apiKey'
    - 'OPENROUTER_API_KEY'
    - 'raw_text'
    - 'raw_ocr_text'
    - 'ocr_text'
    - 'raw_ai_response'
    - 'ai_response'
    - 'response_body'
    - 'document_contents'
    - 'document_content'
    - 'extraction_clean'
    - 'notes'
    - 'file_path'
    - 'storage_path';
END;
$$;

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
BEGIN
  IF p_outcome NOT IN ('success', 'failure', 'denied') THEN
    RAISE EXCEPTION 'Invalid audit outcome';
  END IF;

  IF v_role NOT IN ('postgres', 'service_role', 'supabase_admin') THEN
    IF v_actor_id IS NULL OR NOT (p_company_id = ANY(public.user_company_ids())) THEN
      RAISE EXCEPTION 'Unauthorized';
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

GRANT EXECUTE ON FUNCTION public.record_security_audit_event(uuid, text, text, uuid, text, text, jsonb) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.log_activity()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    INSERT INTO public.activity_logs (company_id, user_id, action, entity_type, entity_id, new_data)
    VALUES (
      NEW.company_id,
      auth.uid(),
      'create',
      TG_TABLE_NAME,
      NEW.id,
      public.redact_audit_payload(to_jsonb(NEW))
    );
  ELSIF TG_OP = 'UPDATE' THEN
    INSERT INTO public.activity_logs (company_id, user_id, action, entity_type, entity_id, old_data, new_data)
    VALUES (
      NEW.company_id,
      auth.uid(),
      'update',
      TG_TABLE_NAME,
      NEW.id,
      public.redact_audit_payload(to_jsonb(OLD)),
      public.redact_audit_payload(to_jsonb(NEW))
    );
  ELSIF TG_OP = 'DELETE' THEN
    INSERT INTO public.activity_logs (company_id, user_id, action, entity_type, entity_id, old_data)
    VALUES (
      OLD.company_id,
      auth.uid(),
      'delete',
      TG_TABLE_NAME,
      OLD.id,
      public.redact_audit_payload(to_jsonb(OLD))
    );
  END IF;

  RETURN coalesce(NEW, OLD);
END;
$$;

DROP POLICY IF EXISTS "activity_logs_isolation" ON public.activity_logs;
DROP POLICY IF EXISTS "activity_logs_insert" ON public.activity_logs;
DROP POLICY IF EXISTS "Company members can view activity logs" ON public.activity_logs;
DROP POLICY IF EXISTS "System can insert activity logs" ON public.activity_logs;

ALTER TABLE public.activity_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.activity_logs FORCE ROW LEVEL SECURITY;

CREATE POLICY "activity_logs_select_tenant"
  ON public.activity_logs
  FOR SELECT
  TO authenticated
  USING (company_id = ANY(public.user_company_ids()));

CREATE POLICY "activity_logs_insert_tenant"
  ON public.activity_logs
  FOR INSERT
  TO authenticated
  WITH CHECK (company_id = ANY(public.user_company_ids()));

GRANT SELECT ON public.activity_logs TO authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.activity_logs FROM authenticated;

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
      v_action := 'security.member.invite';
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

DROP TRIGGER IF EXISTS audit_company_users_sensitive_changes ON public.company_users;
CREATE TRIGGER audit_company_users_sensitive_changes
  AFTER INSERT OR UPDATE ON public.company_users
  FOR EACH ROW EXECUTE FUNCTION public.audit_company_sensitive_changes();

DROP TRIGGER IF EXISTS audit_company_settings_changes ON public.companies;
CREATE TRIGGER audit_company_settings_changes
  AFTER UPDATE ON public.companies
  FOR EACH ROW EXECUTE FUNCTION public.audit_company_sensitive_changes();

CREATE OR REPLACE FUNCTION public.audit_document_category_override()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF OLD.category_id IS DISTINCT FROM NEW.category_id THEN
    PERFORM public.record_security_audit_event(
      NEW.company_id,
      'security.document.category_override',
      'document',
      NEW.id,
      'success',
      NULL,
      jsonb_build_object(
        'old_category_id', OLD.category_id,
        'new_category_id', NEW.category_id,
        'ai_category_id', NEW.ai_category_id,
        'category_confidence', NEW.category_confidence
      )
    );
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS audit_document_category_override ON public.documents;
CREATE TRIGGER audit_document_category_override
  AFTER UPDATE OF category_id ON public.documents
  FOR EACH ROW EXECUTE FUNCTION public.audit_document_category_override();

CREATE OR REPLACE FUNCTION public.audit_expense_category_override()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF OLD.category_id IS DISTINCT FROM NEW.category_id THEN
    PERFORM public.record_security_audit_event(
      NEW.company_id,
      'security.expense.category_override',
      'expense',
      NEW.id,
      'success',
      NULL,
      jsonb_build_object(
        'document_id', NEW.document_id,
        'old_category_id', OLD.category_id,
        'new_category_id', NEW.category_id,
        'category_confidence', NEW.category_confidence
      )
    );
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS audit_expense_category_override ON public.expenses;
CREATE TRIGGER audit_expense_category_override
  AFTER UPDATE OF category_id ON public.expenses
  FOR EACH ROW EXECUTE FUNCTION public.audit_expense_category_override();

CREATE OR REPLACE FUNCTION public.delete_document_cascade(
  p_document_id uuid,
  p_company_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_document_id uuid;
BEGIN
  SELECT d.id
    INTO v_document_id
  FROM public.documents d
  WHERE d.id = p_document_id
    AND d.company_id = p_company_id
    AND d.deleted_at IS NULL
  FOR UPDATE;

  IF v_document_id IS NULL THEN
    PERFORM public.record_security_audit_event(
      p_company_id,
      'security.document.delete',
      'document',
      p_document_id,
      'denied',
      NULL,
      jsonb_build_object('reason', 'not_found_or_unauthorized')
    );
    RAISE EXCEPTION 'Document not found or unauthorized';
  END IF;

  UPDATE public.documents
  SET duplicate_of = NULL,
      is_duplicate = FALSE
  WHERE company_id = p_company_id
    AND duplicate_of = p_document_id
    AND deleted_at IS NULL;

  DELETE FROM public.document_items
  WHERE document_id = p_document_id
    AND company_id = p_company_id;

  DELETE FROM public.expenses
  WHERE document_id = p_document_id
    AND company_id = p_company_id;

  UPDATE public.documents
  SET deleted_at = now(),
      duplicate_of = NULL
  WHERE id = p_document_id
    AND company_id = p_company_id
    AND deleted_at IS NULL;

  PERFORM public.record_security_audit_event(
    p_company_id,
    'security.document.delete',
    'document',
    p_document_id,
    'success',
    NULL,
    jsonb_build_object('soft_deleted', true)
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.delete_document_cascade(uuid, uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.resolve_price_anomaly(
  p_company_id uuid,
  p_anomaly_id uuid,
  p_resolution_status price_anomaly_resolution_status,
  p_resolution_note text DEFAULT NULL
)
RETURNS price_anomalies
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row price_anomalies;
BEGIN
  IF NOT (p_company_id = ANY(public.user_company_ids())) THEN
    PERFORM public.record_security_audit_event(
      p_company_id,
      'security.anomaly.resolve',
      'price_anomaly',
      p_anomaly_id,
      'denied',
      NULL,
      jsonb_build_object('reason', 'unauthorized', 'requested_status', p_resolution_status)
    );
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  UPDATE public.price_anomalies
     SET resolved = p_resolution_status <> 'open',
         resolution_status = p_resolution_status,
         resolution_note = p_resolution_note,
         resolved_at = CASE WHEN p_resolution_status = 'open' THEN NULL ELSE now() END,
         resolved_by = CASE WHEN p_resolution_status = 'open' THEN NULL ELSE auth.uid() END
   WHERE id = p_anomaly_id
     AND company_id = p_company_id
   RETURNING * INTO v_row;

  IF NOT FOUND THEN
    PERFORM public.record_security_audit_event(
      p_company_id,
      'security.anomaly.resolve',
      'price_anomaly',
      p_anomaly_id,
      'denied',
      NULL,
      jsonb_build_object('reason', 'not_found', 'requested_status', p_resolution_status)
    );
    RAISE EXCEPTION 'Anomaly not found';
  END IF;

  IF p_resolution_status = 'baseline_approved' THEN
    UPDATE public.product_price_stats
       SET baseline_price = v_row.current_price,
           baseline_approved_at = now(),
           updated_at = now()
     WHERE company_id = v_row.company_id
       AND product_id = v_row.product_id;
  END IF;

  PERFORM public.record_security_audit_event(
    p_company_id,
    'security.anomaly.resolve',
    'price_anomaly',
    p_anomaly_id,
    'success',
    NULL,
    jsonb_build_object(
      'resolution_status', p_resolution_status,
      'product_id', v_row.product_id,
      'supplier_id', v_row.supplier_id,
      'severity', v_row.severity
    )
  );

  RETURN v_row;
END;
$$;

GRANT EXECUTE ON FUNCTION public.resolve_price_anomaly(uuid, uuid, price_anomaly_resolution_status, text) TO authenticated;

COMMIT;